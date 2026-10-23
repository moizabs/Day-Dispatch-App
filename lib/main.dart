import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'account_browser.dart';
import 'firebase_options.dart';

const _homeUrl = 'https://www.daydispatch.com/Authentication/Login-Form';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const DayDispatchApp());
}

class DayDispatchApp extends StatelessWidget {
  const DayDispatchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Day Dispatch',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff1976d2)),
        useMaterial3: true,
      ),
      home: const DayDispatchWebView(),
    );
  }
}

class DayDispatchWebView extends StatefulWidget {
  const DayDispatchWebView({super.key});

  @override
  State<DayDispatchWebView> createState() => _DayDispatchWebViewState();
}

class _DayDispatchWebViewState extends State<DayDispatchWebView>
    with TickerProviderStateMixin {
  late final WebViewController _controller;
  late final AnimationController _introController;
  late final AnimationController _exitController;
  int _loadingProgress = 0;
  WebResourceError? _error;
  bool _showIntro = true;

  @override
  void initState() {
    super.initState();
    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..forward();
    _exitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent('DayDispatchApp/1.0')
      ..addJavaScriptChannel(
        'DayDispatchBrowser',
        onMessageReceived: (message) async {
          final current = Uri.tryParse(await _controller.currentUrl() ?? '');
          if (current == null || !isDayDispatchUrl(current)) return;
          try {
            final data = jsonDecode(message.message) as Map<String, dynamic>;
            final id = data['id'];
            final uri = Uri.tryParse(data['url'] as String);
            if (id is! int || uri == null) return;
            final opened = await _openExternal(uri);
            await _controller.runJavaScript(
              'window.dispatchEvent(new CustomEvent("daydispatch:browser-result", '
              '{detail: {id: $id, opened: $opened}}));',
            );
          } catch (_) {
            // Ignore malformed bridge messages from page scripts.
          }
        },
      )
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) async {
            final uri = Uri.tryParse(request.url);
            if (request.isMainFrame &&
                uri != null &&
                isExternalAccountPage(uri)) {
              await _openExternal(uri);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onPageStarted: (_) {
            if (!mounted) return;
            setState(() {
              _loadingProgress = 0;
              _error = null;
            });
          },
          onProgress: (progress) {
            if (!mounted) return;
            setState(() => _loadingProgress = progress);
          },
          onPageFinished: (url) async {
            if (!mounted) return;
            setState(() => _loadingProgress = 100);
            final uri = Uri.tryParse(url);
            if (uri != null && isDayDispatchUrl(uri)) {
              await _controller.runJavaScript(_browserBridge);
            }
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame != true || !mounted) return;
            setState(() => _error = error);
          },
        ),
      )
      ..loadRequest(Uri.parse(_homeUrl));

    _finishIntro();
  }

  Future<void> _finishIntro() async {
    await Future<void>.delayed(const Duration(milliseconds: 2200));
    if (!mounted) return;
    await _exitController.forward();
    if (mounted) setState(() => _showIntro = false);
  }

  Future<bool> _openExternal(Uri uri) async {
    if (!isExternalAccountPage(uri)) return false;
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        return true;
      }
    } catch (_) {
      // Keep the current WebView page and offer a retry on launch failure.
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Could not open your browser. Please try again.'),
          action: SnackBarAction(
            label: 'Retry',
            onPressed: () => _openExternal(uri),
          ),
        ),
      );
    }
    return false;
  }

  static const _browserBridge = r'''
    (() => {
      if (window.dayDispatchNative?.openExternal) return;
      let nextId = 0;
      window.dayDispatchNative = window.dayDispatchNative || {};
      window.dayDispatchNative.openExternal = (url) => new Promise((resolve) => {
        const id = ++nextId;
        const finish = (opened) => {
          clearTimeout(timer);
          window.removeEventListener('daydispatch:browser-result', handler);
          resolve(opened);
        };
        const handler = (event) => {
          if (event.detail?.id === id) finish(event.detail.opened === true);
        };
        const timer = setTimeout(() => finish(false), 10000);
        window.addEventListener('daydispatch:browser-result', handler);
        DayDispatchBrowser.postMessage(JSON.stringify({id, url}));
      });
      window.dispatchEvent(new Event('daydispatch:native-ready'));
    })();
  ''';

  @override
  void dispose() {
    _introController.dispose();
    _exitController.dispose();
    super.dispose();
  }

  Future<void> _handleBack() async {
    if (await _controller.canGoBack()) {
      await _controller.goBack();
    } else if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Stack(
            children: [
              WebViewWidget(controller: _controller),
              if (_loadingProgress < 100 && _error == null)
                LinearProgressIndicator(value: _loadingProgress / 100),
              if (_error != null)
                ColoredBox(
                  color: Theme.of(context).colorScheme.surface,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.wifi_off_rounded, size: 48),
                          const SizedBox(height: 16),
                          Text(
                            'Unable to load Day Dispatch',
                            style: Theme.of(context).textTheme.titleLarge,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _error!.description,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 20),
                          FilledButton.icon(
                            onPressed: () => _controller.reload(),
                            icon: const Icon(Icons.refresh),
                            label: const Text('Try again'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (_showIntro)
                Positioned.fill(
                  child: FadeTransition(
                    opacity: ReverseAnimation(_exitController),
                    child: _LaunchIntro(animation: _introController),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LaunchIntro extends StatelessWidget {
  const _LaunchIntro({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final reveal = CurvedAnimation(
      parent: animation,
      curve: const Interval(0, 0.7, curve: Curves.easeOutBack),
    );
    final lineProgress = CurvedAnimation(
      parent: animation,
      curve: const Interval(0.25, 1, curve: Curves.easeInOutCubic),
    );

    return ColoredBox(
      color: const Color(0xfff8fafc),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.12),
                radius: 0.85,
                colors: [Colors.white, Color(0xffeef3f8)],
              ),
            ),
          ),
          Center(
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.78, end: 1).animate(reveal),
              child: FadeTransition(
                opacity: reveal,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/branding/daydispatch_logo.webp',
                      width: 210,
                      filterQuality: FilterQuality.high,
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: 180,
                      height: 3,
                      child: SizeTransition(
                        axis: Axis.horizontal,
                        alignment: Alignment.centerLeft,
                        sizeFactor: lineProgress,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Color(0xff164b78), Color(0xffed3237)],
                              ),
                            ),
                            child: SizedBox.expand(),
                          ),
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
