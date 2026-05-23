import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../../app/di/app_providers.dart';
import '../../../../core/result/result.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../domain/entities/service_card_data.dart';
import '../../domain/entities/service_launch_data.dart';

class ServiceWebViewPage extends ConsumerStatefulWidget {
  const ServiceWebViewPage({super.key, required this.item});

  final ServiceItem item;

  @override
  ConsumerState<ServiceWebViewPage> createState() => _ServiceWebViewPageState();
}

class _ServiceWebViewPageState extends ConsumerState<ServiceWebViewPage> {
  late final WebViewController _controller;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) {
              setState(() => _isLoading = false);
            }
          },
          onWebResourceError: (error) {
            if (mounted) {
              setState(() {
                _isLoading = false;
                _errorMessage = '加载失败：${error.description}';
              });
            }
          },
        ),
      );

    _prepareAndLoad();
  }

  Future<void> _prepareAndLoad() async {
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

    await _loadWithCookies(launchResult.requireValue());
  }

  Future<void> _resetWebViewState() async {
    final cookieManager = WebViewCookieManager();
    await cookieManager.clearCookies();
    await _controller.clearCache();
    await _controller.clearLocalStorage();
  }

  Future<void> _loadWithCookies(ServiceLaunchData launch) async {
    await _resetWebViewState();
    if (!mounted) {
      return;
    }

    final cookieManager = WebViewCookieManager();

    for (final cookie in launch.cookies) {
      var domain = cookie.domain;
      if (domain.startsWith('.')) {
        domain = domain.substring(1);
      }

      await cookieManager.setCookie(
        WebViewCookie(
          name: cookie.name,
          value: cookie.value,
          domain: domain,
          path: cookie.path,
        ),
      );

      if (!mounted) {
        return;
      }
    }

    await _controller.loadRequest(Uri.parse(launch.resolvedUrl));
  }

  @override
  void dispose() {
    unawaited(_resetWebViewState());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ],
                ),
              ),
            )
          else
            WebViewWidget(controller: _controller),
          if (_isLoading && _errorMessage == null)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
