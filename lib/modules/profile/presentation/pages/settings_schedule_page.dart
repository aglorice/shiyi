import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../app/settings/app_preferences.dart';
import '../../../../app/settings/app_preferences_controller.dart';
import '../../../../app/di/app_providers.dart';
import '../../../../app/theme/design_tokens.dart';
import '../../../../shared/widgets/app_snackbar.dart';
import '../../../../shared/widgets/page_section.dart';
import '../../../../shared/widgets/schedule_background.dart';
import '../widgets/settings_widgets.dart';
import 'settings_schedule_timing_page.dart';

class SettingsSchedulePage extends ConsumerStatefulWidget {
  const SettingsSchedulePage({super.key});

  @override
  ConsumerState<SettingsSchedulePage> createState() =>
      _SettingsSchedulePageState();
}

class _SettingsSchedulePageState extends ConsumerState<SettingsSchedulePage> {
  final _picker = ImagePicker();
  bool _picking = false;

  @override
  Widget build(BuildContext context) {
    final preferences = ref.watch(appPreferencesControllerProvider);
    final controller = ref.read(appPreferencesControllerProvider.notifier);
    final hasCustom = (preferences.customScheduleBackgroundPath ?? '').isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('课表'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.pageBottomGap),
        children: [
          PageSection(
            title: '上课提醒',
            children: [
              SettingSwitchTile(
                icon: Icons.notifications_active_outlined,
                title: '启用上课提醒',
                subtitle:
                    preferences.classRemindersEnabled
                        ? (preferences.scheduleTiming.enabled
                            ? '上课前 ${preferences.classReminderLeadMinutes} 分钟推送本地通知'
                            : '需要先在「具体时间设置」里启用精确时段才能提醒')
                        : '开启后会按节次时间推送本地通知',
                value: preferences.classRemindersEnabled,
                onChanged: (value) =>
                    _onToggleClassReminders(context, controller, value),
              ),
              if (preferences.classRemindersEnabled)
                SettingActionTile(
                  icon: Icons.timer_outlined,
                  title: '提前多久提醒',
                  subtitle: preferences.classReminderLeadMinutes == 0
                      ? '准点提醒'
                      : '上课前 ${preferences.classReminderLeadMinutes} 分钟',
                  onTap: () => _pickReminderLead(context, controller,
                      current: preferences.classReminderLeadMinutes),
                ),
            ],
          ),
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
              SettingActionTile(
                icon: Icons.schedule_rounded,
                title: '具体时间设置',
                subtitle: preferences.scheduleTiming.enabled
                    ? '已启用：自定义节次时间'
                    : '关闭，使用学校默认/原始时段',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const SettingsScheduleTimingPage(),
                  ),
                ),
              ),
            ],
          ),
          PageSection(
            title: '自定义图片',
            divider: false,
            children: [
              SettingBlock(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: _CustomImageRow(
                  hasCustom: hasCustom,
                  picking: _picking,
                  onPick: _pickImage,
                  onClear: () =>
                      controller.setCustomScheduleBackgroundPath(null),
                ),
              ),
              if (hasCustom)
                SettingBlock(
                  padding: const EdgeInsets.only(top: 0, bottom: AppSpacing.sm),
                  child: Text(
                    '已使用自定义图片，预设样式将作为图片消失时的兜底。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
          PageSection(
            title: '内置背景  ${preferences.scheduleBackgroundStyle.label}',
            divider: false,
            children: [
              SettingBlock(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: SizedBox(
                  height: 130,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.pageH,
                    ),
                    itemCount: ScheduleBackgroundStyleX.selectable.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (context, index) {
                      final style =
                          ScheduleBackgroundStyleX.selectable[index];
                      return _BackgroundCard(
                        style: style,
                        opacity: preferences.scheduleBackgroundOpacity,
                        selected:
                            preferences.scheduleBackgroundStyle == style &&
                                !hasCustom,
                        onTap: () =>
                            controller.setScheduleBackgroundStyle(style),
                      );
                    },
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

  Future<void> _onToggleClassReminders(
    BuildContext context,
    AppPreferencesController controller,
    bool value,
  ) async {
    if (!value) {
      await controller.setClassRemindersEnabled(false);
      return;
    }
    final service = ref.read(classReminderServiceProvider);
    final granted = await service.requestPermission();
    if (!granted) {
      if (!context.mounted) return;
      AppSnackBar.show(
        context,
        message: '未获得通知权限，无法启用提醒',
        tone: AppSnackBarTone.error,
      );
      return;
    }
    await controller.setClassRemindersEnabled(true);
  }

  Future<void> _pickReminderLead(
    BuildContext context,
    AppPreferencesController controller, {
    required int current,
  }) async {
    const options = [0, 5, 10, 15, 20, 30];
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    '提前多久提醒',
                    style: Theme.of(sheetContext)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                for (final minutes in options)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      minutes == current
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: Theme.of(sheetContext).colorScheme.primary,
                    ),
                    title: Text(minutes == 0 ? '准点提醒' : '$minutes 分钟前'),
                    onTap: () =>
                        Navigator.of(sheetContext).pop(minutes),
                  ),
              ],
            ),
          ),
        );
      },
    );
    if (picked != null && picked != current) {
      await controller.setClassReminderLeadMinutes(picked);
    }
  }

  Future<void> _pickImage() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
        maxWidth: 2000,
        maxHeight: 2000,
      );
      if (picked == null) return;
      // 把图片复制到 app 文档目录，不依赖临时缓存被回收。
      final dir = await getApplicationDocumentsDirectory();
      final ext = picked.path.split('.').last;
      final dest = File(
        '${dir.path}/schedule_background_'
        '${DateTime.now().millisecondsSinceEpoch}.$ext',
      );
      await File(picked.path).copy(dest.path);

      final controller = ref.read(appPreferencesControllerProvider.notifier);
      // 删除上一次的旧文件，避免无限堆积。
      final old = ref
          .read(appPreferencesControllerProvider)
          .customScheduleBackgroundPath;
      if (old != null && old.isNotEmpty) {
        try {
          await File(old).delete();
        } catch (_) {}
      }
      await controller.setCustomScheduleBackgroundPath(dest.path);
      if (mounted) {
        AppSnackBar.show(
          context,
          message: '已设置为课表背景',
          tone: AppSnackBarTone.success,
        );
      }
    } catch (error) {
      if (mounted) {
        AppSnackBar.show(
          context,
          message: '选择图片失败：$error',
          tone: AppSnackBarTone.error,
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }
}

class _CustomImageRow extends StatelessWidget {
  const _CustomImageRow({
    required this.hasCustom,
    required this.picking,
    required this.onPick,
    required this.onClear,
  });

  final bool hasCustom;
  final bool picking;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pageH),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.tonalIcon(
              onPressed: picking ? null : onPick,
              icon: picking
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.image_outlined),
              label: Text(picking
                  ? '处理中…'
                  : (hasCustom ? '更换图片' : '从相册选择')),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
              ),
            ),
          ),
          if (hasCustom) ...[
            const SizedBox(width: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: onClear,
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: const Text('清除'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                foregroundColor: theme.colorScheme.error,
                side: BorderSide(
                  color: theme.colorScheme.error.withValues(alpha: 0.3),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BackgroundCard extends StatelessWidget {
  const _BackgroundCard({
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
        width: 110,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: selected
                ? colorScheme.primary
                : colorScheme.outlineVariant.withValues(alpha: 0.5),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ScheduleBackground(
                      style: style,
                      opacity: style == ScheduleBackgroundStyle.clean
                          ? 0
                          : opacity.clamp(0.25, 0.45).toDouble(),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    if (style == ScheduleBackgroundStyle.clean)
                      Center(
                        child: Icon(
                          Icons.layers_clear_outlined,
                          size: 22,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    if (selected)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check_rounded,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              style.label,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
