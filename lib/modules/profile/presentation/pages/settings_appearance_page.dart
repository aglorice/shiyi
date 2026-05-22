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
      appBar: AppBar(title: const Text('外观'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.pageBottomGap),
        children: [
          PageSection(
            title: '主题模式',
            divider: false,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: _ThemeModeRow(
                  current: preferences.themeMode,
                  onChanged: controller.setThemeMode,
                ),
              ),
            ],
          ),
          PageSection(
            title: '阅读体验',
            children: [
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
                subtitle: '页面信息密度更高，列表更紧',
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
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
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
            ],
          ),
        ],
      ),
    );
  }
}

/// 三栏式 chip：浅色 / 深色 / 跟随系统。
class _ThemeModeRow extends StatelessWidget {
  const _ThemeModeRow({required this.current, required this.onChanged});

  final AppThemeMode current;
  final ValueChanged<AppThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        for (var i = 0; i < AppThemeMode.values.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _ThemeModeCard(
              mode: AppThemeMode.values[i],
              selected: current == AppThemeMode.values[i],
              onTap: () => onChanged(AppThemeMode.values[i]),
              theme: theme,
            ),
          ),
        ],
      ],
    );
  }
}

class _ThemeModeCard extends StatelessWidget {
  const _ThemeModeCard({
    required this.mode,
    required this.selected,
    required this.onTap,
    required this.theme,
  });

  final AppThemeMode mode;
  final bool selected;
  final VoidCallback onTap;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final isDarkPreview = mode == AppThemeMode.dark;
    final previewBg = isDarkPreview
        ? const Color(0xFF1B1A1A)
        : const Color(0xFFFAF8F6);
    final previewFg = isDarkPreview ? Colors.white : Colors.black;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm + 2),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Container(
              height: 48,
              decoration: BoxDecoration(
                color: previewBg,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              alignment: Alignment.center,
              child: Icon(mode.icon, size: 20, color: previewFg),
            ),
            const SizedBox(height: 8),
            Text(
              mode.label,
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
        padding: const EdgeInsets.all(AppSpacing.xxs),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: preset.seedColor,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected
                      ? theme.colorScheme.onSurface
                      : Colors.transparent,
                  width: selected ? 2.5 : 0,
                ),
              ),
              child: selected
                  ? const Center(
                      child: Icon(
                        Icons.check_rounded,
                        size: 20,
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
