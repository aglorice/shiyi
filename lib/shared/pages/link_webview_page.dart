import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../widgets/app_snackbar.dart';

/// 通用站外/站内页面浏览器壳。
///
/// 同一份代码同时跑移动端和桌面端：
/// - 移动端用平台原生 WebView；
/// - Windows 端走 WebView2，能在桌面里直接看通知详情、文件附件等。
class LinkWebViewPage extends StatefulWidget {
  const LinkWebViewPage({super.key, required this.title, required this.uri});

  final String title;
  final Uri uri;

  @override
  State<LinkWebViewPage> createState() => _LinkWebViewPageState();
}

class _LinkWebViewPageState extends State<LinkWebViewPage> {
  bool _isLoading = true;
  String? _errorMessage;
  int _reloadKey = 0;

  Future<void> _copyLink() async {
    await Clipboard.setData(ClipboardData(text: widget.uri.toString()));
    if (!mounted) {
      return;
    }
    AppSnackBar.show(
      context,
      message: '链接已复制',
      tone: AppSnackBarTone.success,
      icon: Icons.copy_rounded,
    );
  }

  void _reload() {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _reloadKey++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: '复制链接',
            onPressed: _copyLink,
            icon: const Icon(Icons.copy_rounded),
          ),
        ],
      ),
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
                      Icons.language_rounded,
                      size: 44,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.tonal(
                      onPressed: _reload,
                      child: const Text('重新加载'),
                    ),
                  ],
                ),
              ),
            )
          else
            InAppWebView(
              key: ValueKey(_reloadKey),
              initialUrlRequest: URLRequest(url: WebUri.uri(widget.uri)),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                isInspectable: kDebugMode,
                cacheEnabled: true,
                supportZoom: true,
                transparentBackground: true,
              ),
              onWebViewCreated: (controller) {
                // 仅触发首次加载，无需保存。
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
            ),
          if (_isLoading && _errorMessage == null)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
