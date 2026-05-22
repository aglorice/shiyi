import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/settings/app_preferences.dart';
import '../../../../app/settings/app_preferences_controller.dart';
import '../../../../app/theme/design_tokens.dart';
import '../../../../shared/widgets/page_section.dart';
import '../widgets/settings_widgets.dart';

class SettingsAppearancePage extends ConsumerWidget {
  const SettingsAppearancePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(appPreferencesControllerProvider);
    final controller = ref.read(appPreferencesControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('外观')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.pageBottomGap),
        children: [
          PageSection(
            title: '显示模式',
            children: [
              SettingSwitchTile(
                icon: Icons.dark_mode_outlined,
                title: '深色主题',
                subtitle: '晚上或低亮度环境更耐看',
                value: preferences.darkMode,
                onChanged: controller.setDarkMode,
              ),
              SettingSwitchTile(
                icon: Icons.contrast_outlined,
                title: '增强对比',
                subtitle: '让文字和边界更清楚',
                value: preferences.highContrast,
                onChanged: controller.setHighContrast,
              ),
              SettingSwitchTile(
                icon: Icons.view_compact_alt_outlined,
                title: '紧凑布局',
                subtitle: '让页面信息密度更高',
                value: preferences.compactMode,
                onChanged: controller.setCompactMode,
              ),
            ],
          ),
          PageSection(
            title: '主题色',
            divider: false,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final preset in AppThemePreset.values)
                      _ThemeDot(
                        preset: preset,
                        selected: preferences.themePreset == preset,
                        onTap: () => controller.setThemePreset(preset),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: AppSpacing.sm),
                child: Text(
                  preferences.themePreset.description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color:
                            Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
            ],
          ),
          PageSection(
            title: '字体',
            divider: false,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: SegmentedButton<AppFontPreset>(
                  multiSelectionEnabled: false,
                  showSelectedIcon: false,
                  segments: AppFontPreset.values
                      .map(
                        (preset) => ButtonSegment<AppFontPreset>(
                          value: preset,
                          label: Text(preset.label),
                        ),
                      )
                      .toList(),
                  selected: {preferences.fontPreset},
                  onSelectionChanged: (selection) {
                    controller.setFontPreset(selection.first);
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Text(
                  preferences.fontPreset.description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color:
                            Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
            ],
          ),
          PageSection(
            title: '字号  ${preferences.fontScaleLabel}',
            divider: false,
            children: [
              SettingBlock(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Slider(
                  value: preferences.fontScale,
                  min: 0.9,
                  max: 1.2,
                  divisions: 6,
                  label: preferences.fontScaleLabel,
                  onChanged: controller.setFontScale,
                ),
              ),
              SettingBlock(
                padding: const EdgeInsets.only(top: 4, bottom: AppSpacing.sm),
                child: Text(
                  '示例：今天没有早八，正好把课表导出到日历看看。',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ThemeDot extends StatelessWidget {
  const _ThemeDot({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final AppThemePreset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: preset.seedColor,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.outlineVariant
                          .withValues(alpha: 0.55),
                  width: selected ? 2 : 1,
                ),
              ),
              child: selected
                  ? const Center(
                      child: Icon(
                        Icons.check_rounded,
                        size: 18,
                        color: Colors.white,
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: 6),
            Text(
              preset.label,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
