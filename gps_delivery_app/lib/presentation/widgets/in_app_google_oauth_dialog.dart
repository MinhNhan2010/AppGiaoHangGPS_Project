import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_windows/webview_windows.dart';
import '../../core/auth/real_auth_delivery_service.dart';
import '../../core/theme/app_colors.dart';

class InAppGoogleOAuthDialog extends StatefulWidget {
  final String initialAuthUrl;
  final VoidCallback onCancel;

  const InAppGoogleOAuthDialog({
    super.key,
    required this.initialAuthUrl,
    required this.onCancel,
  });

  @override
  State<InAppGoogleOAuthDialog> createState() => _InAppGoogleOAuthDialogState();
}

class _InAppGoogleOAuthDialogState extends State<InAppGoogleOAuthDialog> {
  WebviewController? _winController;
  WebViewController? _mobileController;
  StreamSubscription<String>? _winUrlSub;
  StreamSubscription<LoadingState>? _winLoadingSub;

  bool _isInitialized = false;
  bool _isLoadingPage = true;
  bool _isCompletingCallback = false;
  String _currentUrl = 'https://accounts.google.com';
  String? _initError;

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.initialAuthUrl;
    _initEmbeddedWebView();
  }

  Future<void> _initEmbeddedWebView() async {
    try {
      if (Platform.isWindows) {
        final ctrl = WebviewController();
        _winController = ctrl;
        await ctrl.initialize();
        await ctrl.setBackgroundColor(Colors.white);
        await ctrl.setPopupWindowPolicy(WebviewPopupWindowPolicy.sameWindow);
        await ctrl.setUserAgent(
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
        );

        _winUrlSub = ctrl.url.listen((url) {
          if (!mounted) return;
          final isCallback =
              url.contains('/oauth2callback') && url.contains('code=');
          setState(() {
            _currentUrl = url;
            if (isCallback) {
              _isCompletingCallback = true;
            }
          });
          if (isCallback) {
            RealAuthDeliveryService.instance.tryProcessOAuthCallbackUrl(url);
          }
        });

        _winLoadingSub = ctrl.loadingState.listen((state) {
          if (!mounted) return;
          setState(() {
            _isLoadingPage = state == LoadingState.loading;
          });
        });

        await ctrl.loadUrl(widget.initialAuthUrl);
        if (!mounted) return;
        setState(() {
          _isInitialized = true;
        });
      } else {
        final ctrl = WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setBackgroundColor(Colors.white)
          ..setUserAgent(
            'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36',
          )
          ..setNavigationDelegate(
            NavigationDelegate(
              onPageStarted: (url) {
                if (!mounted) return;
                final isCallback =
                    url.contains('/oauth2callback') && url.contains('code=');
                setState(() {
                  _currentUrl = url;
                  _isLoadingPage = true;
                  if (isCallback) {
                    _isCompletingCallback = true;
                  }
                });
                if (isCallback) {
                  RealAuthDeliveryService.instance
                      .tryProcessOAuthCallbackUrl(url);
                }
              },
              onPageFinished: (_) {
                if (!mounted) return;
                setState(() {
                  _isLoadingPage = false;
                });
              },
            ),
          )
          ..loadRequest(Uri.parse(widget.initialAuthUrl));

        _mobileController = ctrl;
        if (!mounted) return;
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initError =
            'Không thể khởi tạo trình duyệt nhúng trong ứng dụng: $e';
      });
    }
  }

  @override
  void dispose() {
    _winUrlSub?.cancel();
    _winLoadingSub?.cancel();
    _winController?.dispose();
    super.dispose();
  }

  Future<void> _reloadPage() async {
    setState(() {
      _isLoadingPage = true;
      _initError = null;
    });
    if (Platform.isWindows && _winController != null) {
      await _winController!.reload();
    } else if (_mobileController != null) {
      await _mobileController!.reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayHost = Uri.tryParse(_currentUrl)?.host ?? 'accounts.google.com';

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 520,
          maxHeight: 680,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: AppColors.ink, width: 2.0),
            boxShadow: const [
              BoxShadow(
                color: AppColors.ink,
                offset: Offset(6, 6),
                blurRadius: 0,
              ),
              BoxShadow(
                color: AppColors.violet,
                offset: Offset(12, 12),
                blurRadius: 0,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Thanh tiêu đề nhúng Google OAuth 2.0
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: const BoxDecoration(
                  color: AppColors.paper,
                  border: Border(
                    bottom: BorderSide(color: AppColors.ink, width: 1.5),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: AppColors.ink, width: 1.4),
                      ),
                      child: const Text(
                        'G',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 17,
                          color: Color(0xFFEA4335),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Đăng nhập bằng Google',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              color: AppColors.ink,
                            ),
                          ),
                          Row(
                            children: [
                              const Icon(
                                Icons.lock_rounded,
                                size: 11,
                                color: Color(0xFF16A34A),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  'https://$displayHost',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontFamily: 'Consolas',
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Tải lại trang',
                      onPressed: _reloadPage,
                      icon: const Icon(
                        Icons.refresh_rounded,
                        size: 19,
                        color: AppColors.ink,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Đóng',
                      onPressed: () {
                        RealAuthDeliveryService.instance.stopGoogleOAuthServer();
                        widget.onCancel();
                      },
                      icon: const Icon(
                        Icons.close_rounded,
                        size: 20,
                        color: AppColors.ink,
                      ),
                    ),
                  ],
                ),
              ),
              if (_isLoadingPage)
                const LinearProgressIndicator(
                  minHeight: 3,
                  backgroundColor: AppColors.paper,
                  color: AppColors.violet,
                ),
              Expanded(
                child: _buildWebViewBody(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWebViewBody() {
    if (_initError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: AppColors.pink,
                size: 42,
              ),
              const SizedBox(height: 12),
              Text(
                _initError!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (!_isInitialized) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.violet),
            SizedBox(height: 14),
            Text(
              'Đang kết nối tới accounts.google.com...',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        Positioned.fill(
          child: Platform.isWindows
              ? Webview(_winController!)
              : WebViewWidget(controller: _mobileController!),
        ),
        if (_isCompletingCallback)
          Positioned.fill(
            child: Container(
              color: Colors.white.withValues(alpha: 0.92),
              alignment: Alignment.center,
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: AppColors.violet),
                  SizedBox(height: 14),
                  Text(
                    'Đang xác thực tài khoản Google với hệ thống...',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w900,
                      color: AppColors.ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
