import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di/app_providers.dart';
import '../../../../core/result/result.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../domain/entities/service_card_data.dart';
import '../../domain/entities/service_launch_data.dart';

/// 校园服务的免登录入口。
///
/// 用 `flutter_inappwebview` 替换原来的 `webview_flutter`：
/// - 同一份 API 同时跑 Android / iOS / macOS / Windows，
///   Windows 端走 WebView2（Edge Chromium）后端，能拿到 Cookie 注入接口；
/// - 桌面端的 [InAppWebView] 默认带滚动 / 缩放 / 触摸板姿势，免我们自己适配。
class ServiceWebViewPage extends ConsumerStatefulWidget {
  const ServiceWebViewPage({super.key, required this.item});

  final ServiceItem item;

  @override
  ConsumerState<ServiceWebViewPage> createState() => _ServiceWebViewPageState();
}

class _ServiceWebViewPageState extends ConsumerState<ServiceWebViewPage> {
  InAppWebViewController? _controller;
  bool _isLoading = true;
  String? _errorMessage;
  ServiceLaunchData? _pendingLaunch;

  @override
  void initState() {
    super.initState();
    _prepareLaunch();
  }

  Future<void> _prepareLaunch() async {
    final authState = await ref.read(authControllerProvider.future);
    final session = authState.session;
    if (session == null) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = '当前未登录，无法进入校园服务。';
      });
      return;
    }

    final launchResult = await ref
        .read(schoolPortalGatewayProvider)
        .prepareServiceLaunch(session, item: widget.item);
    if (!mounted) {
      return;
    }

    if (launchResult case FailureResult<ServiceLaunchData>(
      failure: final failure,
    )) {
      setState(() {
        _isLoading = false;
        _errorMessage = failure.message;
      });
      return;
    }

    _pendingLaunch = launchResult.requireValue();
    if (_controller != null) {
      await _injectCookiesAndLoad(_pendingLaunch!);
    }
  }

  Future<void> _injectCookiesAndLoad(ServiceLaunchData launch) async {
    final cookieManager = CookieManager.instance();
    final targetUri = WebUri(launch.resolvedUrl);

    // 同一域名重新登录前先清掉 stale cookie，避免 expired ticket 拼接。
    try {
      await cookieManager.deleteAllCookies();
    } catch (error) {
      // Windows / macOS 偶现 not-supported，忽略即可，新写入会覆盖老值。
      debugPrint('clearCookies failed: $error');
    }
    await InAppWebViewController.clearAllCache();

    for (final cookie in launch.cookies) {
      var domain = cookie.domain;
      if (domain.startsWith('.')) {
        domain = domain.substring(1);
      }

      try {
        await cookieManager.setCookie(
          url: targetUri,
          name: cookie.name,
          value: cookie.value,
          domain: domain,
          path: cookie.path,
          isSecure: cookie.secure,
          isHttpOnly: cookie.httpOnly,
        );
      } catch (error) {
        debugPrint('setCookie ${cookie.name} failed: $error');
      }
    }

    if (!mounted) return;
    await _controller?.loadUrl(urlRequest: URLRequest(url: targetUri));
  }

  @override
  void dispose() {
    final controller = _controller;
    if (controller != null) {
      unawaited(InAppWebViewController.clearAllCache());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(widget.item.appName)),
      body: Stack(
        children: [
          if (_errorMessage != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 48,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge,
                    ),
                  ],
                ),
              ),
            )
          else
            InAppWebView(
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                useShouldOverrideUrlLoading: false,
                isInspectable: kDebugMode,
                cacheEnabled: true,
                supportZoom: false,
                transparentBackground: true,
              ),
              onWebViewCreated: (controller) async {
                _controller = controller;
                final pending = _pendingLaunch;
                if (pending != null) {
                  await _injectCookiesAndLoad(pending);
                }
              },
              onLoadStop: (_, __) {
                if (mounted) {
                  setState(() => _isLoading = false);
                }
              },
              onReceivedError: (_, __, error) {
                if (!mounted) return;
                setState(() {
                  _isLoading = false;
                  _errorMessage = '加载失败：${error.description}';
                });
              },
              onReceivedHttpError: (_, __, response) {
                if (response.statusCode == null) return;
                final code = response.statusCode!;
                if (code < 400) return;
                if (mounted) {
                  setState(() => _isLoading = false);
                }
              },
            ),
          if (_isLoading && _errorMessage == null)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
