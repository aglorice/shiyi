import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/design_tokens.dart';
import '../../domain/entities/user_log_entry.dart';
import '../controllers/user_logs_controller.dart';
import '../widgets/ip_chip.dart';
import '../widgets/log_list_view.dart';
import '../widgets/user_agent_chip.dart';

/// 登录记录详情页：成功/失败 + 时间 + 设备 + IP + 错误原因。
class AuthLogsPage extends ConsumerWidget {
  const AuthLogsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(authLogsControllerProvider);
    final notifier = ref.read(authLogsControllerProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: const Text('登录记录')),
      body: LogListView(
        state: state,
        onRefresh: notifier.refresh,
        onLoadMore: notifier.loadMore,
        emptyHint: '暂无登录记录',
        itemBuilder: (context, entry) => _AuthLogTile(entry: entry),
      ),
    );
  }
}

class _AuthLogTile extends StatelessWidget {
  const _AuthLogTile({required this.entry});

  final UserLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone =
        entry.success ? const Color(0xFF1C8C6E) : theme.colorScheme.error;

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
                  ? Icons.check_rounded
                  : Icons.close_rounded,
              color: tone,
              size: 18,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      entry.success ? '登录成功' : '登录失败',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: tone,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      entry.title ?? '',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  entry.timeLabel,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (entry.errorMessage != null) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.error.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      entry.errorMessage!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
                ],
                if (entry.logoutTimeLabel != null &&
                    entry.logoutTimeLabel!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    '已于 ${entry.logoutTimeLabel} 退出',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (entry.userAgent != null)
                      UserAgentChip(userAgent: entry.userAgent!),
                    IpChip(
                      ip: entry.ip,
                      fallbackLocation: entry.location,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
