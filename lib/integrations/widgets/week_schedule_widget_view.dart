import 'package:flutter/material.dart';

import '../../app/settings/schedule_timing_preference.dart';
import '../../modules/schedule/domain/entities/schedule_snapshot.dart';

/// 整周课表小组件的视图：周日历 × 节次格子，命中课程的格子填充课程的色块。
///
/// 这个 widget 只用于在 home_widget 那里被渲染成 PNG 推到桌面，
/// 不直接在 App 内显示。所以宽高在 [size] 里写死，确保 PNG 不被原生
/// 二次缩放出毛刺；并且会按 [size] 自适应字号 / 间距，避免 cell 过小时
/// 文字溢出。
class WeekScheduleWidgetView extends StatelessWidget {
  const WeekScheduleWidgetView({
    super.key,
    required this.snapshot,
    required this.timing,
    // 默认渲染分辨率 720×480（设备桌面缩放后仍清晰）。
    this.size = const Size(720, 480),
  });

  final ScheduleSnapshot snapshot;
  final ScheduleTimingPreference timing;
  final Size size;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    // 用本周一作为起点，方便把 dayOfWeek 1..7 映射到列。
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final entries = snapshot.entriesForWeek(week: snapshot.displayWeek);

    // 决定要画几节。优先使用 timing 里的总节数，最低 5 节。
    final totalSections = timing.enabled
        ? (timing.morning.sessionCount +
              timing.afternoon.sessionCount +
              timing.evening.sessionCount)
        : 11;
    final sectionCount = totalSections < 5 ? 5 : totalSections;

    // 本周每节课映射到一个色块。
    // key = dayOfWeek (1..7), value = section -> Cell
    final cellGrid = <int, Map<int, _Cell>>{};
    for (final entry in entries) {
      final day = entry.session.dayOfWeek;
      final start = entry.session.startSection;
      final end = entry.session.endSection ?? start;
      if (start == null) continue;
      cellGrid.putIfAbsent(day, () => {});
      for (var s = start; s <= (end ?? start); s++) {
        cellGrid[day]![s] = _Cell(
          courseName: entry.course.name,
          location: entry.session.location.room,
          start: s == start,
        );
      }
    }

    // 用画布尺寸做整体缩放因子，让所有字号 / 间距按比例放大，
    // 360x240 是基线；走 720x480 时所有数值就是 2x。
    final scale = size.height / 240.0;

    return MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(1)),
      child: Material(
        color: const Color(0xFFFAF8F6),
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: Padding(
            padding: EdgeInsets.all(10 * scale),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Header(
                  weekNumber: snapshot.displayWeek,
                  monday: monday,
                  scale: scale,
                ),
                SizedBox(height: 8 * scale),
                Expanded(
                  child: _Grid(
                    monday: monday,
                    today: today,
                    sectionCount: sectionCount,
                    cellGrid: cellGrid,
                    scale: scale,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Cell {
  const _Cell({
    required this.courseName,
    required this.location,
    required this.start,
  });

  final String courseName;
  final String location;

  /// 是否是这门课的起始节（用于决定要不要在格子内画文字，避免连堂的下半段
  /// 重复显示课程名）。
  final bool start;
}

class _Header extends StatelessWidget {
  const _Header({
    required this.weekNumber,
    required this.monday,
    required this.scale,
  });

  final int weekNumber;
  final DateTime monday;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final sunday = monday.add(const Duration(days: 6));
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          '本周课表',
          style: TextStyle(
            color: const Color(0xFF1A1A1A),
            fontSize: 13 * scale,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
          ),
        ),
        Text(
          '第 $weekNumber 周 · ${monday.month}/${monday.day} - ${sunday.month}/${sunday.day}',
          style: TextStyle(
            color: const Color(0xFF1C8C6E),
            fontSize: 10 * scale,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({
    required this.monday,
    required this.today,
    required this.sectionCount,
    required this.cellGrid,
    required this.scale,
  });

  final DateTime monday;
  final DateTime today;
  final int sectionCount;
  final Map<int, Map<int, _Cell>> cellGrid;
  final double scale;

  static const _dayLabels = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final sectionColWidth = 22.0 * scale;
        final headerHeight = 20.0 * scale;
        final colWidth =
            (constraints.maxWidth - sectionColWidth) / 7;
        final rowHeight =
            (constraints.maxHeight - headerHeight) / sectionCount;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Day-of-week 行
            SizedBox(
              height: headerHeight,
              child: Row(
                children: [
                  SizedBox(width: sectionColWidth),
                  for (var i = 0; i < 7; i++)
                    SizedBox(
                      width: colWidth,
                      child: _DayLabel(
                        date: monday.add(Duration(days: i)),
                        today: today,
                        weekday: i + 1,
                        label: _dayLabels[i],
                        scale: scale,
                      ),
                    ),
                ],
              ),
            ),
            // 课节行
            for (var section = 1; section <= sectionCount; section++)
              SizedBox(
                height: rowHeight,
                child: Row(
                  children: [
                    SizedBox(
                      width: sectionColWidth,
                      child: Center(
                        child: Text(
                          '$section',
                          style: TextStyle(
                            color: const Color(0xFFAAAAAA),
                            fontSize: 9 * scale,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    for (var day = 1; day <= 7; day++)
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 1.5 * scale,
                          vertical: 1.5 * scale,
                        ),
                        child: SizedBox(
                          width: colWidth - 3 * scale,
                          height: rowHeight - 3 * scale,
                          child: _CellTile(
                            cell: cellGrid[day]?[section],
                            day: day,
                            section: section,
                            scale: scale,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _DayLabel extends StatelessWidget {
  const _DayLabel({
    required this.date,
    required this.today,
    required this.weekday,
    required this.label,
    required this.scale,
  });

  final DateTime date;
  final DateTime today;
  final int weekday;
  final String label;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final isToday = date.year == today.year &&
        date.month == today.month &&
        date.day == today.day;
    final color = isToday
        ? const Color(0xFF1C8C6E)
        : const Color(0xFF555555);
    return Center(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10 * scale,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(width: 3 * scale),
          Text(
            '${date.month}/${date.day}',
            style: TextStyle(
              color: color.withValues(alpha: 0.65),
              fontSize: 9 * scale,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _CellTile extends StatelessWidget {
  const _CellTile({
    required this.cell,
    required this.day,
    required this.section,
    required this.scale,
  });

  final _Cell? cell;
  final int day;
  final int section;
  final double scale;

  /// 给同一门课算一个稳定的颜色，由 hash 取模映射到几个柔和色。
  static const _palette = [
    Color(0xFF5B8DEF),
    Color(0xFF4CAF50),
    Color(0xFFE8A838),
    Color(0xFFE57373),
    Color(0xFF00ACC1),
    Color(0xFFAB47BC),
    Color(0xFF8D6E63),
  ];

  Color _colorFor(String courseName) {
    final h = courseName.hashCode.abs();
    return _palette[h % _palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final c = cell;
    if (c == null) {
      // 空格 - 极淡灰
      return Container(
        decoration: BoxDecoration(
          color: const Color(0x10000000),
          borderRadius: BorderRadius.circular(4 * scale),
        ),
      );
    }
    final color = _colorFor(c.courseName);
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(4 * scale),
        border: Border(
          left: BorderSide(color: color, width: 2 * scale),
        ),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: 3 * scale,
        vertical: 2 * scale,
      ),
      // 用 ClipRect 防止内容溢出（cell 极小时 9*scale 文字仍可能超出可用空间）。
      // 起始节才画文字；连堂的下半段格子保留色块视觉，避免重复信息。
      child: c.start ? _CellContent(cell: c, color: color, scale: scale) : null,
    );
  }
}

/// 单元格内文字内容。
///
/// 关键点：用 `LayoutBuilder + FittedBox(BoxFit.scaleDown)` 保证内容永远
/// 不会溢出 cell —— 当 row 高度被压到 8.9px 这种极端尺寸（比如 sectionCount
/// 超大）时，整组文字会按比例缩到 cell 之内而不是触发 RenderFlex overflow。
class _CellContent extends StatelessWidget {
  const _CellContent({
    required this.cell,
    required this.color,
    required this.scale,
  });

  final _Cell cell;
  final Color color;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: LayoutBuilder(
        builder: (context, constraints) {
          // cell 高度过小（< ~14*scale）就只画一条小色条 + 课名，省略地址。
          final tinyHeight = constraints.maxHeight < 14 * scale;
          return FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: constraints.maxWidth,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    cell.courseName,
                    maxLines: tinyHeight ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    softWrap: !tinyHeight,
                    style: TextStyle(
                      color: color.withValues(alpha: 0.95),
                      fontSize: 9 * scale,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                    ),
                  ),
                  if (!tinyHeight && cell.location.isNotEmpty) ...[
                    SizedBox(height: 1 * scale),
                    Text(
                      cell.location,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: const Color(0xFF666666),
                        fontSize: 8 * scale,
                        height: 1.0,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
