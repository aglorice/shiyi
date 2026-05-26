import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/settings/app_preferences.dart';
import '../../../../app/settings/app_preferences_controller.dart';
import '../../../../app/theme/design_tokens.dart';
import '../../../../shared/widgets/page_section.dart';

/// 字体与字号独立设置页。
///
/// 从原本"外观"页里拆出来，避免一页里塞太多 section。
/// 顶部一张实时预览卡片，下面才是字体 / 字号选择，所有改动立刻反映在预览。
class SettingsTypographyPage extends ConsumerWidget {
  const SettingsTypographyPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(appPreferencesControllerProvider);
    final controller = ref.read(appPreferencesControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('字体与字号'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.pageBottomGap),
        children: [
          // 预览卡片
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.pageH,
              AppSpacing.md,
              AppSpacing.pageH,
              AppSpacing.sm,
            ),
            child: _Preview(
              preset: preferences.fontPreset,
              scale: preferences.fontScale,
            ),
          ),
          PageSection(
            title: '字体风格',
            children: [
              for (final preset in AppFontPreset.values)
                _FontPresetTile(
                  preset: preset,
                  selected: preferences.fontPreset == preset,
                  onTap: () => controller.setFontPreset(preset),
                ),
            ],
          ),
          PageSection(
            title: '字号',
            divider: false,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.md,
                  AppSpacing.sm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          '小',
                          style: TextStyle(fontSize: 12),
                        ),
                        Expanded(
                          child: Slider(
                            value: preferences.fontScale,
                            min: 0.9,
                            max: 1.2,
                            divisions: 6,
                            label: preferences.fontScaleLabel,
                            onChanged: controller.setFontScale,
                          ),
                        ),
                        const Text(
                          '大',
                          style: TextStyle(fontSize: 18),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '当前 ${preferences.fontScaleLabel}',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                        TextButton(
                          onPressed: preferences.fontScale == 1.0
                              ? null
                              : () => controller.setFontScale(1.0),
                          child: const Text('恢复默认'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.preset, required this.scale});

  final AppFontPreset preset;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final family = preset.fontFamily;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md + 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
          width: 0.6,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '拾邑',
            style: TextStyle(
              fontFamily: family,
              fontSize: 28 * scale,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
              height: 1.0,
              color: theme.colorScheme.onSurface,
            ),
          ),
          SizedBox(height: 6 * scale),
          Text(
            '拾取校园点滴 邑你相伴同行',
            style: TextStyle(
              fontFamily: family,
              fontSize: 13 * scale,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          SizedBox(height: 14 * scale),
          Text(
            '一段示例正文：早上 8:15 高等数学 A，在 10 号楼 305。下午没有课，可以去图书馆找个角落安心读两个小时。',
            style: TextStyle(
              fontFamily: family,
              fontSize: 14 * scale,
              fontWeight: FontWeight.w500,
              color: theme.colorScheme.onSurface,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _FontPresetTile extends StatelessWidget {
  const _FontPresetTile({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final AppFontPreset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm + 2,
        ),
        child: Row(
          children: [
            // 单个字符样张，按当前预设字体显示
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Text(
                'Aa',
                style: TextStyle(
                  fontFamily: preset.fontFamily,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    preset.label,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    preset.description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(
                Icons.check_rounded,
                color: theme.colorScheme.primary,
              ),
          ],
        ),
      ),
    );
  }
}
