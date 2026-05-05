import 'package:flutter/material.dart';
import 'package:flutter_auto_size_text/flutter_auto_size_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../app/settings/app_preferences_controller.dart';
import '../../../../shared/widgets/app_snackbar.dart';
import '../../../../shared/widgets/async_value_view.dart';
import '../../../../shared/widgets/schedule_background.dart';
import '../../domain/entities/schedule_snapshot.dart';
import '../controllers/schedule_controller.dart';

enum _ScheduleViewMode { week, today }

class SchedulePage extends ConsumerStatefulWidget {
  const SchedulePage({super.key});

  @override
  ConsumerState<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends ConsumerState<SchedulePage> {
  _ScheduleViewMode _viewMode = _ScheduleViewMode.week;
  bool _showAllWeeks = false;
  int? _selectedWeek;

  int _effectiveWeek(ScheduleSnapshot snapshot) {
    final preferences = ref.read(appPreferencesControllerProvider);
    final candidate =
        _selectedWeek ??
        preferences.computedScheduleWeek ??
        snapshot.displayWeek;
    if (candidate < 1) {
      return 1;
    }
    if (candidate > snapshot.maxWeek) {
      return snapshot.maxWeek;
    }
    return candidate;
  }

  String _weekFilterLabel(ScheduleSnapshot snapshot) {
    if (_showAllWeeks) {
      return '全部周';
    }
    return '第 ${_effectiveWeek(snapshot)} 周';
  }

  @override
  Widget build(BuildContext context) {
    final scheduleAsync = ref.watch(scheduleControllerProvider);
    final preferences = ref.watch(appPreferencesControllerProvider);

    return AsyncValueView(
      value: scheduleAsync,
      onRetry: () => ref.read(scheduleControllerProvider.notifier).refresh(),
      loadingLabel: '课表同步中',
      dataBuilder: (snapshot) {
        final todayWeekday = DateTime.now().weekday;
        final effectiveWeek = _effectiveWeek(snapshot);
        final weekFilterLabel = _weekFilterLabel(snapshot);
        final filteredEntries = snapshot.entriesForWeek(
          week: effectiveWeek,
          showAllWeeks: _showAllWeeks,
        );
        final todayEntries = snapshot.sessionsForDay(
          todayWeekday,
          week: effectiveWeek,
          showAllWeeks: _showAllWeeks,
        );

        return Stack(
          children: [
            Positioned.fill(
              child: ScheduleBackground(
                style: preferences.scheduleBackgroundStyle,
                opacity: preferences.scheduleBackgroundOpacity,
              ),
            ),
            Column(
              children: [
                if (snapshot.loadError != null)
                  _ScheduleErrorBanner(
                    message: snapshot.loadError!,
                    onRetry: () =>
                        ref.read(scheduleControllerProvider.notifier).refresh(),
                  ),
                _ScheduleTopBar(
                  snapshot: snapshot,
                  weekLabel: weekFilterLabel,
                  onSwitchTerm: () => _showTermPicker(snapshot),
                  onSelectWeek: () => _showWeekPicker(snapshot),
                  viewMode: _viewMode,
                  onToggleViewMode: () {
                    setState(() {
                      _viewMode = _viewMode == _ScheduleViewMode.week
                          ? _ScheduleViewMode.today
                          : _ScheduleViewMode.week;
                    });
                  },
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () =>
                        ref.read(scheduleControllerProvider.notifier).refresh(),
                    child: _viewMode == _ScheduleViewMode.week
                        ? LayoutBuilder(
                            builder: (context, constraints) {
                              final viewportHeight =
                                  constraints.hasBoundedHeight
                                  ? constraints.maxHeight
                                  : MediaQuery.sizeOf(context).height * 0.72;
                              final contentHeight = viewportHeight > 20
                                  ? viewportHeight - 20
                                  : viewportHeight;

                              return CustomScrollView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                slivers: [
                                  SliverPadding(
                                    padding: const EdgeInsets.fromLTRB(
                                      12,
                                      8,
                                      12,
                                      12,
                                    ),
                                    sliver: SliverToBoxAdapter(
                                      child: SizedBox(
                                        height: contentHeight,
                                        child: _WeekTimetable(
                                          entries: filteredEntries,
                                          showAllWeeks: _showAllWeeks,
                                          showWeekends:
                                              preferences.showWeekends,
                                          onOpenDetail: (entry) =>
                                              _openCourseDetail(
                                                snapshot,
                                                entry,
                                              ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          )
                        : ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                            children: [
                              _TodayHeader(
                                weekLabel: weekFilterLabel,
                                entries: todayEntries,
                                todayWeekday: todayWeekday,
                              ),
                              const SizedBox(height: 16),
                              if (todayEntries.isEmpty)
                                const _EmptyTodayState()
                              else
                                ...todayEntries.map(
                                  (entry) => Padding(
                                    padding: const EdgeInsets.only(bottom: 14),
                                    child: _CourseTile(
                                      entry: entry,
                                      colorSeed: todayWeekday,
                                      onTap: () =>
                                          _openCourseDetail(snapshot, entry),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Future<void> _showTermPicker(ScheduleSnapshot snapshot) async {
    final selectedTermId = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '切换学期',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  '从学期列表中选择要查看的课程表。',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF607172),
                  ),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: snapshot.availableTerms.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final term = snapshot.availableTerms[index];
                      final isSelected = term.id == snapshot.term.id;
                      return Material(
                        color: isSelected
                            ? Theme.of(context).colorScheme.primaryContainer
                            : Theme.of(context).colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(20),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () => Navigator.of(context).pop(term.id),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    term.name,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          fontWeight: isSelected
                                              ? FontWeight.w700
                                              : FontWeight.w600,
                                        ),
                                  ),
                                ),
                                if (isSelected)
                                  Icon(
                                    Icons.check_circle,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  )
                                else
                                  const Icon(Icons.chevron_right_rounded),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted ||
        selectedTermId == null ||
        selectedTermId == snapshot.term.id) {
      return;
    }

    final success = await ref
        .read(scheduleControllerProvider.notifier)
        .changeTerm(selectedTermId);
    if (!mounted) {
      return;
    }
    if (!success) {
      AppSnackBar.show(
        context,
        message: '该学期课表加载失败，已恢复到之前的学期',
        tone: AppSnackBarTone.error,
      );
      return;
    }
    setState(() {
      _showAllWeeks = false;
      _selectedWeek = null;
    });
  }

  Future<void> _showWeekPicker(ScheduleSnapshot snapshot) async {
    final selectedWeek = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) {
        final activeWeek = _effectiveWeek(snapshot);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '切换周次',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  '可以查看指定周，也可以直接显示全部周课程。',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF607172),
                  ),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: snapshot.maxWeek + 1,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final isAllWeeks = index == 0;
                      final week = isAllWeeks ? 0 : index;
                      final isSelected = isAllWeeks
                          ? _showAllWeeks
                          : !_showAllWeeks && week == activeWeek;
                      final label = isAllWeeks ? '全部周' : '第 $week 周';
                      return Material(
                        color: isSelected
                            ? Theme.of(context).colorScheme.primaryContainer
                            : Theme.of(context).colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(20),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () => Navigator.of(context).pop(week),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    label,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          fontWeight: isSelected
                                              ? FontWeight.w700
                                              : FontWeight.w600,
                                        ),
                                  ),
                                ),
                                if (isSelected)
                                  Icon(
                                    Icons.check_circle,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  )
                                else
                                  const Icon(Icons.chevron_right_rounded),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || selectedWeek == null) {
      return;
    }

    setState(() {
      if (selectedWeek == 0) {
        _showAllWeeks = true;
        _selectedWeek = null;
      } else {
        _showAllWeeks = false;
        _selectedWeek = selectedWeek;
        ref
            .read(appPreferencesControllerProvider.notifier)
            .setScheduleWeek(selectedWeek);
      }
    });
  }

  Future<void> _openCourseDetail(
    ScheduleSnapshot snapshot,
    ScheduleEntry entry,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) =>
          _CourseDetailSheet(snapshot: snapshot, entry: entry),
    );
  }
}

class _ScheduleErrorBanner extends StatelessWidget {
  const _ScheduleErrorBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: colorScheme.errorContainer,
      child: Row(
        children: [
          Icon(
            Icons.sync_problem_rounded,
            size: 18,
            color: colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onErrorContainer,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              foregroundColor: colorScheme.onErrorContainer,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }
}

class _ScheduleTopBar extends StatelessWidget {
  const _ScheduleTopBar({
    required this.snapshot,
    required this.weekLabel,
    required this.onSwitchTerm,
    required this.onSelectWeek,
    required this.viewMode,
    required this.onToggleViewMode,
  });

  final ScheduleSnapshot snapshot;
  final String weekLabel;
  final VoidCallback onSwitchTerm;
  final VoidCallback onSelectWeek;
  final _ScheduleViewMode viewMode;
  final VoidCallback onToggleViewMode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onSelectWeek,
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                weekLabel,
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  color: const Color(0xFF213A3C),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                snapshot.term.name,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: const Color(0xFF5A6B6D),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.expand_more_rounded,
                          color: Color(0xFF5A6B6D),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            _TopActionButton(
              icon: Icons.swap_horiz_rounded,
              tooltip: '切换学期',
              onTap: onSwitchTerm,
            ),
            const SizedBox(width: 8),
            _TopActionButton(
              icon: viewMode == _ScheduleViewMode.week
                  ? Icons.today_rounded
                  : Icons.view_week_rounded,
              tooltip: viewMode == _ScheduleViewMode.week
                  ? '切换到今日视图'
                  : '切换到整周视图',
              onTap: onToggleViewMode,
            ),
          ],
        ),
      ),
    );
  }
}

class _TopActionButton extends StatelessWidget {
  const _TopActionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            width: 46,
            height: 46,
            child: Icon(icon, size: 22, color: const Color(0xFF274245)),
          ),
        ),
      ),
    );
  }
}

class _WeekTimetable extends StatelessWidget {
  const _WeekTimetable({
    required this.entries,
    required this.showAllWeeks,
    required this.showWeekends,
    required this.onOpenDetail,
  });

  final List<ScheduleEntry> entries;
  final bool showAllWeeks;
  final bool showWeekends;
  final ValueChanged<ScheduleEntry> onOpenDetail;

  @override
  Widget build(BuildContext context) {
    final visibleDays = showWeekends
        ? const [1, 2, 3, 4, 5, 6, 7]
        : const [1, 2, 3, 4, 5];
    final filteredEntries = entries
        .where((entry) => visibleDays.contains(entry.session.dayOfWeek))
        .toList();
    final model = _WeekBoardModel.fromEntries(
      filteredEntries,
      preferLongestAtSameStart: showAllWeeks,
    );
    if (model.placements.isEmpty) {
      return const _EmptyWeekState();
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final todayWeekday = DateTime.now().weekday;
    final highlightToday = true;
    final dayCount = visibleDays.length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportHeight = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : MediaQuery.sizeOf(context).height * 0.68;
        final compactHeight = viewportHeight < 620;
        final sideWidth = compactHeight ? 36.0 : 42.0;
        final gap = compactHeight ? 2.0 : 3.0;
        final headerHeight = compactHeight ? 34.0 : 40.0;
        final minDayWidth = compactHeight ? 48.0 : 52.0;
        final availableWidth = constraints.maxWidth;
        final columnGaps = dayCount - 1;
        final computedDayWidth =
            (availableWidth - sideWidth - gap * columnGaps) / dayCount;
        final dayWidth = computedDayWidth > minDayWidth
            ? computedDayWidth
            : minDayWidth;
        final boardWidth = sideWidth + dayWidth * dayCount + gap * columnGaps;
        final needsScroll = boardWidth > availableWidth;
        final hintBlockHeight = needsScroll
            ? (compactHeight ? 22.0 : 26.0)
            : 0.0;
        final availableBodyHeight =
            (viewportHeight - headerHeight - hintBlockHeight).clamp(
              0.0,
              double.infinity,
            );
        final rawRowHeight =
            (availableBodyHeight - (model.slotCount - 1) * gap) /
            model.slotCount;
        final preferredMinRowHeight = compactHeight ? 18.0 : 20.0;
        final rowHeight = rawRowHeight < preferredMinRowHeight
            ? rawRowHeight.clamp(0.0, 64.0).toDouble()
            : rawRowHeight.clamp(preferredMinRowHeight, 64.0).toDouble();
        final bodyHeight =
            model.slotCount * rowHeight + (model.slotCount - 1) * gap;
        final dayOffsets = <int, double>{
          for (var index = 0; index < visibleDays.length; index++)
            visibleDays[index]: sideWidth + index * (dayWidth + gap),
        };

        return Container(
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.76),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (needsScroll)
                SizedBox(
                  height: hintBlockHeight,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Row(
                        children: [
                          Icon(
                            Icons.swipe_rounded,
                            size: compactHeight ? 13 : 14,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          SizedBox(width: compactHeight ? 3 : 4),
                          Text(
                            '左右滑动查看完整课表',
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontSize: compactHeight ? 10 : null,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: boardWidth,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Day header row
                      SizedBox(
                        height: headerHeight,
                        child: Row(
                          children: [
                            Container(
                              width: sideWidth,
                              height: headerHeight,
                              color: colorScheme.surfaceContainerLow.withValues(
                                alpha: 0.5,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                '节',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            for (
                              var index = 0;
                              index < visibleDays.length;
                              index++
                            ) ...[
                              if (index != 0) SizedBox(width: gap),
                              _WeekdayHeaderCell(
                                width: dayWidth,
                                label: _weekdayShort(visibleDays[index]),
                                count: model.countForDay(visibleDays[index]),
                                isToday:
                                    highlightToday &&
                                    visibleDays[index] == todayWeekday,
                              ),
                            ],
                          ],
                        ),
                      ),
                      // Grid body
                      SizedBox(
                        height: bodyHeight,
                        child: Stack(
                          children: [
                            // Time axis
                            for (var si = 0; si < model.slots.length; si++)
                              Positioned(
                                left: 0,
                                top: si * (rowHeight + gap),
                                child: _SectionLabel(
                                  width: sideWidth,
                                  height: rowHeight,
                                  text: model.slots[si].primaryLabel,
                                ),
                              ),
                            // Background cells
                            for (var si = 0; si < model.slots.length; si++)
                              for (final day in visibleDays)
                                Positioned(
                                  left: dayOffsets[day]!,
                                  top: si * (rowHeight + gap),
                                  child: _EmptyCell(
                                    width: dayWidth,
                                    height: rowHeight,
                                    isToday:
                                        highlightToday && day == todayWeekday,
                                  ),
                                ),
                            // Course cards
                            for (final p in model.placements)
                              Positioned(
                                left:
                                    dayOffsets[p.dayOfWeek]! +
                                    1.5 +
                                    p.laneIndex *
                                        (((dayWidth - 3) -
                                                    (p.laneCount - 1) * 2) /
                                                p.laneCount +
                                            2),
                                top: p.startSlotIndex * (rowHeight + gap) + 1.5,
                                width:
                                    (((dayWidth - 3) - (p.laneCount - 1) * 2) /
                                            p.laneCount)
                                        .clamp(0.0, dayWidth - 3)
                                        .toDouble(),
                                height:
                                    (p.slotSpan * rowHeight +
                                            (p.slotSpan - 1) * gap -
                                            3)
                                        .clamp(0.0, double.infinity)
                                        .toDouble(),
                                child: _WeekCourseCard(
                                  entries: p.entries,
                                  accent: p.accent,
                                  onTap: () => onOpenDetail(p.entry),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _WeekdayHeaderCell extends StatelessWidget {
  const _WeekdayHeaderCell({
    required this.width,
    required this.label,
    required this.count,
    required this.isToday,
  });

  final double width;
  final String label;
  final int count;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: isToday
            ? colorScheme.primary.withValues(alpha: 0.12)
            : colorScheme.surfaceContainerLow.withValues(alpha: 0.44),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w800,
          color: isToday ? colorScheme.primary : colorScheme.onSurface,
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.width,
    required this.height,
    required this.text,
  });

  final double width;
  final double height;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      color: Theme.of(
        context,
      ).colorScheme.surfaceContainerLow.withValues(alpha: 0.46),
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            text,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            maxLines: 1,
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

class _EmptyCell extends StatelessWidget {
  const _EmptyCell({
    required this.width,
    required this.height,
    required this.isToday,
  });

  final double width;
  final double height;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: width,
      height: height,
      color: isToday
          ? colorScheme.primary.withValues(alpha: 0.06)
          : colorScheme.surfaceContainerLow.withValues(alpha: 0.12),
    );
  }
}

class _WeekCourseCard extends StatelessWidget {
  const _WeekCourseCard({
    required this.entries,
    required this.accent,
    required this.onTap,
  });

  final List<ScheduleEntry> entries;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Color.lerp(Colors.white, accent, 0.16)!.withValues(alpha: 0.82),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: accent.withValues(alpha: 0.22)),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final textTheme = Theme.of(context).textTheme;
              final compact =
                  constraints.maxHeight < 42 || constraints.maxWidth < 70;
              final displayText = _weekCardDisplayText(
                entries,
                textTheme,
                compact: compact,
              );

              return Padding(
                padding: EdgeInsets.all(compact ? 4 : 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 3,
                      height: constraints.maxHeight - (compact ? 8 : 10),
                      margin: EdgeInsets.only(right: compact ? 4 : 5),
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: AutoSizeText.rich(
                          displayText,
                          minFontSize: compact ? 8.5 : 9,
                          maxFontSize: compact ? 12.5 : 13.5,
                          stepGranularity: 0.5,
                          maxLines: 6,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.labelSmall?.copyWith(
                            fontSize: compact ? 10.5 : 11,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF1F3436),
                            height: compact ? 1.16 : 1.18,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

TextSpan _weekCardDisplayText(
  List<ScheduleEntry> entries,
  TextTheme textTheme, {
  required bool compact,
}) {
  final representative = entries.first;
  final teachers = _displayTeachers(entries);
  final locations = _displayLocations(entries);
  final secondaryLines = <String>[
    if (teachers.isNotEmpty) teachers.join('、'),
    if (locations.isNotEmpty) locations.length == 1 ? locations.first : '多个教室',
  ];

  return TextSpan(
    children: [
      TextSpan(
        text: representative.course.name.trim(),
        style: textTheme.labelMedium?.copyWith(
          fontSize: compact ? 12.6 : 13.2,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF1F3436),
          height: compact ? 1.12 : 1.14,
        ),
      ),
      if (secondaryLines.isNotEmpty)
        TextSpan(
          text: '\n${secondaryLines.join('\n')}',
          style: textTheme.labelSmall?.copyWith(
            fontSize: compact ? 9.6 : 10.1,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF42595B),
            height: compact ? 1.14 : 1.18,
          ),
        ),
    ],
  );
}

List<ScheduleEntry> _sortedScheduleEntries(Iterable<ScheduleEntry> entries) {
  final items = entries.toList()
    ..sort((left, right) {
      final byWeekStart = left.session.weekRange.startWeek.compareTo(
        right.session.weekRange.startWeek,
      );
      if (byWeekStart != 0) {
        return byWeekStart;
      }
      final byWeekEnd = left.session.weekRange.endWeek.compareTo(
        right.session.weekRange.endWeek,
      );
      if (byWeekEnd != 0) {
        return byWeekEnd;
      }
      return _displayTeacher(left).compareTo(_displayTeacher(right));
    });
  return items;
}

String _weekBoardGroupingKey(
  ScheduleEntry entry, {
  required bool mergeByStartOnly,
}) {
  final identity = entry.course.courseCode?.trim().isNotEmpty == true
      ? entry.course.courseCode!.trim()
      : entry.course.name.trim();
  return [
    identity,
    entry.session.dayOfWeek,
    entry.session.startSection ?? -1,
    entry.session.startTime.trim(),
    if (!mergeByStartOnly) entry.session.endSection ?? -1,
    if (!mergeByStartOnly) entry.session.endTime.trim(),
  ].join('|');
}

int _entryDurationScore(ScheduleEntry entry) {
  final startSection = entry.session.startSection;
  final endSection = entry.session.endSection;
  if (startSection != null && endSection != null) {
    return endSection - startSection + 1;
  }

  final startMinutes = _timeLabelToMinutes(entry.session.startTime);
  final endMinutes = _timeLabelToMinutes(entry.session.endTime);
  if (startMinutes != null &&
      endMinutes != null &&
      endMinutes >= startMinutes) {
    return endMinutes - startMinutes;
  }

  return 1;
}

int? _timeLabelToMinutes(String raw) {
  final match = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(raw);
  if (match == null) {
    return null;
  }
  return int.parse(match.group(1)!) * 60 + int.parse(match.group(2)!);
}

ScheduleEntry _placementRepresentative(Iterable<ScheduleEntry> entries) {
  final items = entries.toList()
    ..sort((left, right) {
      final byDuration = _entryDurationScore(
        right,
      ).compareTo(_entryDurationScore(left));
      if (byDuration != 0) {
        return byDuration;
      }
      final byWeekStart = left.session.weekRange.startWeek.compareTo(
        right.session.weekRange.startWeek,
      );
      if (byWeekStart != 0) {
        return byWeekStart;
      }
      return left.session.weekRange.endWeek.compareTo(
        right.session.weekRange.endWeek,
      );
    });
  return items.first;
}

String _displayTeacher(ScheduleEntry entry) {
  final sessionTeacher = entry.session.teacher.trim();
  if (sessionTeacher.isNotEmpty && sessionTeacher != '-') {
    return sessionTeacher;
  }
  final courseTeacher = entry.course.teacher.trim();
  if (courseTeacher.isNotEmpty && courseTeacher != '-') {
    return courseTeacher;
  }
  return '';
}

List<String> _displayTeachers(Iterable<ScheduleEntry> entries) {
  final seen = <String>{};
  final values = <String>[];
  for (final entry in entries) {
    final teacher = _displayTeacher(entry);
    if (teacher.isEmpty || !seen.add(teacher)) {
      continue;
    }
    values.add(teacher);
  }
  return values;
}

List<String> _displayLocations(Iterable<ScheduleEntry> entries) {
  final seen = <String>{};
  final values = <String>[];
  for (final entry in entries) {
    final location = entry.session.location.fullName.trim();
    if (location.isEmpty || location == '地点待定' || !seen.add(location)) {
      continue;
    }
    values.add(location);
  }
  return values;
}

List<ScheduleEntry> _relatedScheduleEntries(
  ScheduleSnapshot snapshot,
  ScheduleEntry entry,
) {
  final key = _weekBoardGroupingKey(entry, mergeByStartOnly: true);
  return _sortedScheduleEntries(
    snapshot.entries.where(
      (candidate) =>
          _weekBoardGroupingKey(candidate, mergeByStartOnly: true) == key,
    ),
  );
}

String _scheduleArrangementText(List<ScheduleEntry> entries) {
  final blocks = <String>[];
  for (final entry in _sortedScheduleEntries(entries)) {
    final lines = <String>[
      entry.session.weekLabel,
      if (_displayTeacher(entry).isNotEmpty) _displayTeacher(entry),
      if (entry.session.location.fullName != '地点待定')
        entry.session.location.fullName,
    ];
    blocks.add(lines.join('\n'));
  }
  return blocks.join('\n\n');
}

class _EmptyWeekState extends StatelessWidget {
  const _EmptyWeekState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 26),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.76),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: const Color(0xFF0F6A71).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.grid_view_rounded,
              color: Color(0xFF0F6A71),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '这一周没有可展示的课程',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            '当前学期没有有效周课表数据，可以切到“今日”模式或重新同步。',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF607172)),
          ),
        ],
      ),
    );
  }
}

class _WeekBoardModel {
  const _WeekBoardModel({required this.slots, required this.placements});

  final List<_WeekBoardSlot> slots;
  final List<_WeekBoardPlacement> placements;

  int get slotCount => slots.length;

  int countForDay(int dayOfWeek) {
    return placements.where((item) => item.dayOfWeek == dayOfWeek).length;
  }

  factory _WeekBoardModel.fromEntries(
    List<ScheduleEntry> entries, {
    bool preferLongestAtSameStart = false,
  }) {
    if (entries.isEmpty) {
      return const _WeekBoardModel(slots: [], placements: []);
    }

    final placements = <_WeekBoardPlacement>[];
    final slots = <_WeekBoardSlot>[];
    final groupedEntries = <String, List<ScheduleEntry>>{};
    for (final entry in entries) {
      groupedEntries
          .putIfAbsent(
            _weekBoardGroupingKey(
              entry,
              mergeByStartOnly: preferLongestAtSameStart,
            ),
            () => [],
          )
          .add(entry);
    }

    final mergedEntries = groupedEntries.values
        .map((group) => _sortedScheduleEntries(group))
        .toList();

    final sectionEntries = mergedEntries
        .where(
          (group) =>
              group.first.session.startSection != null &&
              group.first.session.endSection != null,
        )
        .toList();

    if (sectionEntries.isNotEmpty) {
      final maxSection = sectionEntries
          .map((group) => _placementRepresentative(group).session.endSection!)
          .reduce((left, right) => left > right ? left : right);
      for (var section = 1; section <= maxSection; section++) {
        slots.add(
          _WeekBoardSlot(
            primaryLabel: section.toString().padLeft(2, '0'),
            secondaryLabel: '第$section节',
          ),
        );
      }

      for (final group in sectionEntries) {
        final entry = _placementRepresentative(group);
        placements.add(
          _WeekBoardPlacement(
            entries: group,
            dayOfWeek: entry.session.dayOfWeek,
            startSlotIndex: entry.session.startSection! - 1,
            slotSpan:
                entry.session.endSection! - entry.session.startSection! + 1,
            accent: _accentForIndex(_courseColorSeed(entry)),
          ),
        );
      }
    }

    final flexibleEntries = mergedEntries
        .where(
          (group) =>
              group.first.session.startSection == null ||
              group.first.session.endSection == null,
        )
        .toList();
    if (flexibleEntries.isNotEmpty) {
      final orderedLabels =
          flexibleEntries
              .map(
                (group) =>
                    '${group.first.session.startTime}|${group.first.session.endTime}',
              )
              .toSet()
              .toList()
            ..sort((left, right) => _compareTimeKeys(left, right));
      final baseIndex = slots.length;
      for (final label in orderedLabels) {
        final parts = label.split('|');
        slots.add(
          _WeekBoardSlot(
            primaryLabel: parts.first,
            secondaryLabel: parts.length > 1 ? parts.last : '',
          ),
        );
      }
      for (final entry in flexibleEntries) {
        final representative = _placementRepresentative(entry);
        final key =
            '${representative.session.startTime}|${representative.session.endTime}';
        final slotIndex = orderedLabels.indexOf(key);
        if (slotIndex == -1) {
          continue;
        }
        placements.add(
          _WeekBoardPlacement(
            entries: entry,
            dayOfWeek: representative.session.dayOfWeek,
            startSlotIndex: baseIndex + slotIndex,
            slotSpan: 1,
            accent: _accentForIndex(_courseColorSeed(representative)),
          ),
        );
      }
    }

    return _WeekBoardModel(
      slots: slots,
      placements: _resolvePlacementLanes(placements),
    );
  }
}

class _WeekBoardSlot {
  const _WeekBoardSlot({
    required this.primaryLabel,
    required this.secondaryLabel,
  });

  final String primaryLabel;
  final String secondaryLabel;
}

class _WeekBoardPlacement {
  const _WeekBoardPlacement({
    required this.entries,
    required this.dayOfWeek,
    required this.startSlotIndex,
    required this.slotSpan,
    required this.accent,
    this.laneIndex = 0,
    this.laneCount = 1,
  });

  final List<ScheduleEntry> entries;
  final int dayOfWeek;
  final int startSlotIndex;
  final int slotSpan;
  final Color accent;
  final int laneIndex;
  final int laneCount;

  ScheduleEntry get entry => _placementRepresentative(entries);

  int get endSlotIndexExclusive => startSlotIndex + slotSpan;

  _WeekBoardPlacement copyWith({int? laneIndex, int? laneCount}) {
    return _WeekBoardPlacement(
      entries: entries,
      dayOfWeek: dayOfWeek,
      startSlotIndex: startSlotIndex,
      slotSpan: slotSpan,
      accent: accent,
      laneIndex: laneIndex ?? this.laneIndex,
      laneCount: laneCount ?? this.laneCount,
    );
  }
}

List<_WeekBoardPlacement> _resolvePlacementLanes(
  List<_WeekBoardPlacement> placements,
) {
  if (placements.isEmpty) {
    return const [];
  }

  final resolved = <_WeekBoardPlacement>[];
  final byDay = <int, List<_WeekBoardPlacement>>{};
  for (final placement in placements) {
    byDay.putIfAbsent(placement.dayOfWeek, () => []).add(placement);
  }

  final sortedDays = byDay.keys.toList()..sort();
  for (final day in sortedDays) {
    final dayPlacements = byDay[day]!
      ..sort((left, right) {
        final byStart = left.startSlotIndex.compareTo(right.startSlotIndex);
        if (byStart != 0) {
          return byStart;
        }
        final bySpan = right.slotSpan.compareTo(left.slotSpan);
        if (bySpan != 0) {
          return bySpan;
        }
        return left.entry.course.name.compareTo(right.entry.course.name);
      });

    final active = <_ResolvedPlacementLane>[];
    final cluster = <_ResolvedPlacementLane>[];
    var clusterLaneCount = 1;

    void flushCluster() {
      if (cluster.isEmpty) {
        return;
      }
      for (final item in cluster) {
        resolved.add(
          item.placement.copyWith(
            laneIndex: item.laneIndex,
            laneCount: clusterLaneCount,
          ),
        );
      }
      cluster.clear();
      active.clear();
      clusterLaneCount = 1;
    }

    for (final placement in dayPlacements) {
      active.removeWhere(
        (item) =>
            item.placement.endSlotIndexExclusive <= placement.startSlotIndex,
      );
      if (active.isEmpty) {
        flushCluster();
      }

      final usedLaneIndexes = active.map((item) => item.laneIndex).toSet();
      var laneIndex = 0;
      while (usedLaneIndexes.contains(laneIndex)) {
        laneIndex++;
      }

      final resolvedPlacement = _ResolvedPlacementLane(
        placement: placement,
        laneIndex: laneIndex,
      );
      active.add(resolvedPlacement);
      cluster.add(resolvedPlacement);
      if (laneIndex + 1 > clusterLaneCount) {
        clusterLaneCount = laneIndex + 1;
      }
    }

    flushCluster();
  }

  resolved.sort((left, right) {
    final byDay = left.dayOfWeek.compareTo(right.dayOfWeek);
    if (byDay != 0) {
      return byDay;
    }
    final byStart = left.startSlotIndex.compareTo(right.startSlotIndex);
    if (byStart != 0) {
      return byStart;
    }
    return left.laneIndex.compareTo(right.laneIndex);
  });
  return resolved;
}

class _ResolvedPlacementLane {
  const _ResolvedPlacementLane({
    required this.placement,
    required this.laneIndex,
  });

  final _WeekBoardPlacement placement;
  final int laneIndex;
}

class _CourseTile extends StatelessWidget {
  const _CourseTile({
    required this.entry,
    required this.colorSeed,
    required this.onTap,
  });

  final ScheduleEntry entry;
  final int colorSeed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = _accentForIndex(colorSeed);

    return Material(
      color: const Color(0xFFF9F7F2).withValues(alpha: 0.78),
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: accent.withValues(alpha: 0.18)),
          ),
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 88,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.session.startTime,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: accent,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      entry.session.endTime,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: accent.withValues(alpha: 0.88),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      entry.session.sectionLabel,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: accent.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.course.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF22393A),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _displayTeacher(entry).isEmpty
                          ? '教师待定'
                          : _displayTeacher(entry),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF516667),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _InfoChip(
                          icon: Icons.repeat_rounded,
                          label: entry.session.weekLabel,
                        ),
                        _InfoChip(
                          icon: Icons.location_on_outlined,
                          label: entry.session.location.fullName,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, color: accent),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: const Color(0xFF5B6D6E)),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: const Color(0xFF485A5C)),
            ),
          ],
        ),
      ),
    );
  }
}

class _TodayHeader extends StatelessWidget {
  const _TodayHeader({
    required this.weekLabel,
    required this.entries,
    required this.todayWeekday,
  });

  final String weekLabel;
  final List<ScheduleEntry> entries;
  final int todayWeekday;

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat(
      'M 月 d 日 EEEE',
      'zh_CN',
    ).format(DateTime.now());

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.76),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        child: Row(
          children: [
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                color: _accentForIndex(todayWeekday).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              alignment: Alignment.center,
              child: Text(
                '${DateTime.now().day}',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: _accentForIndex(todayWeekday),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dateLabel,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$weekLabel今天共有 ${entries.length} 节课程',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF5C6E70),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CourseDetailSheet extends StatelessWidget {
  const _CourseDetailSheet({required this.snapshot, required this.entry});

  final ScheduleSnapshot snapshot;
  final ScheduleEntry entry;

  @override
  Widget build(BuildContext context) {
    final relatedEntries = _relatedScheduleEntries(snapshot, entry);
    final hasMultipleArrangements = relatedEntries.length > 1;
    final teachers = _displayTeachers(relatedEntries);
    final teacherLabel = teachers.isEmpty ? '教师待定' : teachers.join('、');

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.course.name,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                snapshot.term.name,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: const Color(0xFF5A6B6D),
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _DetailTag(label: entry.session.weekdayLabel),
                  _DetailTag(label: entry.session.sectionLabel),
                  if (!hasMultipleArrangements)
                    _DetailTag(label: entry.session.weekLabel),
                ],
              ),
              const SizedBox(height: 20),
              if (hasMultipleArrangements) ...[
                _DetailBlock(
                  title: '授课安排',
                  value: _scheduleArrangementText(relatedEntries),
                  icon: Icons.view_timeline_rounded,
                ),
                const SizedBox(height: 12),
              ] else ...[
                _DetailBlock(
                  title: '授课教师',
                  value: teacherLabel,
                  icon: Icons.person_outline_rounded,
                ),
                const SizedBox(height: 12),
                _DetailBlock(
                  title: '上课地点',
                  value: entry.session.location.fullName,
                  icon: Icons.location_on_outlined,
                ),
                const SizedBox(height: 12),
              ],
              if (entry.course.note != null &&
                  entry.course.note!.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                _DetailBlock(
                  title: '备注',
                  value: entry.course.note!,
                  icon: Icons.notes_rounded,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailTag extends StatelessWidget {
  const _DetailTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF4F3EE),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _DetailBlock extends StatelessWidget {
  const _DetailBlock({
    required this.title,
    required this.value,
    required this.icon,
  });

  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8F7F2),
        borderRadius: BorderRadius.circular(24),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF556A6C)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: const Color(0xFF5A6B6D),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
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

class _EmptyTodayState extends StatelessWidget {
  const _EmptyTodayState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.76),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFF0F6A71).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.wb_sunny_outlined,
              color: Color(0xFF0F6A71),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '今天没有课程',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            '可以切换到“整周”查看这一学期的完整周课表。',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF607172)),
          ),
        ],
      ),
    );
  }
}

String _weekdayShort(int dayOfWeek) {
  const labels = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  return labels[dayOfWeek - 1];
}

int _courseColorSeed(ScheduleEntry entry) {
  final seed = entry.course.id.hashCode ^ entry.course.name.hashCode;
  return seed.abs() % 7 + 1;
}

int _compareTimeKeys(String left, String right) {
  final leftPrimary = left.split('|').first;
  final rightPrimary = right.split('|').first;
  final leftTime = _parseMinutes(leftPrimary);
  final rightTime = _parseMinutes(rightPrimary);
  if (leftTime != null && rightTime != null) {
    return leftTime.compareTo(rightTime);
  }
  return left.compareTo(right);
}

int? _parseMinutes(String label) {
  final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(label.trim());
  if (match == null) {
    return null;
  }
  final hour = int.tryParse(match.group(1)!);
  final minute = int.tryParse(match.group(2)!);
  if (hour == null || minute == null) {
    return null;
  }
  return hour * 60 + minute;
}

Color _accentForIndex(int index) {
  const palette = [
    Color(0xFF0F6A71),
    Color(0xFFB97834),
    Color(0xFF5478A6),
    Color(0xFF7C6655),
    Color(0xFF2F8C72),
    Color(0xFF9A5C46),
    Color(0xFF5A64A5),
  ];
  return palette[(index - 1) % palette.length];
}
