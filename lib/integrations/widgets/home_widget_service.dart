import 'dart:io';
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/settings/schedule_timing_preference.dart';
import '../../core/logging/app_logger.dart';
import '../../modules/schedule/domain/entities/schedule_snapshot.dart';
import 'week_schedule_widget_view.dart';

/// 桌面小组件数据中转层。
///
/// 现在提供两个组件：
/// - 「下节课」：纯文本，原生侧 RemoteViews 渲染。
/// - 「整周课表」：把 [WeekScheduleWidgetView] 渲染成 PNG 推到原生侧的
///   ImageView，避免在 Kotlin 里手画一遍 7×N 的网格。
class HomeWidgetService {
  HomeWidgetService({required AppLogger logger}) : _logger = logger;

  final AppLogger _logger;

  // Android 与 iOS 都用同一个 group 名。Android 这边映射到 SharedPreferences
  // 文件 `HomeWidgetPreferences`；iOS 接入后映射到 App Group。
  static const _groupName = 'group.com.uniyi.uni_yi.widget';

  // 「下节课」相关 key
  static const _kCourseName = 'next_class.courseName';
  static const _kTimeRange = 'next_class.timeRange';
  static const _kLocation = 'next_class.location';
  static const _kTeacher = 'next_class.teacher';
  static const _kSubtitle = 'next_class.subtitle';
  static const _kHasNext = 'next_class.has';

  // 「整周课表」相关 key
  static const _kWeekImagePath = 'week_schedule.imagePath';
  static const _kWeekUpdatedAt = 'week_schedule.updatedAt';
  // 没有任何课程数据时把 hasData 置 false，原生侧切空态。
  static const _kWeekHasData = 'week_schedule.hasData';

  static const _nextClassProvider = 'NextClassWidgetProvider';
  static const _weekScheduleProvider = 'WeekScheduleWidgetProvider';
  static const _iosNextClassWidgetName = 'NextClassWidget';
  static const _iosWeekScheduleWidgetName = 'WeekScheduleWidget';

  Future<void> _ensureInit() async {
    await HomeWidget.setAppGroupId(_groupName);
  }

  /// 一次性把所有 widget 都更新到最新课表。
  Future<void> updateForSchedule({
    required ScheduleSnapshot snapshot,
    required ScheduleTimingPreference timing,
  }) async {
    await _ensureInit();
    await _updateNextClass(snapshot: snapshot, timing: timing);
    await _updateWeekSchedule(snapshot: snapshot, timing: timing);
  }

  // ---------------- 下节课 ----------------

  Future<void> _updateNextClass({
    required ScheduleSnapshot snapshot,
    required ScheduleTimingPreference timing,
  }) async {
    try {
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
        androidName: _nextClassProvider,
        iOSName: _iosNextClassWidgetName,
      );
      _logger.info(
        '[WIDGET] 推送下节课 hasNext=${next != null}',
      );
    } catch (error, stackTrace) {
      _logger.warn('[WIDGET] 下节课推送失败 error=$error');
      _logger.debug('[WIDGET] stackTrace=$stackTrace');
    }
  }

  // ---------------- 整周课表 ----------------

  Future<void> _updateWeekSchedule({
    required ScheduleSnapshot snapshot,
    required ScheduleTimingPreference timing,
  }) async {
    if (kIsWeb) return;
    try {
      final hasData = snapshot.entries.isNotEmpty;
      await HomeWidget.saveWidgetData(_kWeekHasData, hasData);

      if (hasData) {
        // 用 home_widget 提供的 renderFlutterWidget 把 Flutter 视图栅格化成 PNG。
        // 注意：必须在主 isolate / 主 BuildContext 之外，但 home_widget 自己
        // 内部启动了一个 PipelineOwner 跑离屏渲染，调起来很简单。
        final imagePath = await HomeWidget.renderFlutterWidget(
          WeekScheduleWidgetView(snapshot: snapshot, timing: timing),
          key: 'week_schedule',
          // logical pixels；原生 ImageView 会按 DPR 缩放到位。
          logicalSize: const Size(360, 240),
        );
        if (imagePath is String && imagePath.isNotEmpty) {
          await HomeWidget.saveWidgetData(_kWeekImagePath, imagePath);
        } else {
          await HomeWidget.saveWidgetData(_kWeekImagePath, '');
        }
        // 给原生侧一个时间戳辅助调试（看 widget 多久没刷新过）。
        await HomeWidget.saveWidgetData(
          _kWeekUpdatedAt,
          DateTime.now().millisecondsSinceEpoch,
        );
      } else {
        // 没数据时把旧 PNG 删掉，避免空态还在显示上次的图。
        final old = await HomeWidget.getWidgetData<String>(_kWeekImagePath);
        if (old != null && old.isNotEmpty) {
          try {
            await File(old).delete();
          } catch (_) {}
        }
        await HomeWidget.saveWidgetData(_kWeekImagePath, '');
      }

      await HomeWidget.updateWidget(
        androidName: _weekScheduleProvider,
        iOSName: _iosWeekScheduleWidgetName,
      );
      _logger.info(
        '[WIDGET] 推送整周课表 hasData=$hasData entries=${snapshot.entries.length}',
      );
    } catch (error, stackTrace) {
      _logger.warn('[WIDGET] 整周课表推送失败 error=$error');
      _logger.debug('[WIDGET] stackTrace=$stackTrace');
    }
  }

  /// 调试用：返回 widget PNG 落盘的位置。
  Future<String?> debugWeekImagePath() async {
    try {
      final dir = await getApplicationSupportDirectory();
      return '${dir.path}/week_schedule.png';
    } catch (_) {
      return null;
    }
  }

  // ---------------- 内部计算 ----------------

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
      final entries = snapshot
          .entriesForWeek(week: week)
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
