import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/design_tokens.dart';
import '../../../../shared/widgets/page_section.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../profile/presentation/widgets/settings_widgets.dart';

/// 个人中心入口页：四个分组入口卡。
///
/// 设计风格沿用「我」页：直接铺背景 + PageSection + SettingActionTile，
/// 不画卡片嵌套。点击进入对应详情页查看分页列表。
class PersonalInfoPage extends ConsumerWidget {
  const PersonalInfoPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session =
        ref.watch(authControllerProvider).asData?.value.session;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('个人中心')),
      body: ListView(
        padding: const EdgeInsets.only(
          top: AppSpacing.sm,
          bottom: AppSpacing.pageBottomGap,
        ),
        children: [
          if (session != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.pageH,
                AppSpacing.sm,
                AppSpacing.pageH,
                AppSpacing.lg,
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Text(
                      (session.displayName.isEmpty
                              ? '?'
                              : session.displayName.substring(0, 1))
                          .toUpperCase(),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          session.displayName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          session.userId,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontFeatures: const [
                              FontFeature.tabularFigures()
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          PageSection(
            title: '安全',
            children: [
              SettingActionTile(
                icon: Icons.devices_rounded,
                title: '当前在线',
                subtitle: '管理已登录的设备',
                onTap: () => context.push('/personal-info/online'),
              ),
              SettingActionTile(
                icon: Icons.login_rounded,
                title: '登录记录',
                subtitle: '查看历次登录尝试',
                onTap: () => context.push('/personal-info/auth-logs'),
              ),
              SettingActionTile(
                icon: Icons.lock_reset_rounded,
                title: '密码维护',
                subtitle: '密码修改与找回操作',
                onTap: () => context.push('/personal-info/password-logs'),
              ),
            ],
          ),
          PageSection(
            title: '应用',
            children: [
              SettingActionTile(
                icon: Icons.apps_rounded,
                title: '应用访问',
                subtitle: '通过单点登录访问的应用',
                onTap: () => context.push('/personal-info/app-logs'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
