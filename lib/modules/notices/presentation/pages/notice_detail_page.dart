import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../app/di/app_providers.dart';
import '../../../../core/error/error_display.dart';
import '../../../../core/platform/file_save_service.dart';
import '../../../../core/result/result.dart';
import '../../../../shared/utils/long_image_share.dart';
import '../../../../shared/widgets/async_value_view.dart';
import '../../../../shared/widgets/app_snackbar.dart';
import '../../../../shared/widgets/constrained_body.dart';
import '../../domain/entities/campus_notice.dart';
import '../controllers/notice_detail_controller.dart';

class NoticeDetailPage extends ConsumerStatefulWidget {
  const NoticeDetailPage({super.key, required this.item});

  final CampusNoticeItem item;

  @override
  ConsumerState<NoticeDetailPage> createState() => _NoticeDetailPageState();
}

class _NoticeDetailPageState extends ConsumerState<NoticeDetailPage> {
  bool _sharing = false;

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(noticeDetailProvider(widget.item));
    final detailForShare = switch (detailAsync) {
      AsyncData(:final value) => value,
      _ => null,
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.item.categoryLabel ?? widget.item.category.defaultLabel,
        ),
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
      body: ConstrainedBody(
        child: AsyncValueView(
          value: detailAsync,
          onRetry: () => ref.invalidate(noticeDetailProvider(widget.item)),
          loadingLabel: '加载中',
          dataBuilder: (detail) => RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(noticeDetailProvider(widget.item));
              await ref.read(noticeDetailProvider(widget.item).future);
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                Text(
                  detail.title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    height: 1.35,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: 12),
                _MetaRow(detail: detail),
                const SizedBox(height: 20),
                for (final block in detail.contentBlocks)
                  switch (block) {
                    NoticeTextBlock(:final text) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: SelectableText(
                        text,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontSize: 16,
                          height: 1.8,
                        ),
                      ),
                    ),
                    NoticeImageBlock(:final url) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _NoticeImage(
                        source: detail.item.category.board,
                        url: url,
                        referer: detail.item.detailUrl,
                      ),
                    ),
                  },
                if (detail.attachments.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    '附件',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (final attachment in detail.attachments) ...[
                    _AttachmentTile(item: detail.item, attachment: attachment),
                    const SizedBox(height: 10),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _shareDetail(
    BuildContext buttonContext,
    CampusNoticeDetail detail,
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
        child: _NoticeSharePoster(detail: detail, images: images),
      );
      if (!mounted) return;

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      await LongImageShare.sharePng(
        bytes: bytes,
        fileName: _shareFileName('通知', detail.title),
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
    CampusNoticeDetail detail,
  ) async {
    final images = <String, Uint8List>{};
    for (final block in detail.contentBlocks) {
      if (block is! NoticeImageBlock || block.url.trim().isEmpty) {
        continue;
      }
      try {
        images[block.url] = await ref.read(
          noticeImageBytesProvider((
            source: detail.item.category.board,
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

class _AttachmentTile extends ConsumerWidget {
  const _AttachmentTile({required this.item, required this.attachment});

  final CampusNoticeItem item;
  final CampusNoticeAttachment attachment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloading = ref.watch(
      noticeAttachmentDownloadingProvider(attachment.url),
    );
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: downloading ? null : () => _downloadAttachment(context, ref),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.attach_file_rounded,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      attachment.title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      downloading ? '保存中...' : '点击下载到系统下载目录',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              downloading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.download_rounded,
                          size: 20,
                          color: theme.colorScheme.primary,
                        ),
                        PopupMenuButton<_AttachmentAction>(
                          tooltip: '更多保存方式',
                          onSelected: (action) {
                            switch (action) {
                              case _AttachmentAction.saveAs:
                                _downloadAttachment(
                                  context,
                                  ref,
                                  pickLocation: true,
                                );
                            }
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem<_AttachmentAction>(
                              value: _AttachmentAction.saveAs,
                              child: Text('另存为...'),
                            ),
                          ],
                        ),
                      ],
                    ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _downloadAttachment(
    BuildContext context,
    WidgetRef ref, {
    bool pickLocation = false,
  }) async {
    ref
            .read(noticeAttachmentDownloadingProvider(attachment.url).notifier)
            .state =
        true;

    final result = await ref
        .read(noticeAttachmentDownloaderProvider)
        .download(
          source: item.category.board,
          attachment: attachment,
          referer: item.detailUri,
          pickLocation: pickLocation,
        );

    if (!context.mounted) {
      return;
    }

    ref
            .read(noticeAttachmentDownloadingProvider(attachment.url).notifier)
            .state =
        false;

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    switch (result) {
      case Success<SavedFile>(data: final file):
        AppSnackBar.show(
          context,
          message: '${file.fileName} 已保存到 ${file.path}',
          tone: AppSnackBarTone.success,
          icon: Icons.download_done_rounded,
          clearCurrent: false,
        );
      case FailureResult<SavedFile>(failure: final failure):
        AppSnackBar.show(
          context,
          message: formatError(failure).message,
          tone: AppSnackBarTone.error,
          clearCurrent: false,
        );
    }
  }
}

enum _AttachmentAction { saveAs }

class _NoticeImage extends ConsumerWidget {
  const _NoticeImage({
    required this.source,
    required this.url,
    required this.referer,
  });

  final NoticeBoardSource source;
  final String url;
  final String referer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final imageAsync = ref.watch(
      noticeImageBytesProvider((source: source, url: url, referer: referer)),
    );
    final theme = Theme.of(context);

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: imageAsync.when(
        data: (bytes) => Material(
          color: theme.colorScheme.surfaceContainerLowest,
          child: InkWell(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      _NoticeImagePreviewPage(url: url, bytes: bytes),
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
          child: const CircularProgressIndicator(strokeWidth: 2),
        ),
        error: (_, __) => Container(
          height: 44,
          alignment: Alignment.center,
          child: Text(
            '图片加载失败',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ),
      ),
    );
  }
}

class _NoticeImagePreviewPage extends ConsumerWidget {
  const _NoticeImagePreviewPage({required this.url, required this.bytes});

  final String url;
  final Uint8List bytes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saving = ref.watch(noticeImageSavingProvider(url));

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('图片预览'),
        actions: [
          IconButton(
            tooltip: '保存图片',
            onPressed: saving
                ? null
                : () => _saveImage(context: context, ref: ref),
            icon: saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.download_rounded),
          ),
          PopupMenuButton<_ImageSaveAction>(
            tooltip: '更多保存方式',
            enabled: !saving,
            onSelected: (action) {
              switch (action) {
                case _ImageSaveAction.saveAs:
                  _saveImage(context: context, ref: ref, pickLocation: true);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem<_ImageSaveAction>(
                value: _ImageSaveAction.saveAs,
                child: Text('另存为...'),
              ),
            ],
          ),
        ],
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

  Future<void> _saveImage({
    required BuildContext context,
    required WidgetRef ref,
    bool pickLocation = false,
  }) async {
    ref.read(noticeImageSavingProvider(url).notifier).state = true;

    final result = await ref
        .read(fileSaveServiceProvider)
        .saveBytesSafely(
          fileName: _buildImageFileName(url, bytes),
          bytes: bytes,
          subdirectory: '',
          failureLabel: '图片',
          pickLocation: pickLocation,
        );

    if (!context.mounted) {
      return;
    }

    ref.read(noticeImageSavingProvider(url).notifier).state = false;

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    switch (result) {
      case Success<SavedFile>(data: final file):
        AppSnackBar.show(
          context,
          message: '${file.fileName} 已保存到 ${file.path}',
          tone: AppSnackBarTone.success,
          icon: Icons.download_done_rounded,
          clearCurrent: false,
        );
      case FailureResult<SavedFile>(failure: final failure):
        AppSnackBar.show(
          context,
          message: formatError(failure).message,
          tone: AppSnackBarTone.error,
          clearCurrent: false,
        );
    }
  }

  String _buildImageFileName(String rawUrl, Uint8List bytes) {
    final uri = Uri.tryParse(rawUrl);
    final rawName = uri?.pathSegments.last.trim() ?? '';
    final sanitizedName = rawName
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (sanitizedName.isNotEmpty && sanitizedName.contains('.')) {
      return sanitizedName;
    }

    final extension = _inferImageExtension(bytes);
    return '通知图片$extension';
  }

  String _inferImageExtension(Uint8List bytes) {
    if (bytes.length >= 4 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return '.png';
    }

    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return '.jpg';
    }

    if (bytes.length >= 6 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x38) {
      return '.gif';
    }

    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return '.webp';
    }

    return '.img';
  }
}

enum _ImageSaveAction { saveAs }

class _NoticeSharePoster extends StatelessWidget {
  const _NoticeSharePoster({required this.detail, required this.images});

  final CampusNoticeDetail detail;
  final Map<String, Uint8List> images;

  @override
  Widget build(BuildContext context) {
    final categoryLabel =
        detail.item.categoryLabel ?? detail.item.category.defaultLabel;
    final dateLabel = DateFormat(
      'yyyy-MM-dd',
      'zh_CN',
    ).format(detail.item.publishedAt);
    final metaLines = <String>{
      dateLabel,
      if (detail.source != null && detail.source!.trim().isNotEmpty)
        detail.source!.trim(),
    }..removeWhere((line) => line.isEmpty);

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
                    color: const Color(0xFFB97834).withValues(alpha: 0.11),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.campaign_rounded,
                    color: Color(0xFFB97834),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    categoryLabel,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFB97834),
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
                fontSize: 24,
                height: 1.28,
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
              color: const Color(0xFFB97834).withValues(alpha: 0.18),
            ),
            const SizedBox(height: 18),
            for (final block in detail.contentBlocks)
              switch (block) {
                NoticeTextBlock(:final text) => Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Text(text),
                ),
                NoticeImageBlock(:final url) => Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _ShareImageBlock(
                    bytes: images[url],
                    failureLabel: '图片未能加载',
                  ),
                ),
              },
            if (detail.attachments.isNotEmpty) ...[
              const SizedBox(height: 6),
              const Text(
                '附件',
                style: TextStyle(
                  color: Color(0xFF142C2F),
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 10),
              for (final attachment in detail.attachments)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _ShareAttachmentRow(attachment: attachment),
                ),
            ],
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
        color: const Color(0xFFB97834).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF9D622B),
          fontSize: 11,
          fontWeight: FontWeight.w800,
          height: 1.1,
        ),
      ),
    );
  }
}

class _ShareImageBlock extends StatelessWidget {
  const _ShareImageBlock({required this.bytes, required this.failureLabel});

  final Uint8List? bytes;
  final String failureLabel;

  @override
  Widget build(BuildContext context) {
    final data = bytes;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: data == null
          ? Container(
              height: 92,
              alignment: Alignment.center,
              color: const Color(0xFFF5EFE5),
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
    );
  }
}

class _ShareAttachmentRow extends StatelessWidget {
  const _ShareAttachmentRow({required this.attachment});

  final CampusNoticeAttachment attachment;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFB97834).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.attach_file_rounded,
            color: Color(0xFFB97834),
            size: 17,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              attachment.title,
              style: const TextStyle(
                color: Color(0xFF213A3C),
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
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
                  '拾邑 · 五邑大学校园助手',
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

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.detail});

  final CampusNoticeDetail detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateLabel = DateFormat('yyyy年MM月dd日').format(detail.item.publishedAt);

    return Wrap(
      spacing: 16,
      runSpacing: 6,
      children: [
        _metaChip(theme, Icons.event_outlined, dateLabel),
        if (detail.source != null && detail.source!.isNotEmpty)
          _metaChip(theme, Icons.source_outlined, detail.source!),
      ],
    );
  }

  Widget _metaChip(ThemeData theme, IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
