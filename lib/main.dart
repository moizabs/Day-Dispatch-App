import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'firebase_options.dart';
import 'notification_service.dart';

const String kDayDispatchUrl =
    'https://daydispatch.com/Authentication/Login-Form';
const Color kDayDispatchRed = Color(0xFFE01F26);
const Color kDayDispatchNavy = Color(0xFF1F2E63);
const Color kDayDispatchSurface = Color(0xFFF7F8FB);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  // SystemChrome.setSystemUIOverlayStyle(
  //   const SystemUiOverlayStyle(
  //     statusBarColor: Colors.transparent,
  //     statusBarIconBrightness: Brightness.dark,
  //     statusBarBrightness: Brightness.light,
  //   ),
  // );
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await NotificationService.instance.initialize();
  runApp(const DayDispatchApp());
}

class DayDispatchApp extends StatefulWidget {
  const DayDispatchApp({super.key});

  @override
  State<DayDispatchApp> createState() => _DayDispatchAppState();
}

class _DayDispatchAppState extends State<DayDispatchApp> {
  bool _showSplash = true;
  Timer? _startupTimer;
  Timer? _webViewReadyTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_requestInitialPermissions());
    });
    _startupTimer = Timer(const Duration(milliseconds: 3600), () {
      if (mounted) {
        setState(() => _showSplash = false);
      }
    });
  }

  Future<void> _requestInitialPermissions() async {
    try {
      final permissions = <Permission>[
        Permission.notification,
        Permission.camera,
        Permission.photos,
        Permission.videos,
        Permission.storage,
        Permission.microphone,
      ];
      final statuses = await permissions.request();
      debugPrint('Initial permissions statuses: $statuses');
    } catch (error) {
      debugPrint('Initial permissions request error: $error');
    }
  }

  @override
  void dispose() {
    _startupTimer?.cancel();
    _webViewReadyTimer?.cancel();
    super.dispose();
  }

  void _handleWebViewReady() {
    if (!mounted || !_showSplash) return;
    _webViewReadyTimer?.cancel();
    _webViewReadyTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) {
        setState(() => _showSplash = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp( 
      title: 'DayDispatch',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: kDayDispatchSurface,
        colorScheme: ColorScheme.fromSeed(
          seedColor: kDayDispatchNavy,
          primary: kDayDispatchNavy,
          secondary: kDayDispatchRed,
          brightness: Brightness.light,
        ),
      ),
      home: Stack(
        children: [
          DayDispatchWebViewPage(onWebViewReady: _handleWebViewReady),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 900),
            switchOutCurve: Curves.easeInOutCubic,
            child: _showSplash
                ? const DayDispatchSplashScreen(key: ValueKey('splash'))
                : const SizedBox.shrink(key: ValueKey('content')),
          ),
        ],
      ),
    );
  }
}

class DayDispatchSplashScreen extends StatefulWidget {
  const DayDispatchSplashScreen({super.key});

  @override
  State<DayDispatchSplashScreen> createState() =>
      _DayDispatchSplashScreenState();
}

class _DayDispatchSplashScreenState extends State<DayDispatchSplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _controller;
  late final AnimationController _loaderController;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _scaleAnimation;
  late final Animation<Offset> _textSlideAnimation;
  late final Animation<double> _textFadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _loaderController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _scaleAnimation = Tween<double>(
      begin: 0.9,
      end: 1,
    ).chain(CurveTween(curve: Curves.easeOutCubic)).animate(_controller);
    _textSlideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.22), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _controller,
            curve: const Interval(0.32, 1, curve: Curves.easeOutCubic),
          ),
        );
    _textFadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.28, 0.85, curve: Curves.easeOut),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _loaderController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFAFBFF), Color(0xFFF0F3FA)],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            top: -120,
            right: -100,
            child: _AmbientOrb(color: kDayDispatchRed, size: 300),
          ),
          Positioned(
            bottom: -150,
            left: -120,
            child: _AmbientOrb(color: kDayDispatchNavy, size: 360),
          ),
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedBuilder(
                      animation: Listenable.merge([
                        _controller,
                        _loaderController,
                      ]),
                      builder: (context, child) => Transform.translate(
                        offset: Offset(0, 12 * (1 - _fadeAnimation.value)),
                        child: Transform.scale(
                          scale: _scaleAnimation.value,
                          child: Opacity(
                            opacity: _fadeAnimation.value,
                            child: Container(
                              width: 112,
                              height: 112,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.96),
                                borderRadius: BorderRadius.circular(30),
                                border: Border.all(
                                  color: Colors.white,
                                  width: 1.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: kDayDispatchNavy.withValues(
                                      alpha:
                                          0.08 +
                                          (_loaderController.value * 0.04),
                                    ),
                                    blurRadius:
                                        28 + (_loaderController.value * 10),
                                    offset: const Offset(0, 14),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(19),
                                child: Image.asset(
                                  'assets/images/daydispatch_logo.webp',
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, _, _) => const Icon(
                                    Icons.local_shipping_rounded,
                                    size: 48,
                                    color: kDayDispatchRed,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    FadeTransition(
                      opacity: _textFadeAnimation,
                      child: SlideTransition(
                        position: _textSlideAnimation,
                        child: Column(
                          children: [
                            const SizedBox(height: 30),
                            // const Text(
                            //   'DayDispatch',
                            //   style: TextStyle(
                            //     fontSize: 31,
                            //     height: 1,
                            //     fontWeight: FontWeight.w800,
                            //     letterSpacing: -1,
                            //     color: kDayDispatchNavy,
                            //   ),
                            // ),
                            // const SizedBox(height: 11),
                            // const Text(
                            //   'Delivery management, simplified.',
                            //   textAlign: TextAlign.center,
                            //   style: TextStyle(
                            //     fontSize: 14,
                            //     height: 1.4,
                            //     fontWeight: FontWeight.w500,
                            //     letterSpacing: 0.15,
                            //     color: Color(0xFF737C99),
                            //   ),
                            // ),
                            // const SizedBox(height: 34),
                            SizedBox(
                              width: 120,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(99),
                                child: const LinearProgressIndicator(
                                  minHeight: 3,
                                  backgroundColor: Color(0xFFE1E5EF),
                                  valueColor: AlwaysStoppedAnimation(
                                    kDayDispatchRed,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AmbientOrb extends StatelessWidget {
  const _AmbientOrb({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color.withValues(alpha: 0.09), color.withValues(alpha: 0)],
        ),
      ),
    );
  }
}

class DayDispatchWebViewPage extends StatefulWidget {
  const DayDispatchWebViewPage({super.key, this.onWebViewReady});

  final VoidCallback? onWebViewReady;

  @override
  State<DayDispatchWebViewPage> createState() => _DayDispatchWebViewPageState();
}

class _DayDispatchWebViewPageState extends State<DayDispatchWebViewPage> {
  static const _nativeNotificationChannel = MethodChannel(
    'com.daydispatch.app/notifications',
  );
  late final WebViewController _controller;
  final Connectivity _connectivity = Connectivity();
  late final StreamSubscription<List<ConnectivityResult>>
  _connectivitySubscription;
  late final StreamSubscription<NotificationDestination>
  _notificationSubscription;

  bool _loading = true;
  bool _offline = false;
  bool _authenticationBridgeInstalled = false;
  bool _authenticationBridgeInstalling = false;
  bool _webViewReady = false;
  bool _canPullToRefresh = false;
  bool _refreshing = false;
  final GlobalKey _webViewGestureKey = GlobalKey();
  int? _pullPointer;
  double _pullStartY = 0;
  double _pullDistance = 0;
  NotificationDestination? _pendingNotificationDestination;
  int _progress = 0;

  static const double _refreshTriggerDistance = 150;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setUserAgent(
        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1 DayDispatchApp/1.0',
      )
      ..addJavaScriptChannel(
        'DayDispatchAuth',
        onMessageReceived: (message) {
          debugPrint('DayDispatch authentication channel message received.');
          unawaited(_handleAuthenticationMessage(message.message));
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            if (!mounted) return;
            setState(() {
              _progress = progress;
              _loading = progress < 100;
            });
            // Laravel starts looking for the bridge while the document is
            // still loading. Install it early so slow assets cannot make the
            // website exhaust its login retry window.
            if (progress >= 10 && !_authenticationBridgeInstalled) {
              unawaited(_installAuthenticationBridge());
            }
          },
          onPageStarted: (String url) {
            _webViewReady = false;
            _authenticationBridgeInstalled = false;
            _authenticationBridgeInstalling = false;
            setState(() {
              _loading = true;
              _progress = 0;
              _offline = false;
            });
          },
          onPageFinished: (String url) {
            _webViewReady = true;
            setState(() {
              _loading = false;
              _progress = 100;
              _offline = false;
              _refreshing = false;
              _pullDistance = 0;
            });
            widget.onWebViewReady?.call();
            unawaited(_installAuthenticationBridge());
            final pendingDestination = _pendingNotificationDestination;
            if (pendingDestination != null) {
              _pendingNotificationDestination = null;
              unawaited(_openNotificationDestination(pendingDestination));
            }
          },
          onWebResourceError: (WebResourceError error) {
            // A page can still be usable when an image, script, iframe, or
            // analytics request fails. Only replace the whole WebView when the
            // main document itself could not load.
            if (error.isForMainFrame != true || !mounted) return;
            setState(() {
              _loading = false;
              _offline = true;
              _refreshing = false;
              _pullDistance = 0;
            });
          },
          onNavigationRequest: (NavigationRequest request) {
            final uri = Uri.tryParse(request.url);
            if (uri == null) return NavigationDecision.prevent;

            const externalSchemes = {'tel', 'mailto', 'sms', 'whatsapp'};
            if (externalSchemes.contains(uri.scheme.toLowerCase())) {
              unawaited(launchUrl(uri, mode: LaunchMode.externalApplication));
              return NavigationDecision.prevent;
            }

            // Keep website, authentication, payment, and redirect pages inside
            // the app instead of unexpectedly switching to Chrome.
            if (uri.scheme == 'http' ||
                uri.scheme == 'https' ||
                uri.scheme == 'about' ||
                uri.scheme == 'data') {
              return NavigationDecision.navigate;
            }

            unawaited(launchUrl(uri, mode: LaunchMode.externalApplication));
            return NavigationDecision.prevent;
          },
        ),
      );

    if (_controller.platform is AndroidWebViewController) {
      (_controller.platform as AndroidWebViewController)
          .setOnShowFileSelector(_androidFilePicker);
    }

    _connectivitySubscription = _connectivity.onConnectivityChanged.listen((
      results,
    ) {
      if (!mounted) return;
      setState(() => _offline = results.contains(ConnectivityResult.none));
    });
    _notificationSubscription = NotificationService.instance.destinations
        .listen(_openNotificationDestination);
    NotificationService.instance.flushPendingDestination();
    unawaited(_initializeNativeNotificationNavigation());

    unawaited(_initializeWebView());
  }

  Future<void> _initializeNativeNotificationNavigation() async {
    _nativeNotificationChannel.setMethodCallHandler((call) async {
      if (call.method != 'openNotificationDestination') return;
      final destination = _destinationFromNativeArguments(call.arguments);
      if (destination != null) await _openNotificationDestination(destination);
    });
    try {
      final initial = await _nativeNotificationChannel
          .invokeMapMethod<String, dynamic>('getInitialDestination');
      final destination = _destinationFromNativeArguments(initial);
      if (destination != null) await _openNotificationDestination(destination);
    } on MissingPluginException {
      // Non-Android platforms use the Firebase Messaging Dart callbacks.
    }
  }

  Future<List<String>> _androidFilePicker(FileSelectorParams params) async {
    try {
      final allowMultiple = params.mode == FileSelectorMode.openMultiple;

      FileType fileType = FileType.any;
      final acceptTypes = params.acceptTypes;
      if (acceptTypes.isNotEmpty) {
        final isOnlyImage = acceptTypes.every((t) => t.startsWith('image/'));
        final isOnlyVideo = acceptTypes.every((t) => t.startsWith('video/'));
        final isOnlyAudio = acceptTypes.every((t) => t.startsWith('audio/'));
        if (isOnlyImage) {
          fileType = FileType.image;
        } else if (isOnlyVideo) {
          fileType = FileType.video;
        } else if (isOnlyAudio) {
          fileType = FileType.audio;
        }
      }

      if (allowMultiple) {
        final files = await FilePicker.pickFiles(type: fileType);
        return files
            .where((file) => file.path != null)
            .map((file) => Uri.file(file.path!).toString())
            .toList();
      } else {
        final file = await FilePicker.pickFile(type: fileType);
        if (file?.path != null) {
          return [Uri.file(file!.path!).toString()];
        }
      }
    } catch (error) {
      debugPrint('WebView Android file picker error: $error');
    }
    return <String>[];
  }

  NotificationDestination? _destinationFromNativeArguments(Object? arguments) {
    if (arguments is! Map) return null;
    return NotificationDestination.fromData({
      'type': arguments['type'],
      if (arguments['type'] == 'chat_notification')
        'chat_url': arguments['destination_url'],
      if (arguments['type'] == 'order_notification')
        'order_url': arguments['destination_url'],
    });
  }

  @override
  void dispose() {
    _connectivitySubscription.cancel();
    _notificationSubscription.cancel();
    super.dispose();
  }

  Future<void> _handleAuthenticationMessage(String rawMessage) async {
    try {
      final decoded = jsonDecode(rawMessage);
      if (decoded is! Map<String, dynamic>) {
        debugPrint(
          'DayDispatch authentication message rejected: invalid shape.',
        );
        return;
      }

      final currentUrl = await _controller.currentUrl();
      final currentUri = currentUrl == null ? null : Uri.tryParse(currentUrl);
      if (currentUri == null) {
        debugPrint(
          'DayDispatch authentication message rejected: URL unavailable.',
        );
        return;
      }
      if (!_isTrustedAppUri(currentUri)) {
        debugPrint(
          'DayDispatch authentication message rejected: untrusted origin '
          '${currentUri.scheme}://${currentUri.host}.',
        );
        return;
      }

      final event = decoded['event']?.toString();
      if (event == 'login') {
        debugPrint('DayDispatch native login bridge received.');
        final token = decoded['sanctum_token']?.toString() ?? '';
        final requestedBase = decoded['api_base_url']?.toString();
        final apiBaseUri = requestedBase == null
            ? currentUri.replace(path: '', query: null, fragment: null)
            : Uri.tryParse(requestedBase);
        if (apiBaseUri == null || apiBaseUri.host != currentUri.host) {
          debugPrint('DayDispatch native login rejected: API origin mismatch.');
          return;
        }

        final registered = await NotificationService.instance.authenticate(
          sanctumToken: token,
          apiBaseUri: apiBaseUri,
        );
        await _sendBridgeResult('daydispatch:fcm-registration', registered);
      } else if (event == 'logout') {
        await NotificationService.instance.logout();
        await _sendBridgeResult('daydispatch:fcm-logout-complete', true);
      }
    } on FormatException {
      debugPrint('Ignored an invalid DayDispatch authentication message.');
    } catch (error) {
      debugPrint(
        'DayDispatch authentication bridge failed: '
        '${sanitizedException(error)}',
      );
    }
  }

  Future<void> _installAuthenticationBridge() async {
    if (_authenticationBridgeInstalled || _authenticationBridgeInstalling) {
      return;
    }
    _authenticationBridgeInstalling = true;
    try {
      await _controller.runJavaScript('''
        (() => {
          const nativeBridge = window.dayDispatchNative || {};
          nativeBridge.login = (sanctumToken, apiBaseUrl) =>
            window.DayDispatchAuth.postMessage(
              JSON.stringify({
                event: 'login',
                sanctum_token: sanctumToken,
                api_base_url: apiBaseUrl || window.location.origin
              })
            );
          nativeBridge.logout = () => window.DayDispatchAuth.postMessage(
            JSON.stringify({ event: 'logout' })
          );
          nativeBridge.version = '1.2';
          window.dayDispatchNative = nativeBridge;
          window.dispatchEvent(new CustomEvent('daydispatch:native-ready'));
        })();
      ''');
      _authenticationBridgeInstalled = true;
      debugPrint('DayDispatch native authentication bridge installed.');
    } catch (error) {
      debugPrint(
        'DayDispatch native authentication bridge installation failed: '
        '${sanitizedException(error)}',
      );
    } finally {
      _authenticationBridgeInstalling = false;
    }
  }

  Future<void> _sendBridgeResult(String eventName, bool success) async {
    await _controller.runJavaScript(
      'window.dispatchEvent(new CustomEvent(${jsonEncode(eventName)}, '
      '{detail: {success: $success}}));',
    );
  }

  bool _isTrustedAppUri(Uri uri) {
    final initialUri = Uri.parse(kDayDispatchUrl);
    final host = uri.host.toLowerCase();
    return uri.scheme == 'https' &&
            (host == initialUri.host.toLowerCase() ||
                host == 'alaine-excitomotor-militantly.ngrok-free.dev' ||
                host.endsWith('.daydispatch.com')) ||
        uri.scheme == 'http' &&
            (host == '10.0.2.2' ||
                host == 'localhost' ||
                host == '127.0.0.1' ||
                _isPrivateDevelopmentHost(host));
  }

  bool _isPrivateDevelopmentHost(String host) {
    final parts = host.split('.').map(int.tryParse).toList();
    if (parts.length != 4 || parts.any((part) => part == null)) return false;
    final first = parts[0]!;
    final second = parts[1]!;
    return first == 10 ||
        first == 192 && second == 168 ||
        first == 172 && second >= 16 && second <= 31;
  }

  Future<void> _openNotificationDestination(
    NotificationDestination destination,
  ) async {
    if (!_webViewReady) {
      _pendingNotificationDestination = destination;
      return;
    }

    final currentUrl = await _controller.currentUrl();
    final currentUri = Uri.tryParse(currentUrl ?? kDayDispatchUrl);
    if (currentUri == null || !_isTrustedAppUri(currentUri)) return;

    final destinationUri = currentUri.resolve(destination.destinationUrl);
    if (!_isTrustedAppUri(destinationUri)) {
      debugPrint('Notification destination rejected: untrusted URI.');
      return;
    }
    debugPrint('Loading notification destination: type=${destination.type}');
    await _controller.loadRequest(destinationUri);
  }

  Future<void> _initializeWebView() async {
    final connectivity = await _connectivity.checkConnectivity();
    if (!mounted) return;
    if (connectivity.contains(ConnectivityResult.none)) {
      setState(() => _offline = true);
      return;
    }

    setState(() => _offline = false);
    await _controller.loadRequest(Uri.parse(kDayDispatchUrl));
  }

  Future<void> _retryLoad() async {
    final connectivity = await _connectivity.checkConnectivity();
    if (connectivity.contains(ConnectivityResult.none)) {
      setState(() => _offline = true);
      return;
    }

    setState(() {
      _offline = false;
      _loading = true;
    });
    await _controller.loadRequest(Uri.parse(kDayDispatchUrl));
  }

  void _startPull(PointerDownEvent event) {
    if (_offline || _loading || _pullPointer != null) return;
    _pullPointer = event.pointer;
    _pullStartY = event.position.dy;
    _canPullToRefresh = false;
    final size = _webViewGestureKey.currentContext?.size;
    if (size != null && size.width > 0 && size.height > 0) {
      unawaited(_checkPullPosition(event.pointer, event.localPosition, size));
    }
  }

  Future<void> _checkPullPosition(
    int pointer,
    Offset position,
    Size size,
  ) async {
    try {
      final result = await _controller.runJavaScriptReturningResult(
        '''
        (() => {
          const x = ${position.dx / size.width} * window.innerWidth;
          const y = ${position.dy / size.height} * window.innerHeight;
          let element = document.elementFromPoint(x, y);
          if (!element) return false;
          while (element && element !== document.documentElement &&
                 element !== document.body) {
            const style = window.getComputedStyle(element);
            // Nested scroll areas (including chat) own their entire gesture,
            // even at the top or when their content does not yet overflow.
            if (/^(auto|scroll|overlay)\$/.test(style.overflowY) ||
                element.isContentEditable ||
                /^(INPUT|TEXTAREA|SELECT|IFRAME)\$/.test(element.tagName)) {
              return false;
            }
            element = element.parentElement;
          }
          return Math.max(document.documentElement.scrollTop || 0,
                          document.body.scrollTop || 0) <= 1;
        })()
        ''',
      );
      if (mounted && _pullPointer == pointer) {
        _canPullToRefresh = result == true || result.toString() == 'true';
      }
    } catch (_) {
      if (_pullPointer == pointer) _canPullToRefresh = false;
    }
  }

  void _updatePull(PointerMoveEvent event) {
    if (_pullPointer != event.pointer || !_canPullToRefresh) return;
    final distance = (event.position.dy - _pullStartY)
        .clamp(0.0, _refreshTriggerDistance + 40)
        .toDouble();
    if (distance == _pullDistance) return;
    setState(() => _pullDistance = distance);
  }

  void _finishPull(PointerEvent event) {
    if (_pullPointer != event.pointer) return;
    final shouldRefresh =
        event is PointerUpEvent &&
        _canPullToRefresh &&
        _pullDistance >= _refreshTriggerDistance;
    _pullPointer = null;
    _canPullToRefresh = false;
    if (!mounted) return;
    if (shouldRefresh) {
      setState(() {
        _refreshing = true;
        _pullDistance = 64;
      });
      unawaited(_controller.reload());
    } else if (_pullDistance > 0) {
      setState(() => _pullDistance = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await _controller.canGoBack()) {
          await _controller.goBack();
          return;
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          top: true,
          bottom: false,
          child: Stack(
            children: [
              if (!_offline)
                Listener(
                  key: _webViewGestureKey,
                  onPointerDown: _startPull,
                  onPointerMove: _updatePull,
                  onPointerUp: _finishPull,
                  onPointerCancel: _finishPull,
                  child: WebViewWidget(controller: _controller),
                ),
              if (!_offline && (_pullDistance > 0 || _refreshing))
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutBack,
                  top: _refreshing ? 18 : 8,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Center(
                      child: Transform.translate(
                        offset: Offset(
                          0,
                          (_pullDistance - 44).clamp(0, 70).toDouble(),
                        ),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(22),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x26000000),
                                blurRadius: 12,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 18,
                                height: 18,
                                child: _refreshing
                                    ? const CircularProgressIndicator(
                                        strokeWidth: 2.4,
                                        color: kDayDispatchRed,
                                      )
                                    : Transform.rotate(
                                        angle:
                                            (_pullDistance /
                                                _refreshTriggerDistance) *
                                            3.14159,
                                        child: CircularProgressIndicator(
                                          value: (_pullDistance /
                                                  _refreshTriggerDistance)
                                              .clamp(0.0, 1.0),
                                          strokeWidth: 2.4,
                                          color: kDayDispatchRed,
                                          backgroundColor: kDayDispatchRed
                                              .withValues(alpha: 0.12),
                                        ),
                                      ),
                              ),
                              const SizedBox(width: 9),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 180),
                                child: Text(
                                  _refreshing
                                      ? 'Refreshing...'
                                      : _pullDistance >=
                                            _refreshTriggerDistance
                                      ? 'Release to refresh'
                                      : 'Pull to refresh',
                                  key: ValueKey(
                                    _refreshing
                                        ? 'refreshing'
                                        : _pullDistance >=
                                              _refreshTriggerDistance
                                        ? 'release'
                                        : 'pull',
                                  ),
                                  style: const TextStyle(
                                    color: kDayDispatchNavy,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (_offline)
                Container(
                  color: kDayDispatchSurface,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 36),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 92,
                            height: 92,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(28),
                              boxShadow: [
                                BoxShadow(
                                  color: kDayDispatchNavy.withValues(
                                    alpha: 0.08,
                                  ),
                                  blurRadius: 18,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.wifi_off_rounded,
                              size: 46,
                              color: kDayDispatchRed,
                            ),
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'Internet connection unavailable',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              color: kDayDispatchNavy,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Check your network and try again to continue using DayDispatch.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 15,
                              height: 1.5,
                              color: Color(0xFF4D597C),
                            ),
                          ),
                          const SizedBox(height: 28),
                          ElevatedButton.icon(
                            onPressed: _retryLoad,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Retry'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kDayDispatchRed,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (!_offline)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: AnimatedOpacity(
                    opacity: _loading ? 1 : 0,
                    duration: const Duration(milliseconds: 450),
                    curve: Curves.easeOutCubic,
                    child: IgnorePointer(
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: _progress / 100),
                        duration: const Duration(milliseconds: 500),
                        curve: Curves.easeOutCubic,
                        builder: (context, value, child) =>
                            LinearProgressIndicator(
                              value: value,
                              minHeight: 3,
                              backgroundColor: kDayDispatchRed.withValues(
                                alpha: 0.08,
                              ),
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                kDayDispatchRed,
                              ),
                            ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
