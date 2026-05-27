import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/design_tokens.dart';
import '../../../../core/error/failure.dart';
import '../../../../shared/widgets/app_snackbar.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/module_error_state.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../domain/entities/user_log_entry.dart';
import '../controllers/user_logs_controller.dart';
import '../widgets/log_meta_row.dart';

/// 当前在线管理页。
class OnlineSessionsPage extends ConsumerWidget {
  const OnlineSessionsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(onlineSessionsControllerProvider);
    final notifier = ref.read(onlineSessionsControllerProvider.notifier);
    final theme = Theme.of(context);

    // 兜底：列表本身被 SessionExpiredFailure 打中（比如踢自己后服务端返回 200，
    // 但下一次刷新立刻 302）。直接走和 selfKicked 一样的清场逻辑。
    ref.listen(onlineSessionsControllerProvider, (prev, next) async {
      final wasExpired = prev?.failure is SessionExpiredFailure;
      final isExpired = next.failure is SessionExpiredFailure;
      if (!wasExpired && isExpired && context.mounted) {
        await ref.read(authControllerProvider.notifier).logout();
        if (!context.mounted) return;
        context.go('/login');
        AppSnackBar.show(
          context,
          message: '登录已过期，请重新登录',
          tone: AppSnackBarTone.info,
        );
      }
    });

    Widget body;
    if (state.loading && state.items.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (state.error != null && state.items.isEmpty) {
      body = ModuleErrorState(message: state.error!, onRetry: notifier.refresh);
    } else if (state.items.isEmpty) {
      body = RefreshIndicator(
        onRefresh: notifier.refresh,
        child: ListView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.pageH,
            vertical: AppSpacing.lg,
          ),
          children: const [
            SizedBox(height: 40),
            EmptyState(
              title: '当前没有在线会话',
              subtitle: '其他设备登录时会出现在这里。',
              mood: EmptyStateMood.empty,
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
        .kickOnlineSession(session.id, isCurrent: session.isCurrent);

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
    return InkWell(
      onLongPress: () async {
        await Clipboard.setData(ClipboardData(text: session.ip));
        if (!context.mounted) return;
        AppSnackBar.show(
          context,
          message: '已复制 ${session.ip}',
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
              _osIcon(session.userAgent),
              size: 22,
              color: session.isCurrent
                  ? const Color(0xFF1C8C6E)
                  : theme.colorScheme.onSurface,
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
                          _formatUa(session.userAgent),
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (session.isCurrent)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Text(
                            '当前',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: const Color(0xFF1C8C6E),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      InkWell(
                        onTap: onKick,
                        borderRadius: BorderRadius.circular(999),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            session.isCurrent
                                ? Icons.logout_rounded
                                : Icons.power_settings_new_rounded,
                            size: 18,
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  LogMetaRow(
                    icon: Icons.access_time_rounded,
                    text: _shortTime(session.loginTimeLabel),
                    secondary: session.loginTypeDesc,
                  ),
                  LogMetaRow(
                    icon: Icons.public_rounded,
                    text: session.ip,
                    secondary: session.location,
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

IconData _osIcon(String ua) {
  final s = ua.toLowerCase();
  if (s.startsWith('mac')) return Icons.laptop_mac_rounded;
  if (s.startsWith('windows')) return Icons.desktop_windows_rounded;
  if (s.startsWith('android')) return Icons.phone_android_rounded;
  if (s.startsWith('iphone') || s.startsWith('ios') || s.startsWith('ipad')) {
    return Icons.phone_iphone_rounded;
  }
  if (s.startsWith('linux')) return Icons.terminal_rounded;
  return Icons.devices_other_rounded;
}

String _formatUa(String ua) {
  if (ua.trim().isEmpty) return '未知设备';
  final segs = ua.split(' ');
  final osRaw = segs.first.toLowerCase();
  String os;
  if (osRaw.startsWith('mac')) {
    os = 'macOS';
  } else if (osRaw.startsWith('windows')) {
    final parts = osRaw.replaceAll('_', ' ').split(' ');
    os = parts.length >= 2
        ? 'Windows ${parts.sublist(1).join(' ')}'
        : 'Windows';
  } else if (osRaw.startsWith('android')) {
    final cap = osRaw.replaceAll('_', ' ');
    os = '${cap[0].toUpperCase()}${cap.substring(1)}';
  } else if (osRaw.startsWith('iphone') ||
      osRaw.startsWith('ios') ||
      osRaw.startsWith('ipad')) {
    os = 'iOS';
  } else if (osRaw.startsWith('linux')) {
    os = 'Linux';
  } else {
    os = osRaw;
  }
  if (segs.length < 2) return os;
  final br = segs.sublist(1).join(' ');
  final m = RegExp(r'([a-zA-Z]+)\d*/(\d+)').firstMatch(br);
  if (m != null) {
    final name = m.group(1) ?? '';
    final ver = m.group(2) ?? '';
    if (name.isNotEmpty) {
      return '$os · ${name[0].toUpperCase()}${name.substring(1)} $ver';
    }
  }
  return '$os · $br';
}
