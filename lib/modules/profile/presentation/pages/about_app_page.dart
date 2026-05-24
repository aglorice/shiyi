import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/app_links.dart';
import '../../../../app/theme/design_tokens.dart';
import '../../../../shared/widgets/app_snackbar.dart';
import '../../../../shared/widgets/page_section.dart';
import '../controllers/app_update_controller.dart';
import '../widgets/settings_widgets.dart';

/// 关于应用页：极简留白版。
/// 顶部 logo + 名字 + 版本号，下面三组：功能 / 信息 / 链接。
/// 不再用渐变 hero 和叠卡的层级。
class AboutAppPage extends ConsumerWidget {
  const AboutAppPage({super.key});

  static const _features = <_AboutFeature>[
    _AboutFeature(Icons.calendar_today_rounded, '课表'),
    _AboutFeature(Icons.school_outlined, '成绩'),
    _AboutFeature(Icons.assignment_outlined, '考试'),
    _AboutFeature(Icons.bolt_outlined, '电量'),
    _AboutFeature(Icons.notifications_none_rounded, '通知'),
    _AboutFeature(Icons.grid_view_rounded, '服务'),
    _AboutFeature(Icons.sports_tennis_rounded, '场馆'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final appInfo = ref.watch(
      installedAppInfoProvider.select(
        (value) => value.maybeWhen(data: (data) => data, orElse: () => null),
      ),
    );
    final versionLabel = appInfo?.versionLabel ?? '读取中';
    final packageName = appInfo?.packageName ?? '';
    final browserRoute = Uri(
      path: '/browser',
      queryParameters: {'title': 'GitHub', 'url': appGitHubRepositoryUrl},
    ).toString();

    return Scaffold(
      appBar: AppBar(title: const Text('关于'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.pageBottomGap),
        children: [
          const SizedBox(height: AppSpacing.lg),
          _AppIntro(versionLabel: versionLabel),
          const SizedBox(height: AppSpacing.xl),
          PageSection(
            title: '能做什么',
            divider: false,
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: GridView.count(
                  crossAxisCount: 4,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 0.86,
                  mainAxisSpacing: AppSpacing.md,
                  crossAxisSpacing: 0,
                  children: [
                    for (final feature in _features)
                      _FeatureDot(feature: feature),
                  ],
                ),
              ),
            ],
          ),
          PageSection(
            title: '应用信息',
            children: [
              _InfoRow(label: '版本号', value: versionLabel),
              if (packageName.isNotEmpty)
                _InfoRow(label: '包名', value: packageName),
              _InfoRow(label: '协议', value: 'MIT'),
            ],
          ),
          PageSection(
            title: '项目',
            children: [
              SettingActionTile(
                icon: Icons.code_rounded,
                title: '查看 GitHub 源码',
                subtitle: appGitHubRepositoryUrl,
                onTap: () => context.push(browserRoute),
              ),
              SettingActionTile(
                icon: Icons.copy_rounded,
                title: '复制仓库链接',
                onTap: () => _copyRepositoryLink(context),
              ),
              SettingActionTile(
                icon: Icons.bug_report_outlined,
                title: '反馈问题',
                subtitle: '在 GitHub 上提 Issue',
                onTap: () => context.push(browserRoute),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxl),
          Center(
            child: Text(
              'Made with care · 拾邑',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
  }

  Future<void> _copyRepositoryLink(BuildContext context) async {
    await Clipboard.setData(const ClipboardData(text: appGitHubRepositoryUrl));
    if (!context.mounted) {
      return;
    }
    AppSnackBar.show(
      context,
      message: 'GitHub 链接已复制',
      tone: AppSnackBarTone.success,
      icon: Icons.copy_rounded,
    );
  }
}

/// 顶部「应用名 + 版本」介绍块。logo 用 primary 圆角方块占位，无渐变。
class _AppIntro extends StatelessWidget {
  const _AppIntro({required this.versionLabel});

  final String versionLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pageH),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(64 * 0.225),
            child: Image.asset(
              'assets/logo/pixel_cat_logo_1024.png',
              width: 64,
              height: 64,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '拾邑',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '一个收纳大学生活的随身助理',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'v$versionLabel',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
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

class _FeatureDot extends StatelessWidget {
  const _FeatureDot({required this.feature});

  final _AboutFeature feature;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Icon(
            feature.icon,
            size: 22,
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          feature.label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _AboutFeature {
  const _AboutFeature(this.icon, this.label);

  final IconData icon;
  final String label;
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
