import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/settings/app_preferences_controller.dart';
import '../../../../app/settings/schedule_timing_preference.dart';
import '../../../../app/theme/design_tokens.dart';
import '../../../../shared/widgets/page_section.dart';
import '../widgets/settings_widgets.dart';

/// 「课表 → 具体时间设置」。
///
/// 用户填好上下午晚上各自的「起始时间 + 节数」，配合三个全局参数
/// （节长 / 默认课间 / 大课间），自动算出每节起讫。
/// 任何一节后面的间隔都可以点击切换"短/大"，或长按设置自定义分钟。
class SettingsScheduleTimingPage extends ConsumerWidget {
  const SettingsScheduleTimingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(appPreferencesControllerProvider);
    final timing = preferences.scheduleTiming;
    final controller = ref.read(appPreferencesControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('具体时间设置'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.pageBottomGap),
        children: [
          PageSection(
            title: '总开关',
            children: [
              SettingSwitchTile(
                icon: Icons.access_time_outlined,
                title: '启用具体时间',
                subtitle: '开启后课表与 ICS 导出都会用下面的时间',
                value: timing.enabled,
                onChanged: (v) => controller
                    .setScheduleTiming(timing.copyWith(enabled: v)),
              ),
            ],
          ),
          PageSection(
            title: '全局参数',
            children: [
              _NumberRow(
                label: '一节课',
                suffix: '分钟',
                value: timing.lessonMinutes,
                min: 30,
                max: 60,
                onChanged: (v) => controller
                    .setScheduleTiming(timing.copyWith(lessonMinutes: v)),
              ),
              _NumberRow(
                label: '默认课间',
                suffix: '分钟',
                value: timing.shortBreakMinutes,
                min: 0,
                max: 30,
                onChanged: (v) => controller.setScheduleTiming(
                  timing.copyWith(shortBreakMinutes: v),
                ),
              ),
              _NumberRow(
                label: '大课间',
                suffix: '分钟',
                value: timing.longBreakMinutes,
                min: 5,
                max: 60,
                onChanged: (v) => controller.setScheduleTiming(
                  timing.copyWith(longBreakMinutes: v),
                ),
              ),
            ],
          ),
          _BlockSection(
            title: '上午',
            block: timing.morning,
            timing: timing,
            onChanged: (b) =>
                controller.setScheduleTiming(timing.copyWith(morning: b)),
            sectionStartIndex: 1,
          ),
          _BlockSection(
            title: '下午',
            block: timing.afternoon,
            timing: timing,
            onChanged: (b) =>
                controller.setScheduleTiming(timing.copyWith(afternoon: b)),
            sectionStartIndex: 1 + timing.morning.sessionCount,
          ),
          _BlockSection(
            title: '晚上',
            block: timing.evening,
            timing: timing,
            onChanged: (b) =>
                controller.setScheduleTiming(timing.copyWith(evening: b)),
            sectionStartIndex: 1 +
                timing.morning.sessionCount +
                timing.afternoon.sessionCount,
          ),
        ],
      ),
    );
  }
}

/// 一行：左侧名字，右侧 [-] 数字 [+]。
class _NumberRow extends StatelessWidget {
  const _NumberRow({
    required this.label,
    required this.suffix,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final String suffix;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

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
          _StepperPill(
            value: value,
            min: min,
            max: max,
            suffix: suffix,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _StepperPill extends StatelessWidget {
  const _StepperPill({
    required this.value,
    required this.min,
    required this.max,
    required this.suffix,
    required this.onChanged,
  });

  final int value;
  final int min;
  final int max;
  final String suffix;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: value > min ? () => onChanged(value - 1) : null,
            icon: const Icon(Icons.remove_rounded, size: 18),
          ),
          SizedBox(
            width: 56,
            child: Text(
              '$value $suffix',
              textAlign: TextAlign.center,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: value < max ? () => onChanged(value + 1) : null,
            icon: const Icon(Icons.add_rounded, size: 18),
          ),
        ],
      ),
    );
  }
}

/// 一个时段块（上午/下午/晚上）的设置 + 节次预览。
class _BlockSection extends StatelessWidget {
  const _BlockSection({
    required this.title,
    required this.block,
    required this.timing,
    required this.onChanged,
    required this.sectionStartIndex,
  });

  final String title;
  final TimingBlock block;
  final ScheduleTimingPreference timing;
  final ValueChanged<TimingBlock> onChanged;
  final int sectionStartIndex;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // 算出本块每节起讫
    final allSections = timing.resolveSectionTimes();
    final visible = <(int, ({String start, String end}))>[];
    for (var i = 0; i < block.sessionCount; i++) {
      final no = sectionStartIndex + i;
      final pair = allSections[no];
      if (pair != null) visible.add((no, pair));
    }

    return PageSection(
      title: title,
      divider: false,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: _StartTimeRow(
                  current: block.start,
                  onChanged: (v) =>
                      onChanged(block.copyWith(start: v)),
                ),
              ),
              const SizedBox(width: 12),
              _StepperPill(
                value: block.sessionCount,
                min: 0,
                max: 10,
                suffix: '节',
                onChanged: (v) =>
                    onChanged(block.trimmedToCount(v)),
              ),
            ],
          ),
        ),
        if (visible.isNotEmpty) ...[
          const SizedBox(height: 4),
          for (var i = 0; i < visible.length; i++) ...[
            _SessionPreviewRow(
              sectionNo: visible[i].$1,
              start: visible[i].$2.start,
              end: visible[i].$2.end,
            ),
            if (i < visible.length - 1)
              _GapRow(
                gapIndex: i,
                block: block,
                timing: timing,
                onChanged: onChanged,
              ),
          ],
        ] else
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 8),
            child: Text(
              '当前节数为 0，没有需要展示的时间。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

class _StartTimeRow extends StatelessWidget {
  const _StartTimeRow({required this.current, required this.onChanged});

  final String current;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => _pick(context),
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Row(
          children: [
            Icon(Icons.schedule_rounded, size: 18, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Text(
              '起始 $current',
              style: theme.textTheme.bodyLarge?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pick(BuildContext context) async {
    final parts = current.split(':');
    final initial = TimeOfDay(
      hour: int.tryParse(parts.first) ?? 8,
      minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
    );
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return;
    onChanged(
      '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}',
    );
  }
}

class _SessionPreviewRow extends StatelessWidget {
  const _SessionPreviewRow({
    required this.sectionNo,
    required this.start,
    required this.end,
  });

  final int sectionNo;
  final String start;
  final String end;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text(
              '第$sectionNo节',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            start,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 6),
          Icon(Icons.arrow_forward_rounded, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            end,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _GapRow extends StatelessWidget {
  const _GapRow({
    required this.gapIndex,
    required this.block,
    required this.timing,
    required this.onChanged,
  });

  final int gapIndex;
  final TimingBlock block;
  final ScheduleTimingPreference timing;
  final ValueChanged<TimingBlock> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLong = block.longBreakAt.contains(gapIndex);
    final custom = block.customGap[gapIndex];
    final minutes = block.gapMinutesAt(
      gapIndex,
      shortBreakMinutes: timing.shortBreakMinutes,
      longBreakMinutes: timing.longBreakMinutes,
    );
    final label = custom != null
        ? '自定义 $custom 分钟'
        : isLong
            ? '大课间 $minutes 分钟'
            : '课间 $minutes 分钟';

    return Padding(
      padding: const EdgeInsets.fromLTRB(36, 4, 0, 4),
      child: Row(
        children: [
          ActionChip(
            avatar: Icon(
              isLong || custom != null
                  ? Icons.timelapse_rounded
                  : Icons.coffee_outlined,
              size: 14,
              color: theme.colorScheme.primary,
            ),
            label: Text(label),
            onPressed: () => onChanged(block.toggleLongBreak(gapIndex)),
          ),
          const SizedBox(width: 8),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: '自定义分钟',
            icon: const Icon(Icons.tune_rounded, size: 18),
            onPressed: () => _editCustom(context, theme, custom),
          ),
        ],
      ),
    );
  }

  Future<void> _editCustom(
    BuildContext context,
    ThemeData theme,
    int? current,
  ) async {
    final controller = TextEditingController(
      text: current?.toString() ?? '',
    );
    final result = await showDialog<int?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('自定义课间'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '分钟（留空则恢复默认）',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final raw = controller.text.trim();
              if (raw.isEmpty) {
                Navigator.of(ctx).pop(-1); // 用 -1 当 sentinel: 清除
              } else {
                final v = int.tryParse(raw);
                if (v == null || v < 0) {
                  Navigator.of(ctx).pop();
                } else {
                  Navigator.of(ctx).pop(v);
                }
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (result == null) return;
    if (result == -1) {
      onChanged(block.setCustomGap(gapIndex, null));
    } else {
      onChanged(block.setCustomGap(gapIndex, result));
    }
  }
}
