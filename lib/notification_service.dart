import 'dart:async';
import 'dart:convert';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'firebase_options.dart';

String sanitizedException(
  Object error, {
  Iterable<String?> secrets = const [],
}) {
  final type = error.runtimeType.toString();
  var message = error.toString();

  for (final secret in secrets) {
    if (secret != null && secret.isNotEmpty) {
      message = message.replaceAll(secret, '[REDACTED]');
    }
  }

  message = message
      .replaceAll(
        RegExp(r'Bearer\s+[^\s,;]+', caseSensitive: false),
        'Bearer [REDACTED]',
      )
      .replaceAll(
        RegExp(
          r'(sanctum_token|fcm_token|token)\s*[:=]\s*[^\s,;}]+',
          caseSensitive: false,
        ),
        r'$1=[REDACTED]',
      )
      .replaceAll(RegExp(r'[\r\n]+'), ' ')
      .trim();

  final typePrefix = '$type:';
  if (message.startsWith(typePrefix)) {
    message = message.substring(typePrefix.length).trim();
  }
  if (message.length > 300) message = '${message.substring(0, 300)}…';
  return message.isEmpty ? type : '$type: $message';
}

const AndroidNotificationChannel _notificationChannel =
    AndroidNotificationChannel(
      'daydispatch_notifications',
      'DayDispatch notifications',
      description: 'Delivery updates and important DayDispatch alerts.',
      importance: Importance.high,
    );

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
}

class NotificationDestination {
  const NotificationDestination({
    required this.type,
    required this.destinationUrl,
  });

  final String type;
  final String destinationUrl;

  static NotificationDestination? fromData(Map<String, dynamic> data) {
    final type = data['type']?.toString();
    final destinationUrl = switch (type) {
      'chat_notification' => data['chat_url']?.toString().trim(),
      'order_notification' => data['order_url']?.toString().trim(),
      _ => null,
    };
    if (type == null ||
        destinationUrl == null ||
        !_isSafeRelativePath(destinationUrl)) {
      debugPrint(
        'FCM destination rejected: invalid or missing data for type=$type',
      );
      return null;
    }
    return NotificationDestination(type: type, destinationUrl: destinationUrl);
  }

  Map<String, String> toJson() => {
    'type': type,
    if (type == 'chat_notification') 'chat_url': destinationUrl,
    if (type == 'order_notification') 'order_url': destinationUrl,
  };

  static bool _isSafeRelativePath(String value) {
    if (!value.startsWith('/') ||
        value.startsWith('//') ||
        value.contains(r'\')) {
      return false;
    }
    final uri = Uri.tryParse(value);
    return uri != null && !uri.hasScheme && !uri.hasAuthority;
  }
}

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final http.Client _httpClient = http.Client();
  final StreamController<NotificationDestination> _destinations =
      StreamController<NotificationDestination>.broadcast();

  StreamSubscription<String>? _tokenRefreshSubscription;
  NotificationDestination? _pendingDestination;
  Uri? _apiBaseUri;
  String? _bearerToken;
  String? _registeredFcmToken;
  bool _initialized = false;
  Completer<void>? _authOperation;

  Stream<NotificationDestination> get destinations => _destinations.stream;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    try {
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      );
      await _localNotifications.initialize(
        settings: settings,
        onDidReceiveNotificationResponse: _handleLocalNotificationTap,
      );

      final localLaunchDetails = await _localNotifications
          .getNotificationAppLaunchDetails();
      if (localLaunchDetails?.didNotificationLaunchApp == true) {
        _handleLocalNotificationTap(
          localLaunchDetails!.notificationResponse ??
              const NotificationResponse(
                notificationResponseType:
                    NotificationResponseType.selectedNotification,
              ),
        );
      }

      await _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(_notificationChannel);

      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
            alert: true,
            badge: true,
            sound: true,
          );

      FirebaseMessaging.onMessage.listen(_showForegroundNotification);
      FirebaseMessaging.onMessageOpenedApp.listen(_handleRemoteMessageTap);

      final initialMessage = await FirebaseMessaging.instance
          .getInitialMessage();
      if (initialMessage != null) _handleRemoteMessageTap(initialMessage);
    } catch (error) {
      debugPrint(
        'Push notification initialization failed: '
        '${sanitizedException(error)}',
      );
    }
  }

  Future<bool> authenticate({
    required String sanctumToken,
    required Uri apiBaseUri,
  }) async {
    if (sanctumToken.trim().isEmpty ||
        !{'http', 'https'}.contains(apiBaseUri.scheme)) {
      debugPrint('Push registration skipped: authentication data is invalid.');
      return false;
    }
    if (_authOperation != null) {
      debugPrint('Push registration skipped: another operation is active.');
      return false;
    }

    debugPrint('Push registration started after authenticated login.');

    final operation = Completer<void>();
    _authOperation = operation;
    _bearerToken = sanctumToken.trim();
    _apiBaseUri = apiBaseUri;

    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      debugPrint(
        'Push notification permission status: '
        '${settings.authorizationStatus.name}',
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint(
          'Push registration stopped: notification permission denied.',
        );
        return false;
      }

      if (defaultTargetPlatform == TargetPlatform.iOS) {
        String? apnsToken = await FirebaseMessaging.instance.getAPNSToken();
        int attempts = 0;
        while (apnsToken == null && attempts < 10) {
          await Future.delayed(const Duration(milliseconds: 500));
          apnsToken = await FirebaseMessaging.instance.getAPNSToken();
          attempts++;
        }
        debugPrint('APNs token available: ${apnsToken != null && apnsToken.isNotEmpty}');
      }

      final fcmToken = await FirebaseMessaging.instance.getToken();
      debugPrint(
        'Firebase messaging token available: '
        '${fcmToken != null && fcmToken.isNotEmpty}',
      );
      if (fcmToken == null || fcmToken.isEmpty) return false;

      final registered = await _registerToken(fcmToken);
      if (!registered) return false;

      _registeredFcmToken = fcmToken;
      _tokenRefreshSubscription ??= FirebaseMessaging.instance.onTokenRefresh
          .listen(_handleTokenRefresh);
      return true;
    } catch (error) {
      debugPrint(
        'Push notification registration failed: '
        '${sanitizedException(error, secrets: [_bearerToken])}',
      );
      return false;
    } finally {
      operation.complete();
      if (identical(_authOperation, operation)) _authOperation = null;
    }
  }

  Future<void> logout() async {
    final activeOperation = _authOperation;
    if (activeOperation != null) await activeOperation.future;

    final operation = Completer<void>();
    _authOperation = operation;

    try {
      final token =
          _registeredFcmToken ?? await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) await _deleteToken(token);
    } catch (error) {
      debugPrint(
        'Push notification logout cleanup failed: '
        '${sanitizedException(error, secrets: [_bearerToken, _registeredFcmToken])}',
      );
    } finally {
      _registeredFcmToken = null;
      _bearerToken = null;
      _apiBaseUri = null;
      await _tokenRefreshSubscription?.cancel();
      _tokenRefreshSubscription = null;
      operation.complete();
      if (identical(_authOperation, operation)) _authOperation = null;
    }
  }

  void flushPendingDestination() {
    final destination = _pendingDestination;
    if (destination == null || _destinations.isClosed) return;
    _pendingDestination = null;
    _destinations.add(destination);
  }

  Future<void> _handleTokenRefresh(String newToken) async {
    if (_bearerToken == null || _apiBaseUri == null || newToken.isEmpty) return;

    final oldToken = _registeredFcmToken;
    if (await _registerToken(newToken)) {
      _registeredFcmToken = newToken;
      if (oldToken != null && oldToken != newToken) {
        await _deleteToken(oldToken);
      }
    }
  }

  Future<bool> _registerToken(String fcmToken) async {
    final bearerToken = _bearerToken;
    final endpoint = _deviceEndpoint;
    if (bearerToken == null || endpoint == null) return false;

    try {
      debugPrint('FCM device registration POST starting: $endpoint');
      final response = await _httpClient
          .post(
            endpoint,
            headers: _headers(bearerToken),
            body: jsonEncode({
              'token': fcmToken,
              'platform': _platformName,
              'device_name': await _deviceName(),
            }),
          )
          .timeout(const Duration(seconds: 15));
      debugPrint(
        'FCM device registration POST completed: HTTP ${response.statusCode}',
      );
      if (response.statusCode >= 200 && response.statusCode < 300) return true;
      debugPrint(
        'FCM device registration rejected (${response.statusCode}): '
        '${_safeApiMessage(response.body, secrets: [bearerToken, fcmToken])}',
      );
    } catch (error) {
      debugPrint(
        'FCM device registration POST failed: '
        '${sanitizedException(error, secrets: [bearerToken, fcmToken])}',
      );
    }
    return false;
  }

  Future<bool> _deleteToken(String fcmToken) async {
    final bearerToken = _bearerToken;
    final endpoint = _deviceEndpoint;
    if (bearerToken == null || endpoint == null) return false;

    try {
      final request = http.Request('DELETE', endpoint)
        ..headers.addAll(_headers(bearerToken))
        ..body = jsonEncode({'token': fcmToken});
      final streamedResponse = await _httpClient
          .send(request)
          .timeout(const Duration(seconds: 15));
      final response = await http.Response.fromStream(streamedResponse);
      if (response.statusCode >= 200 && response.statusCode < 300) return true;
      debugPrint(
        'FCM device removal rejected (${response.statusCode}): '
        '${_safeApiMessage(response.body)}',
      );
    } catch (error) {
      debugPrint(
        'FCM device removal network error: '
        '${sanitizedException(error, secrets: [bearerToken, fcmToken])}',
      );
    }
    return false;
  }

  Uri? get _deviceEndpoint {
    final base = _apiBaseUri;
    if (base == null) return null;
    final cleanPath = base.path.replaceAll(RegExp(r'/+$'), '');
    final apiPath = cleanPath.endsWith('/api')
        ? '$cleanPath/fcm/devices'
        : '$cleanPath/api/fcm/devices';
    return base.replace(path: apiPath, query: null, fragment: null);
  }

  Map<String, String> _headers(String bearerToken) => {
    'Authorization': 'Bearer $bearerToken',
    'Accept': 'application/json',
    'Content-Type': 'application/json',
  };

  String get _platformName =>
      defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

  Future<String> _deviceName() async {
    try {
      final info = DeviceInfoPlugin();
      if (defaultTargetPlatform == TargetPlatform.android) {
        final android = await info.androidInfo;
        return '${android.manufacturer} ${android.model}'.trim();
      }
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final ios = await info.iosInfo;
        return ios.name.trim().isEmpty ? ios.model : ios.name.trim();
      }
    } catch (error) {
      debugPrint('Device name is unavailable: ${sanitizedException(error)}');
    }
    return 'DayDispatch mobile app';
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    // Android notifications are displayed by the native Kotlin FCM service.
    // Keeping display in one layer prevents duplicate foreground alerts.
    if (defaultTargetPlatform == TargetPlatform.android) return;
    final notification = message.notification;
    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      if (notification != null) return;
    }

    final destination = NotificationDestination.fromData(message.data);
    final title = notification?.title ?? message.data['title']?.toString();
    final body = notification?.body ?? message.data['body']?.toString();
    await _localNotifications.show(
      id: message.messageId?.hashCode ?? message.hashCode,
      title: title?.isNotEmpty == true ? title : 'DayDispatch',
      body: body?.isNotEmpty == true ? body : 'You have a new update.',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _notificationChannel.id,
          _notificationChannel.name,
          channelDescription: _notificationChannel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: destination == null ? null : jsonEncode(destination.toJson()),
    );
  }

  void _handleRemoteMessageTap(RemoteMessage message) {
    final destination = NotificationDestination.fromData(message.data);
    if (destination != null) _emitDestination(destination);
  }

  void _handleLocalNotificationTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    try {
      final data = jsonDecode(payload);
      if (data is Map<String, dynamic>) {
        final destination = NotificationDestination.fromData(data);
        if (destination != null) _emitDestination(destination);
      }
    } on FormatException {
      debugPrint('Ignored an invalid local notification payload.');
    }
  }

  void _emitDestination(NotificationDestination destination) {
    if (_destinations.hasListener) {
      _destinations.add(destination);
    } else {
      _pendingDestination = destination;
    }
  }

  String _safeApiMessage(
    String responseBody, {
    Iterable<String?> secrets = const [],
  }) {
    try {
      final decoded = jsonDecode(responseBody);
      if (decoded is Map<String, dynamic>) {
        var message = (decoded['message'] ?? 'API validation failed')
            .toString();
        for (final secret in secrets) {
          if (secret != null && secret.isNotEmpty) {
            message = message.replaceAll(secret, '[REDACTED]');
          }
        }
        return message.length > 300 ? '${message.substring(0, 300)}…' : message;
      }
    } on FormatException {
      // Do not log arbitrary HTML or server output.
    }
    return 'API request failed';
  }
}
