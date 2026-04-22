import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../app/di/app_providers.dart';
import '../../../../core/error/error_display.dart';
import '../../../../core/platform/file_save_service.dart';
import '../../../../core/result/result.dart';
import '../../../../shared/widgets/async_value_view.dart';
import '../../../../shared/widgets/app_snackbar.dart';
import '../../../../shared/widgets/constrained_body.dart';
import '../../domain/entities/campus_notice.dart';
import '../controllers/notice_detail_controller.dart';

class NoticeDetailPage extends ConsumerWidget {
  const NoticeDetailPage({super.key, required this.item});

  final CampusNoticeItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(noticeDetailProvider(item));

    return Scaffold(
      appBar: AppBar(
        title: Text(item.categoryLabel ?? item.category.defaultLabel),
      ),
      body: ConstrainedBody(
        child: AsyncValueView(
          value: detailAsync,
          onRetry: () => ref.invalidate(noticeDetailProvider(item)),
          loadingLabel: '加载中',
          dataBuilder: (detail) => RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(noticeDetailProvider(item));
              await ref.read(noticeDetailProvider(item).future);
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
