import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/design_tokens.dart';
import '../../domain/entities/user_log_entry.dart';
import '../controllers/user_logs_controller.dart';
import '../widgets/ip_chip.dart';
import '../widgets/log_list_view.dart';

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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              entry.success
                  ? Icons.lock_reset_rounded
                  : Icons.lock_outline_rounded,
              color: tone,
              size: 18,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.title ?? '密码操作',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  entry.timeLabel,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 8),
                IpChip(ip: entry.ip),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
