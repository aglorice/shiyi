import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../widgets/app_snackbar.dart';

class LinkWebViewPage extends StatefulWidget {
  const LinkWebViewPage({super.key, required this.title, required this.uri});

  final String title;
  final Uri uri;

  @override
  State<LinkWebViewPage> createState() => _LinkWebViewPageState();
}

class _LinkWebViewPageState extends State<LinkWebViewPage> {
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
            if (!mounted) {
              return;
            }
            setState(() => _isLoading = false);
          },
          onWebResourceError: (error) {
            if (!mounted) {
              return;
            }
            setState(() {
              _isLoading = false;
              _errorMessage = '加载失败：${error.description}';
            });
          },
        ),
      );

    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    await _controller.loadRequest(widget.uri);
  }

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

  @override
  Widget build(BuildContext context) {
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
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.tonal(
                      onPressed: _load,
                      child: const Text('重新加载'),
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
