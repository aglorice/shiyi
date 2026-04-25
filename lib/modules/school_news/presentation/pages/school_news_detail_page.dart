import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../shared/widgets/async_value_view.dart';
import '../../domain/entities/school_news.dart';
import '../controllers/school_news_detail_controller.dart';

class SchoolNewsDetailPage extends ConsumerWidget {
  const SchoolNewsDetailPage({super.key, required this.item});

  final SchoolNewsItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(schoolNewsDetailProvider(item));

    return Scaffold(
      appBar: AppBar(title: const Text('学校要闻')),
      body: AsyncValueView(
        value: detailAsync,
        onRetry: () => ref.invalidate(schoolNewsDetailProvider(item)),
        loadingLabel: '正文加载中',
        dataBuilder: (detail) {
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(schoolNewsDetailProvider(item));
              await ref.read(schoolNewsDetailProvider(item).future);
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 34),
              children: [
                _DetailHeader(detail: detail),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Divider(
                    height: 1,
                    color: Theme.of(
                      context,
                    ).colorScheme.outlineVariant.withValues(alpha: 0.66),
                  ),
                ),
                for (final block in detail.contentBlocks)
                  switch (block) {
                    SchoolNewsTextBlock(:final text) => Padding(
                      padding: const EdgeInsets.only(bottom: 15),
                      child: SelectableText(
                        text,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontSize: 16,
                          height: 1.82,
                        ),
                      ),
                    ),
                    SchoolNewsImageBlock(:final url, :final alt) => Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _SchoolNewsImage(
                        url: url,
                        referer: detail.item.detailUrl,
                        alt: alt,
                      ),
                    ),
                  },
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DetailHeader extends StatelessWidget {
  const _DetailHeader({required this.detail});

  final SchoolNewsDetail detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateLabel = DateFormat(
      'yyyy-MM-dd',
      'zh_CN',
    ).format(detail.item.publishedAt);
    final metaLines = detail.metaLines.isEmpty
        ? ['发布时间：$dateLabel']
        : detail.metaLines;

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            detail.title,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w900,
              height: 1.28,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final line in metaLines) _MetaChip(label: line)],
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SchoolNewsImage extends ConsumerWidget {
  const _SchoolNewsImage({required this.url, required this.referer, this.alt});

  final String url;
  final String referer;
  final String? alt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final imageAsync = ref.watch(
      schoolNewsImageBytesProvider((url: url, referer: referer)),
    );
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: imageAsync.when(
            data: (bytes) => Material(
              color: colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.42,
              ),
              child: InkWell(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => _SchoolNewsImagePreviewPage(bytes: bytes),
                    ),
                  );
                },
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    Image.memory(bytes, fit: BoxFit.fitWidth),
                    Container(
                      margin: const EdgeInsets.all(10),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.58),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        '点击预览',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            loading: () => Container(
              height: 160,
              alignment: Alignment.center,
              color: colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.42,
              ),
              child: const CircularProgressIndicator(strokeWidth: 2),
            ),
            error: (_, __) => Container(
              height: 88,
              alignment: Alignment.center,
              color: colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.42,
              ),
              child: Text(
                '图片加载失败',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.error,
                ),
              ),
            ),
          ),
        ),
        if (alt != null && alt!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            alt!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _SchoolNewsImagePreviewPage extends StatelessWidget {
  const _SchoolNewsImagePreviewPage({required this.bytes});

  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('图片预览'),
      ),
      body: SafeArea(
        child: Center(
          child: InteractiveViewer(
            minScale: 1,
            maxScale: 4,
            child: Image.memory(bytes, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }
}
