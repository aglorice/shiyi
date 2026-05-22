import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/settings/app_preferences.dart';
import '../../../../app/settings/app_preferences_controller.dart';
import '../../../../app/theme/design_tokens.dart';
import '../../../../shared/widgets/page_section.dart';
import '../../../../shared/widgets/schedule_background.dart';
import '../widgets/settings_widgets.dart';

class SettingsSchedulePage extends ConsumerWidget {
  const SettingsSchedulePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(appPreferencesControllerProvider);
    final controller = ref.read(appPreferencesControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('课表')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.pageBottomGap),
        children: [
          PageSection(
            title: '显示',
            children: [
              SettingSwitchTile(
                icon: Icons.weekend_outlined,
                title: '显示周六周日',
                subtitle: '关闭后整周课表只显示周一到周五',
                value: preferences.showWeekends,
                onChanged: controller.setShowWeekends,
              ),
            ],
          ),
          PageSection(
            title: '背景样式  ${preferences.scheduleBackgroundStyle.label}',
            divider: false,
            children: [
              SettingBlock(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: SizedBox(
                  height: 96,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.zero,
                    itemCount: ScheduleBackgroundStyle.values.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      final style = ScheduleBackgroundStyle.values[index];
                      return _BackgroundCardSlim(
                        style: style,
                        opacity: preferences.scheduleBackgroundOpacity,
                        selected:
                            preferences.scheduleBackgroundStyle == style,
                        onTap: () =>
                            controller.setScheduleBackgroundStyle(style),
                      );
                    },
                  ),
                ),
              ),
              SettingBlock(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Text(
                  preferences.scheduleBackgroundStyle.description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color:
                            Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
            ],
          ),
          PageSection(
            title:
                '背景强度  ${(preferences.scheduleBackgroundOpacity * 100).round()}%',
            divider: false,
            children: [
              SettingBlock(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Slider(
                  value: preferences.scheduleBackgroundOpacity,
                  min: 0,
                  max: 1,
                  divisions: 10,
                  label:
                      '${(preferences.scheduleBackgroundOpacity * 100).round()}%',
                  onChanged: controller.setScheduleBackgroundOpacity,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BackgroundCardSlim extends StatelessWidget {
  const _BackgroundCardSlim({
    required this.style,
    required this.opacity,
    required this.selected,
    required this.onTap,
  });

  final ScheduleBackgroundStyle style;
  final double opacity;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.md),
      onTap: onTap,
      child: Container(
        width: 96,
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: selected
                ? colorScheme.primary
                : colorScheme.outlineVariant.withValues(alpha: 0.45),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.md - 2),
          child: Stack(
            children: [
              Positioned.fill(
                child: ScheduleBackground(
                  style: style,
                  opacity: style == ScheduleBackgroundStyle.clean
                      ? 0
                      : opacity.clamp(0.22, 0.42).toDouble(),
                  borderRadius: BorderRadius.circular(AppRadius.md - 2),
                ),
              ),
              Center(
                child: Icon(style.icon, color: style.accentColor, size: 22),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 6,
                child: Center(
                  child: Text(
                    style.label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
              if (selected)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      size: 12,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
