import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/design_tokens.dart';
import '../../../../shared/widgets/app_snackbar.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../domain/entities/user_log_entry.dart';
import '../controllers/user_logs_controller.dart';
import '../widgets/ip_chip.dart';
import '../widgets/user_agent_chip.dart';

/// 当前在线管理页。
///
/// 列表项右侧带"踢出"按钮：踢自己 → 自动登出回登录页；踢其它则刷新列表。
class OnlineSessionsPage extends ConsumerWidget {
  const OnlineSessionsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(onlineSessionsControllerProvider);
    final notifier = ref.read(onlineSessionsControllerProvider.notifier);
    final theme = Theme.of(context);

    Widget body;
    if (state.loading && state.items.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (state.error != null && state.items.isEmpty) {
      body = _ErrorView(message: state.error!, onRetry: notifier.refresh);
    } else if (state.items.isEmpty) {
      body = RefreshIndicator(
        onRefresh: notifier.refresh,
        child: ListView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.pageH,
            vertical: AppSpacing.lg,
          ),
          children: [
            const SizedBox(height: 80),
            Center(
              child: Text(
                '暂无在线会话',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      body = RefreshIndicator(
        onRefresh: notifier.refresh,
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.pageH,
            AppSpacing.sm,
            AppSpacing.pageH,
            AppSpacing.pageBottomGap,
          ),
          itemCount: state.items.length,
          separatorBuilder: (_, __) => Divider(
            height: 0.6,
            thickness: 0.6,
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
            indent: 32,
          ),
          itemBuilder: (context, index) => _OnlineTile(
            session: state.items[index],
            onKick: () => _confirmKick(context, ref, state.items[index]),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('当前在线'),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: notifier.refresh,
          ),
        ],
      ),
      body: body,
    );
  }

  Future<void> _confirmKick(
    BuildContext context,
    WidgetRef ref,
    OnlineSession session,
  ) async {
    final isSelf = session.isCurrent;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isSelf ? '退出当前登录' : '踢出该登录'),
        content: Text(
          isSelf
              ? '这是当前正在使用的会话，踢出后会立即返回登录页。是否继续？'
              : '将让 ${session.ip} 的登录立刻失效，是否继续？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(isSelf ? '退出登录' : '确定踢出'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final result = await ref
        .read(onlineSessionsControllerProvider.notifier)
        .kickOnlineSession(session.id);

    if (!context.mounted) return;
    switch (result) {
      case KickOnlineResult.success:
        AppSnackBar.show(
          context,
          message: '已踢出该会话',
          tone: AppSnackBarTone.success,
        );
      case KickOnlineResult.selfKicked:
        await ref.read(authControllerProvider.notifier).logout();
        if (!context.mounted) return;
        context.go('/login');
        AppSnackBar.show(
          context,
          message: '已退出当前登录',
          tone: AppSnackBarTone.info,
        );
      case KickOnlineResult.error:
        AppSnackBar.show(
          context,
          message: '操作失败，请稍后重试',
          tone: AppSnackBarTone.error,
        );
    }
  }
}

class _OnlineTile extends StatelessWidget {
  const _OnlineTile({required this.session, required this.onKick});

  final OnlineSession session;
  final VoidCallback onKick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 9),
            decoration: BoxDecoration(
              color: session.isCurrent
                  ? const Color(0xFF1C8C6E)
                  : theme.colorScheme.outlineVariant,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          UserAgentChip(userAgent: session.userAgent),
                          if (session.isCurrent)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0x1A1C8C6E),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Text(
                                '当前',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF1C8C6E),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: session.isCurrent ? '退出当前登录' : '踢出该登录',
                      onPressed: onKick,
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        session.isCurrent
                            ? Icons.logout_rounded
                            : Icons.power_settings_new_rounded,
                        size: 20,
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${session.loginTimeLabel} · ${session.loginTypeDesc}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                IpChip(
                  ip: session.ip,
                  fallbackLocation: session.location,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              color: theme.colorScheme.error,
              size: 36,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.tonal(
              onPressed: onRetry,
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}
