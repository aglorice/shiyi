import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/design_tokens.dart';
import '../../../../shared/widgets/app_snackbar.dart';
import '../../../../shared/widgets/page_section.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../widgets/settings_widgets.dart';
import '../widgets/update_sheet.dart';

/// 「我」页：身份卡 + 设置入口列表 + 退出。
///
/// 整页直接铺在 scaffold 背景上，没有 SurfaceCard 嵌套；分组靠间距和小灰字。
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider).value;
    final session = authState?.session;

    return ListView(
      padding: const EdgeInsets.only(
        top: AppSpacing.lg,
        bottom: AppSpacing.pageBottomGapWithNav,
      ),
      children: [
        _IdentityRow(session: session),
        PageSection(
          title: '偏好',
          children: [
            SettingActionTile(
              icon: Icons.palette_outlined,
              title: '外观',
              subtitle: '主题色、深色、字体、字号',
              onTap: () => context.push('/settings/appearance'),
            ),
            SettingActionTile(
              icon: Icons.calendar_view_week_outlined,
              title: '课表',
              subtitle: '周末显示、背景样式、强度',
              onTap: () => context.push('/settings/schedule'),
            ),
            SettingActionTile(
              icon: Icons.sports_tennis_outlined,
              title: '场馆预约',
              subtitle: '手机号、项目、场馆类型',
              onTap: () => context.push('/settings/gym'),
            ),
          ],
        ),
        PageSection(
          title: '工具',
          children: [
            SettingActionTile(
              icon: Icons.event_note_outlined,
              title: '导出整学期课表',
              subtitle: '生成 .ics 分享到日历',
              onTap: () => context.push('/settings/schedule-export'),
            ),
            SettingActionTile(
              icon: Icons.terminal_rounded,
              title: '请求日志',
              subtitle: '查看接口请求与响应',
              onTap: () => context.push('/settings/logs'),
            ),
            SettingActionTile(
              icon: Icons.storage_rounded,
              title: '存储与缓存',
              subtitle: '清空本地缓存、重置外观',
              onTap: () => context.push('/settings/storage'),
            ),
          ],
        ),
        PageSection(
          title: '关于',
          children: [
            SettingActionTile(
              icon: Icons.system_update_alt_rounded,
              title: '版本更新',
              subtitle: '检查并安装新版',
              onTap: () => UpdateSheet.show(context, ref),
              trailing: const UpdateTileTrailing(),
            ),
            SettingActionTile(
              icon: Icons.info_outline_rounded,
              title: '关于应用',
              subtitle: '版本信息与项目仓库',
              onTap: () => context.push('/about'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xxl),
        Center(
          child: TextButton(
            onPressed: () => _confirmLogout(context, ref),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 14,
              ),
            ),
            child: const Text(
              '退出登录',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('退出后将清除当前账号的本地凭证，下次需重新登录。'),
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
            child: const Text('确定退出'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await ref.read(authControllerProvider.notifier).logout();
    if (context.mounted) {
      context.go('/login');
      AppSnackBar.show(
        context,
        message: '已退出登录',
        tone: AppSnackBarTone.info,
      );
    }
  }
}

/// 顶部用户信息行：直接贴在 scaffold 上。
class _IdentityRow extends StatelessWidget {
  const _IdentityRow({required this.session});

  final dynamic session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final rawName = session?.displayName?.toString().trim() ?? '';
    final displayName = rawName.isEmpty ? '未登录' : rawName;
    final initial =
        displayName.isNotEmpty ? displayName.substring(0, 1) : '?';
    final userId = session?.userId?.toString() ?? '-';
    final dept = session?.profile?.deptName?.toString() ?? '暂未同步院系';

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pageH,
        AppSpacing.sm,
        AppSpacing.pageH,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 32,
            backgroundColor: colorScheme.primaryContainer,
            child: Text(
              initial,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  userId,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  dept,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
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
