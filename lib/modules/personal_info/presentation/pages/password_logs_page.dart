import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/design_tokens.dart';
import '../../../../shared/widgets/app_snackbar.dart';
import '../../domain/entities/user_log_entry.dart';
import '../controllers/user_logs_controller.dart';
import '../widgets/log_list_view.dart';
import '../widgets/log_meta_row.dart';

/// 密码维护详情页。
class PasswordLogsPage extends ConsumerWidget {
  const PasswordLogsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(passwordLogsControllerProvider);
    final notifier = ref.read(passwordLogsControllerProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: const Text('密码维护')),
      body: LogListView(
        state: state,
        onRefresh: notifier.refresh,
        onLoadMore: notifier.loadMore,
        emptyHint: '暂无密码维护记录',
        itemBuilder: (context, entry) => _PasswordLogTile(entry: entry),
      ),
    );
  }
}

class _PasswordLogTile extends StatelessWidget {
  const _PasswordLogTile({required this.entry});

  final UserLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = entry.success
        ? const Color(0xFF1C8C6E)
        : theme.colorScheme.error;
    return InkWell(
      onLongPress: () async {
        await Clipboard.setData(ClipboardData(text: entry.ip));
        if (!context.mounted) return;
        AppSnackBar.show(
          context,
          message: '已复制 ${entry.ip}',
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
              entry.success
                  ? Icons.lock_reset_rounded
                  : Icons.lock_outline_rounded,
              color: tone,
              size: 22,
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
                          entry.title ?? '密码操作',
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
