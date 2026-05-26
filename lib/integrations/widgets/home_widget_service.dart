import 'package:home_widget/home_widget.dart';

import '../../app/settings/schedule_timing_preference.dart';
import '../../core/logging/app_logger.dart';
import '../../modules/schedule/domain/entities/schedule_snapshot.dart';

/// 把"下节课"信息推到原生桌面小组件的共享 SharedPreferences。
/// 现在只完成了 Android 这边的实现（lib/.../widget/NextClassWidgetProvider.kt
/// 直接读这些 key）。iOS 的 WidgetKit 需要单独建 target，留给后续。
class HomeWidgetService {
  HomeWidgetService({required AppLogger logger}) : _logger = logger;

  final AppLogger _logger;

  // Android 与 iOS 都用同一个 group 名。Android 这边映射到 SharedPreferences
  // 文件 `HomeWidgetPreferences`；iOS 接入后映射到 App Group。
  static const _groupName = 'group.com.uniyi.uni_yi.widget';
  static const _kCourseName = 'next_class.courseName';
  static const _kTimeRange = 'next_class.timeRange';
  static const _kLocation = 'next_class.location';
  static const _kTeacher = 'next_class.teacher';
  static const _kSubtitle = 'next_class.subtitle';
  // 当前没有下节课时（已经放学/没排课），写入 false 让 widget 显示空态。
  static const _kHasNext = 'next_class.has';

  static const _androidProvider = 'NextClassWidgetProvider';
  static const _iosWidgetName = 'NextClassWidget';

  Future<void> _ensureInit() async {
    await HomeWidget.setAppGroupId(_groupName);
  }

  /// 把 "今天 + 之后" 的下一节课写入小组件。
  Future<void> updateForSchedule({
    required ScheduleSnapshot snapshot,
    required ScheduleTimingPreference timing,
  }) async {
    try {
      await _ensureInit();
      final next = _findNextClass(snapshot, timing);
      if (next == null) {
        await HomeWidget.saveWidgetData(_kHasNext, false);
        await HomeWidget.saveWidgetData(_kCourseName, '今天没有更多课');
        await HomeWidget.saveWidgetData(_kSubtitle, '休息一下吧');
        await HomeWidget.saveWidgetData(_kTimeRange, '');
        await HomeWidget.saveWidgetData(_kLocation, '');
        await HomeWidget.saveWidgetData(_kTeacher, '');
      } else {
        await HomeWidget.saveWidgetData(_kHasNext, true);
        await HomeWidget.saveWidgetData(_kCourseName, next.courseName);
        await HomeWidget.saveWidgetData(_kSubtitle, next.subtitle);
        await HomeWidget.saveWidgetData(_kTimeRange, next.timeRange);
        await HomeWidget.saveWidgetData(_kLocation, next.location);
        await HomeWidget.saveWidgetData(_kTeacher, next.teacher);
      }
      await HomeWidget.updateWidget(
        androidName: _androidProvider,
        iOSName: _iosWidgetName,
      );
      _logger.info(
        '[WIDGET] 已推送下节课信息到桌面小组件 hasNext=${next != null}',
      );
    } catch (error, stackTrace) {
      _logger.warn('[WIDGET] 推送桌面小组件失败 error=$error');
      _logger.debug('[WIDGET] stackTrace=$stackTrace');
    }
  }

  _NextClassPayload? _findNextClass(
    ScheduleSnapshot snapshot,
    ScheduleTimingPreference timing,
  ) {
    if (!timing.enabled) return null;
    final sectionTimes = timing.resolveSectionTimes();
    if (sectionTimes.isEmpty) return null;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // 往后看 3 天（覆盖周末停课的常见情况）。
    for (var dayOffset = 0; dayOffset <= 3; dayOffset++) {
      final date = today.add(Duration(days: dayOffset));
      final week = snapshot.displayWeek + (dayOffset ~/ 7);
      final entries = snapshot.entriesForWeek(week: week)
          .where((e) => e.session.dayOfWeek == date.weekday)
          .toList();
      // 按 startSection 排序后找第一个还未过的。
      entries.sort((a, b) {
        final ax = a.session.startSection ?? 99;
        final bx = b.session.startSection ?? 99;
        return ax.compareTo(bx);
      });
      for (final entry in entries) {
        final session = entry.session;
        final start = session.startSection;
        if (start == null) continue;
        final st = sectionTimes[start];
        if (st == null) continue;
        final parsed = _parseHm(st.start);
        if (parsed == null) continue;
        final classStart = DateTime(
          date.year,
          date.month,
          date.day,
          parsed.$1,
          parsed.$2,
        );
        if (!classStart.isAfter(now)) continue;

        final endSec = session.endSection ?? start;
        final endTime = sectionTimes[endSec]?.end ?? st.end;
        return _NextClassPayload(
          courseName: entry.course.name,
          timeRange: '${st.start} - $endTime',
          location: session.location.fullName,
          teacher: entry.course.teacher,
          subtitle: _composeSubtitle(date, today, st.start),
        );
      }
    }
    return null;
  }

  String _composeSubtitle(DateTime classDay, DateTime today, String startHm) {
    if (classDay == today) return '今天 $startHm';
    final diff = classDay.difference(today).inDays;
    if (diff == 1) return '明天 $startHm';
    return '${classDay.month}/${classDay.day} $startHm';
  }

  (int, int)? _parseHm(String value) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(value.trim());
    if (m == null) return null;
    final h = int.tryParse(m.group(1)!);
    final mm = int.tryParse(m.group(2)!);
    if (h == null || mm == null) return null;
    return (h, mm);
  }
}

class _NextClassPayload {
  const _NextClassPayload({
    required this.courseName,
    required this.timeRange,
    required this.location,
    required this.teacher,
    required this.subtitle,
  });

  final String courseName;
  final String timeRange;
  final String location;
  final String teacher;
  final String subtitle;
}
