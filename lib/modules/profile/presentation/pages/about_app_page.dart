import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/app_links.dart';
import '../../../../shared/widgets/constrained_body.dart';
import '../../../../shared/widgets/app_snackbar.dart';
import '../../../../shared/widgets/surface_card.dart';
import '../controllers/app_update_controller.dart';

class AboutAppPage extends ConsumerWidget {
  const AboutAppPage({super.key});

  static const _featureItems = [
    _AboutFeatureItem(Icons.calendar_today_rounded, '课表'),
    _AboutFeatureItem(Icons.school_outlined, '成绩'),
    _AboutFeatureItem(Icons.assignment_rounded, '考试'),
    _AboutFeatureItem(Icons.bolt_rounded, '电量'),
    _AboutFeatureItem(Icons.notifications_rounded, '通知'),
    _AboutFeatureItem(Icons.grid_view_rounded, '服务'),
    _AboutFeatureItem(Icons.sports_tennis_rounded, '场馆'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final appInfo = ref.watch(
      installedAppInfoProvider.select(
        (value) => value.maybeWhen(data: (data) => data, orElse: () => null),
      ),
    );
    final useWideLayout = MediaQuery.sizeOf(context).width >= 860;
    final versionLabel = appInfo?.versionLabel ?? '读取中';
    final packageName = appInfo?.packageName ?? 'shiyi';
    final browserRoute = Uri(
      path: '/browser',
      queryParameters: {'title': 'GitHub', 'url': appGitHubRepositoryUrl},
    ).toString();

    return Scaffold(
      appBar: AppBar(title: const Text('关于应用')),
      body: ConstrainedBody(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            _AboutHero(versionLabel: versionLabel, packageName: packageName),
            const SizedBox(height: 16),
            if (useWideLayout)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 11,
                    child: _FeaturesPanel(
                      titleStyle: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 9,
                    child: Column(
                      children: [
                        _InfoPanel(
                          versionLabel: versionLabel,
                          packageName: packageName,
                        ),
                        const SizedBox(height: 16),
                        _GitHubPanel(
                          onOpen: () => context.push(browserRoute),
                          onCopy: () => _copyRepositoryLink(context),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            else ...[
              _FeaturesPanel(
                titleStyle: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 16),
              _InfoPanel(versionLabel: versionLabel, packageName: packageName),
              const SizedBox(height: 16),
              _GitHubPanel(
                onOpen: () => context.push(browserRoute),
                onCopy: () => _copyRepositoryLink(context),
              ),
            ],
          ],
        ),
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

class _AboutHero extends StatelessWidget {
  const _AboutHero({required this.versionLabel, required this.packageName});

  final String versionLabel;
  final String packageName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          colors: [
            colorScheme.primary,
            Color.lerp(colorScheme.primary, colorScheme.tertiary, 0.58) ??
                colorScheme.tertiary,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -36,
            right: -20,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.09),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            bottom: -34,
            left: -14,
            child: Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'ABOUT 拾邑',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '拾邑',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '五邑大学校园助手',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.92),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _HeroChip(label: 'v$versionLabel'),
                          _HeroChip(label: packageName),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Container(
                  width: 88,
                  height: 88,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.18),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.asset(
                      'assets/logo/pixel_cat_logo_1024.png',
                      fit: BoxFit.cover,
                    ),
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

class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _FeaturesPanel extends StatelessWidget {
  const _FeaturesPanel({required this.titleStyle});

  final TextStyle? titleStyle;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('核心能力', style: titleStyle),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: AboutAppPage._featureItems
                .map((item) => _FeatureBadge(item: item))
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _FeatureBadge extends StatelessWidget {
  const _FeatureBadge({required this.item});

  final _AboutFeatureItem item;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(item.icon, size: 18, color: colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            item.label,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({required this.versionLabel, required this.packageName});

  final String versionLabel;
  final String packageName;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '应用信息',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 14),
          _InfoRow(label: '名称', value: '拾邑'),
          const SizedBox(height: 12),
          _InfoRow(label: '版本', value: versionLabel),
          const SizedBox(height: 12),
          _InfoRow(label: '包名', value: packageName),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 44,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _GitHubPanel extends StatelessWidget {
  const _GitHubPanel({required this.onOpen, required this.onCopy});

  final VoidCallback onOpen;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.code_rounded, color: colorScheme.onSurface),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'GitHub',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '$appGitHubOwner/$appGitHubRepo',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            appGitHubRepositoryUrl,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('查看仓库'),
                ),
              ),
              const SizedBox(width: 12),
              IconButton.filledTonal(
                tooltip: '复制链接',
                onPressed: onCopy,
                icon: const Icon(Icons.copy_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AboutFeatureItem {
  const _AboutFeatureItem(this.icon, this.label);

  final IconData icon;
  final String label;
}
