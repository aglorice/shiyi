import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/design_tokens.dart';
import '../../../../shared/widgets/app_snackbar.dart';
import '../../../../shared/widgets/page_section.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../domain/entities/user_log_entry.dart';
import '../controllers/user_logs_controller.dart';
import '../widgets/ip_chip.dart';

/// 个人中心：当前在线 / 登录记录 / 应用访问 / 密码维护。
///
/// 整页布局走小红书风：scaffold 直接铺背景，上面一段一段 PageSection；
/// 不画卡片，只用极淡分隔线和小灰字标题区隔。
class PersonalInfoPage extends ConsumerWidget {
  const PersonalInfoPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(userLogsControllerProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('个人中心'),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () =>
                ref.read(userLogsControllerProvider.notifier).loadAll(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () =>
            ref.read(userLogsControllerProvider.notifier).loadAll(),
        child: ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.pageBottomGap),
          children: [
            _OnlineSection(value: state.online),
            _LogSection(
              title: '登录记录',
              hint: '账号在 authserver 上的登录尝试',
              value: state.authLogs,
              builder: _AuthLogTile.new,
            ),
            _LogSection(
              title: '应用访问',
              hint: '通过单点登录访问的应用',
              value: state.appLogs,
              builder: _AppLogTile.new,
            ),
            _LogSection(
              title: '密码维护',
              hint: '密码修改 / 找回操作',
              value: state.pwdLogs,
              builder: _PasswordLogTile.new,
            ),
          ],
        ),
      ),
    );
  }
}

class _OnlineSection extends ConsumerWidget {
  const _OnlineSection({required this.value});

  final AsyncValue<List<OnlineSession>> value;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return value.when(
      loading: () => const _SectionSkeleton(title: '当前在线'),
      error: (e, _) => _SectionError(title: '当前在线', message: '$e'),
      data: (list) => PageSection(
        title: '当前在线',
        action: Text(
          '${list.length} 个会话',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        children: list.isEmpty
            ? [const _EmptyRow(message: '暂无在线会话')]
            : list
                .map((s) => _OnlineTile(
                      session: s,
                      onKick: () => _confirmKick(context, ref, s),
                    ))
                .toList(),
      ),
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
              : '将让 ${_shortUa(session.userAgent)} 在 ${session.ip} 上的登录立刻失效，是否继续？',
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
        .read(userLogsControllerProvider.notifier)
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
        // 自己被踢：清本地 + 跳登录页。
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

class _LogSection<T> extends StatelessWidget {
  const _LogSection({
    required this.title,
    required this.hint,
    required this.value,
    required this.builder,
  });

  final String title;
  final String hint;
  final AsyncValue<UserLogPage> value;
  final Widget Function(UserLogEntry entry) builder;

  @override
  Widget build(BuildContext context) {
    return value.when(
      loading: () => _SectionSkeleton(title: title),
      error: (e, _) => _SectionError(title: title, message: '$e'),
      data: (page) {
        final theme = Theme.of(context);
        return PageSection(
          title: title,
          action: Text(
            '共 ${page.total} 条',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          children: page.items.isEmpty
              ? [_EmptyRow(message: hint)]
              : page.items.map(builder).toList(),
        );
      },
    );
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
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 8),
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
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          Text(
                            _shortUa(session.userAgent),
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
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
                      icon: Icon(
                        session.isCurrent
                            ? Icons.logout_rounded
                            : Icons.power_settings_new_rounded,
                        size: 20,
                        color: theme.colorScheme.error,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      session.loginTimeLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      '·',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      session.loginTypeDesc,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
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

class _AuthLogTile extends StatelessWidget {
  const _AuthLogTile(this.entry);

  final UserLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = entry.success
        ? const Color(0xFF1C8C6E)
        : theme.colorScheme.error;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            entry.success
                ? Icons.check_circle_outline_rounded
                : Icons.error_outline_rounded,
            color: tone,
            size: 22,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.title ?? '登录',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  entry.timeLabel,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (entry.errorMessage != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    entry.errorMessage!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                IpChip(
                  ip: entry.ip,
                  fallbackLocation: entry.location,
                ),
                if (entry.userAgent != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _shortUa(entry.userAgent!),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AppLogTile extends StatelessWidget {
  const _AppLogTile(this.entry);

  final UserLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.apps_rounded,
            size: 22,
            color: theme.colorScheme.onSurface,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.title ?? '应用',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (entry.appUrl != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    entry.appUrl!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Text(
                      entry.timeLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    IpChip(ip: entry.ip),
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

class _PasswordLogTile extends StatelessWidget {
  const _PasswordLogTile(this.entry);

  final UserLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = entry.success
        ? const Color(0xFF1C8C6E)
        : theme.colorScheme.error;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
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
                Text(
                  entry.title ?? '密码操作',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  entry.timeLabel,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                IpChip(ip: entry.ip),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyRow extends StatelessWidget {
  const _EmptyRow({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(
        message,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _SectionSkeleton extends StatelessWidget {
  const _SectionSkeleton({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return PageSection(
      title: title,
      children: const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionError extends StatelessWidget {
  const _SectionError({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PageSection(
      title: title,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            children: [
              Icon(
                Icons.error_outline_rounded,
                color: theme.colorScheme.error,
                size: 18,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

String _shortUa(String? ua) {
  if (ua == null || ua.trim().isEmpty) return '未知设备';
  // "windows_10 chrome13/131.0.0.0" → "Windows · Chrome 131"
  final segs = ua.split(' ');
  if (segs.length < 2) return ua;
  final os = segs[0]
      .replaceAll('_', ' ')
      .replaceAll('mac os x', 'macOS')
      .replaceAll('windows', 'Windows')
      .replaceAll('android', 'Android')
      .replaceAll('iphone', 'iPhone')
      .replaceAll('ios', 'iOS')
      .trim();
  final br = segs.sublist(1).join(' ');
  final brMatch = RegExp(r'([a-zA-Z]+)(?:\d+)?/(\d+)').firstMatch(br);
  if (brMatch != null) {
    final name = brMatch.group(1) ?? '';
    final ver = brMatch.group(2) ?? '';
    final namePretty = name[0].toUpperCase() + name.substring(1);
    return '$os · $namePretty $ver';
  }
  return '$os · $br';
}
