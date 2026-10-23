import 'package:daydispatch/main.dart';
import 'package:daydispatch/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

class _TestWebViewPlatform extends WebViewPlatform {
  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) {
    return _TestNavigationDelegate(params);
  }

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    return _TestWebViewController(params);
  }

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) {
    return _TestWebViewWidget(params);
  }

  @override
  PlatformWebViewCookieManager createPlatformCookieManager(
    PlatformWebViewCookieManagerCreationParams params,
  ) {
    return _TestCookieManager(params);
  }
}

class _TestNavigationDelegate extends PlatformNavigationDelegate {
  _TestNavigationDelegate(super.params) : super.implementation();

  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback onNavigationRequest,
  ) async {}

  @override
  Future<void> setOnPageStarted(PageEventCallback onPageStarted) async {}

  @override
  Future<void> setOnPageFinished(PageEventCallback onPageFinished) async {}

  @override
  Future<void> setOnHttpError(HttpResponseErrorCallback onHttpError) async {}

  @override
  Future<void> setOnProgress(ProgressCallback onProgress) async {}

  @override
  Future<void> setOnWebResourceError(
    WebResourceErrorCallback onWebResourceError,
  ) async {}

  @override
  Future<void> setOnUrlChange(UrlChangeCallback onUrlChange) async {}

  @override
  Future<void> setOnHttpAuthRequest(
    HttpAuthRequestCallback onHttpAuthRequest,
  ) async {}

  @override
  Future<void> setOnSSlAuthError(SslAuthErrorCallback onSslAuthError) async {}
}

class _TestWebViewController extends PlatformWebViewController {
  _TestWebViewController(super.params) : super.implementation();

  @override
  Future<void> loadRequest(LoadRequestParams params) async {}

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {}

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {}

  @override
  Future<void> setBackgroundColor(Color color) async {}

  @override
  Future<void> setUserAgent(String? userAgent) async {}

  @override
  Future<void> addJavaScriptChannel(
    JavaScriptChannelParams javaScriptChannelParams,
  ) async {}

  @override
  Future<void> runJavaScript(String javaScript) async {}

  @override
  Future<String?> currentUrl() async => null;

  @override
  Future<String?> getUserAgent() async => null;

  @override
  Future<void> setOnPlatformPermissionRequest(
    void Function(PlatformWebViewPermissionRequest request) onPermissionRequest,
  ) async {}

  @override
  Future<bool> canGoBack() async => false;

  @override
  Future<void> goBack() async {}

  @override
  Future<void> reload() async {}
}

class _TestWebViewWidget extends PlatformWebViewWidget {
  _TestWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

class _TestCookieManager extends PlatformWebViewCookieManager {
  _TestCookieManager(super.params) : super.implementation();

  @override
  Future<bool> clearCookies() async => false;

  @override
  Future<void> setCookie(WebViewCookie cookie) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  WebViewPlatform.instance = _TestWebViewPlatform();

  testWidgets('app starts on the DayDispatch splash shell', (tester) async {
    await tester.pumpWidget(const DayDispatchApp());

    expect(find.byType(DayDispatchSplashScreen), findsOneWidget);
    expect(find.byType(DayDispatchWebViewPage), findsOneWidget);
  });

  test('order notification data creates an order destination', () {
    final destination = NotificationDestination.fromData({
      'type': 'order_notification',
      'notification_id': '42',
      'order_id': 'DD-1001',
      'order_url': '/global-search?search_criteria=8&search_query=6496',
    });

    expect(destination?.type, 'order_notification');
    expect(
      destination?.destinationUrl,
      '/global-search?search_criteria=8&search_query=6496',
    );
  });

  test('chat notification data creates a chat destination', () {
    final destination = NotificationDestination.fromData({
      'type': 'chat_notification',
      'chat_url': '/chat/6496',
      'sender_id': '6496',
      'chat_id': '123',
      'notification_id': '456',
    });

    expect(destination?.type, 'chat_notification');
    expect(destination?.destinationUrl, '/chat/6496');
  });

  test('invalid notification data is ignored', () {
    expect(
      NotificationDestination.fromData({
        'type': 'unrelated_notification',
        'order_id': 'DD-1001',
      }),
      isNull,
    );
    expect(
      NotificationDestination.fromData({
        'type': 'order_notification',
        'order_id': '6496',
      }),
      isNull,
    );
    expect(
      NotificationDestination.fromData({
        'type': 'chat_notification',
        'chat_url': 'https://evil.example/chat/6496',
      }),
      isNull,
    );
  });

  test('notification exceptions redact bearer and FCM tokens', () {
    const sanctumToken = 'sanctum-secret-value';
    const fcmToken = 'fcm-secret-value';
    final description = sanitizedException(
      Exception('Bearer $sanctumToken token=$fcmToken'),
      secrets: const [sanctumToken, fcmToken],
    );

    expect(description, contains('Exception'));
    expect(description, isNot(contains(sanctumToken)));
    expect(description, isNot(contains(fcmToken)));
    expect(description, contains('[REDACTED]'));
  });
}
