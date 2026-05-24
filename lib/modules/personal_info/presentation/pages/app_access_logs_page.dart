import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/design_tokens.dart';
import '../../../../shared/widgets/app_snackbar.dart';
import '../../domain/entities/user_log_entry.dart';
import '../controllers/user_logs_controller.dart';
import '../widgets/log_list_view.dart';
import '../widgets/log_meta_row.dart';

/// 应用访问详情页：app 名 + URL（短）+ IP + 时间。
class AppAccessLogsPage extends ConsumerWidget {
  const AppAccessLogsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appAccessLogsControllerProvider);
    final notifier = ref.read(appAccessLogsControllerProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: const Text('应用访问')),
      body: LogListView(
        state: state,
        onRefresh: notifier.refresh,
        onLoadMore: notifier.loadMore,
        emptyHint: '暂无应用访问记录',
        itemBuilder: (context, entry) => _AppLogTile(entry: entry),
      ),
    );
  }
}

class _AppLogTile extends StatelessWidget {
  const _AppLogTile({required this.entry});

  final UserLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onLongPress: () async {
        if (entry.appUrl == null) return;
        await Clipboard.setData(ClipboardData(text: entry.appUrl!));
        if (!context.mounted) return;
        AppSnackBar.show(
          context,
          message: '已复制链接',
          tone: AppSnackBarTone.success,
          icon: Icons.copy_rounded,
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.apps_rounded,
              size: 22,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          entry.title ?? '应用',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Text(
                        _shortTime(entry.timeLabel),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (entry.appUrl != null && entry.appUrl!.isNotEmpty)
                    LogMetaRow(
                      icon: Icons.link_rounded,
                      text: _shortenUrl(entry.appUrl!),
                    ),
                  LogMetaRow(
                    icon: Icons.public_rounded,
                    text: entry.ip,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _shortTime(String full) {
  if (full.length < 16) return full;
  return full.substring(5, 16);
}

String _shortenUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return url;
  final host = uri.host;
  final path = uri.path.isEmpty ? '' : uri.path;
  final tail = path.length > 36 ? '${path.substring(0, 33)}…' : path;
  return '$host$tail';
}
