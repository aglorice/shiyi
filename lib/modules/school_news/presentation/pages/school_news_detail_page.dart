import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/error/error_display.dart';
import '../../../../shared/utils/long_image_share.dart';
import '../../../../shared/widgets/async_value_view.dart';
import '../../../../shared/widgets/app_snackbar.dart';
import '../../domain/entities/school_news.dart';
import '../controllers/school_news_detail_controller.dart';

class SchoolNewsDetailPage extends ConsumerStatefulWidget {
  const SchoolNewsDetailPage({super.key, required this.item});

  final SchoolNewsItem item;

  @override
  ConsumerState<SchoolNewsDetailPage> createState() =>
      _SchoolNewsDetailPageState();
}

class _SchoolNewsDetailPageState extends ConsumerState<SchoolNewsDetailPage> {
  bool _sharing = false;

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(schoolNewsDetailProvider(widget.item));
    final detailForShare = switch (detailAsync) {
      AsyncData(:final value) => value,
      _ => null,
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('学校要闻'),
        actions: [
          if (detailForShare != null)
            IconButton(
              tooltip: '长图分享',
              onPressed: _sharing
                  ? null
                  : () => _shareDetail(context, detailForShare),
              icon: _sharing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.ios_share_rounded),
            ),
        ],
      ),
      body: AsyncValueView(
        value: detailAsync,
        onRetry: () => ref.invalidate(schoolNewsDetailProvider(widget.item)),
        loadingLabel: '正文加载中',
        dataBuilder: (detail) {
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(schoolNewsDetailProvider(widget.item));
              await ref.read(schoolNewsDetailProvider(widget.item).future);
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

  Future<void> _shareDetail(
    BuildContext buttonContext,
    SchoolNewsDetail detail,
  ) async {
    setState(() => _sharing = true);
    final sharePositionOrigin = LongImageShare.shareOriginFor(buttonContext);
    AppSnackBar.show(
      context,
      message: '正在生成分享长图...',
      tone: AppSnackBarTone.info,
      icon: Icons.auto_awesome_rounded,
      duration: const Duration(seconds: 3),
    );

    try {
      final images = await _loadShareImages(detail);
      if (!mounted) return;
      for (final bytes in images.values) {
        await precacheImage(MemoryImage(bytes), context);
      }
      if (!mounted) return;

      final bytes = await LongImageShare.capturePng(
        context: context,
        child: _SchoolNewsSharePoster(detail: detail, images: images),
      );
      if (!mounted) return;

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      await LongImageShare.sharePng(
        bytes: bytes,
        fileName: _shareFileName('学校要闻', detail.title),
        title: detail.title,
        text: '${detail.title}\n${detail.item.detailUrl}',
        sharePositionOrigin: sharePositionOrigin,
      );
    } catch (error) {
      if (!mounted) return;
      AppSnackBar.show(
        context,
        message: '长图分享失败：${formatError(error).message}',
        tone: AppSnackBarTone.error,
        icon: Icons.error_outline_rounded,
      );
    } finally {
      if (mounted) {
        setState(() => _sharing = false);
      }
    }
  }

  Future<Map<String, Uint8List>> _loadShareImages(
    SchoolNewsDetail detail,
  ) async {
    final images = <String, Uint8List>{};
    for (final block in detail.contentBlocks) {
      if (block is! SchoolNewsImageBlock || block.url.trim().isEmpty) {
        continue;
      }
      try {
        images[block.url] = await ref.read(
          schoolNewsImageBytesProvider((
            url: block.url,
            referer: detail.item.detailUrl,
          )).future,
        );
      } catch (_) {
        continue;
      }
    }
    return images;
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

class _SchoolNewsSharePoster extends StatelessWidget {
  const _SchoolNewsSharePoster({required this.detail, required this.images});

  final SchoolNewsDetail detail;
  final Map<String, Uint8List> images;

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat(
      'yyyy-MM-dd',
      'zh_CN',
    ).format(detail.item.publishedAt);
    final metaLines = detail.metaLines.isEmpty
        ? ['发布时间：$dateLabel']
        : detail.metaLines;

    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
      child: DefaultTextStyle(
        style: const TextStyle(
          color: Color(0xFF213A3C),
          fontSize: 15,
          height: 1.72,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F6A71).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.newspaper_rounded,
                    color: Color(0xFF0F6A71),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    '学校要闻',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F6A71),
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Text(
              detail.title,
              style: const TextStyle(
                color: Color(0xFF142C2F),
                fontSize: 25,
                height: 1.26,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [for (final line in metaLines) _ShareMetaChip(line)],
            ),
            const SizedBox(height: 18),
            Container(
              height: 1,
              color: const Color(0xFF0F6A71).withValues(alpha: 0.16),
            ),
            const SizedBox(height: 18),
            for (final block in detail.contentBlocks)
              switch (block) {
                SchoolNewsTextBlock(:final text) => Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Text(text),
                ),
                SchoolNewsImageBlock(:final url, :final alt) => Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _ShareImageBlock(
                    bytes: images[url],
                    alt: alt,
                    failureLabel: '图片未能加载',
                  ),
                ),
              },
            const SizedBox(height: 8),
            _SharePosterFooter(sourceUrl: detail.item.detailUrl),
          ],
        ),
      ),
    );
  }
}

class _ShareMetaChip extends StatelessWidget {
  const _ShareMetaChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0F6A71).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF0F6A71),
          fontSize: 11,
          fontWeight: FontWeight.w800,
          height: 1.1,
        ),
      ),
    );
  }
}

class _ShareImageBlock extends StatelessWidget {
  const _ShareImageBlock({
    required this.bytes,
    required this.failureLabel,
    this.alt,
  });

  final Uint8List? bytes;
  final String failureLabel;
  final String? alt;

  @override
  Widget build(BuildContext context) {
    final data = bytes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: data == null
              ? Container(
                  height: 92,
                  alignment: Alignment.center,
                  color: const Color(0xFFEFF4F2),
                  child: Text(
                    failureLabel,
                    style: const TextStyle(
                      color: Color(0xFF607172),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              : Image.memory(data, fit: BoxFit.fitWidth),
        ),
        if (alt != null && alt!.trim().isNotEmpty) ...[
          const SizedBox(height: 7),
          Text(
            alt!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF607172),
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ],
      ],
    );
  }
}

class _SharePosterFooter extends StatelessWidget {
  const _SharePosterFooter({required this.sourceUrl});

  final String sourceUrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F6A71).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.auto_awesome_rounded,
            color: Color(0xFF0F6A71),
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Uni Yi · 五邑大学校园助手',
                  style: TextStyle(
                    color: Color(0xFF0F6A71),
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  sourceUrl,
                  style: const TextStyle(
                    color: Color(0xFF607172),
                    fontSize: 10,
                    height: 1.32,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _shareFileName(String prefix, String title) {
  final safeTitle = title
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final clipped = safeTitle.length > 28
      ? safeTitle.substring(0, 28)
      : safeTitle;
  return '${prefix}_${clipped.isEmpty ? '详情' : clipped}.png';
}
