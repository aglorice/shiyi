import 'dart:convert';
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
  // 不再在 Dart 端预先挑出"哪一节是下一节"。改成把"今天 + 后 6 天"所有
  // 课程的绝对起止时间打包成 JSON 数组推到 SharedPreferences，
  // Kotlin 那边的 widget 在 onUpdate 时根据当前墙上时间挑选第一个还没开始
  // 的 session。这样 App 不打开 widget 也能跟着系统每 30 分钟刷新自动跳到
  // 真正的下一节。
  static const _kNextClassPlan = 'next_class.plan';
  // 同时保留这一组 fallback 字段：plan 解析失败 / 太老时，原生侧仍能展示
  // 出最近一次 App 推送过来的"下一节"。
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

  static const _nextClassProvider =
      'com.uniyi.uni_yi.widget.NextClassWidgetProvider';
  static const _weekScheduleProvider =
      'com.uniyi.uni_yi.widget.WeekScheduleWidgetProvider';
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
      // 1) 算出未来 7 天里所有有具体时间的 session，落成 JSON。
      final plan = _buildClassPlan(snapshot: snapshot, timing: timing);
      await HomeWidget.saveWidgetData(_kNextClassPlan, jsonEncode(plan));

      // 2) 同步给 fallback 字段当快照，防止 plan 失效时 widget 全空。
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
        qualifiedAndroidName: _nextClassProvider,
        iOSName: _iosNextClassWidgetName,
      );
      _logger.info(
        '[WIDGET] 推送下节课 plan=${plan.length} 节 fallbackHasNext=${next != null}',
      );
    } catch (error, stackTrace) {
      _logger.warn('[WIDGET] 下节课推送失败 error=$error');
      _logger.debug('[WIDGET] stackTrace=$stackTrace');
    }
  }

  /// 把课表压成原生 widget 能消费的轻量 JSON：
  /// `[{ "ts":1779550800000, "te":1779553500000, "name":"高数","loc":"...","teacher":"..." }, ...]`
  ///
  /// - ts/te 用毫秒 epoch，原生侧拿到直接 `now < ts` 比较，免去重复时间解析；
  /// - 范围未来 7 天，配合 widget 默认 30 分钟刷新足够覆盖。
  List<Map<String, dynamic>> _buildClassPlan({
    required ScheduleSnapshot snapshot,
    required ScheduleTimingPreference timing,
    int rangeDays = 7,
  }) {
    final out = <Map<String, dynamic>>[];
    if (!timing.enabled) return out;
    final sectionTimes = timing.resolveSectionTimes();
    if (sectionTimes.isEmpty) return out;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    for (var dayOffset = 0; dayOffset <= rangeDays; dayOffset++) {
      final date = today.add(Duration(days: dayOffset));
      final week = snapshot.displayWeek + (dayOffset ~/ 7);
      final entries = snapshot
          .entriesForWeek(week: week)
          .where((e) => e.session.dayOfWeek == date.weekday)
          .toList();
      for (final entry in entries) {
        final session = entry.session;
        final start = session.startSection;
        if (start == null) continue;
        final st = sectionTimes[start];
        if (st == null) continue;
        final endSec = session.endSection ?? start;
        final et = sectionTimes[endSec];
        final sParsed = _parseHm(st.start);
        final eParsed = _parseHm(et?.end ?? st.end);
        if (sParsed == null) continue;
        final classStart = DateTime(
          date.year, date.month, date.day, sParsed.$1, sParsed.$2,
        );
        final classEnd = eParsed == null
            ? classStart.add(Duration(minutes: timing.lessonMinutes))
            : DateTime(
                date.year, date.month, date.day, eParsed.$1, eParsed.$2,
              );
        out.add({
          'ts': classStart.millisecondsSinceEpoch,
          'te': classEnd.millisecondsSinceEpoch,
          'name': entry.course.name,
          'loc': session.location.fullName,
          'teacher': entry.course.teacher,
        });
      }
    }
    // 按起始时间排序，方便原生侧线性扫描第一条 ts > now 的。
    out.sort((a, b) => (a['ts'] as int).compareTo(b['ts'] as int));
    return out;
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
        // logicalSize 用 720×480（基线 360×240 的 2 倍）：
        // - 设备桌面缩放后仍然清晰（正常手机 widget 显示宽度 320–360 dp，
        //   720 像素的图缩到这个区间不会被放大模糊）；
        // - week_schedule_widget_view 内部按 size 自适应字号 / 间距，
        //   2 倍渲染后字号也按比例放大，PNG 仍然是清晰的。
        final imagePath = await HomeWidget.renderFlutterWidget(
          WeekScheduleWidgetView(snapshot: snapshot, timing: timing),
          key: 'week_schedule',
          logicalSize: const Size(720, 480),
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
        qualifiedAndroidName: _weekScheduleProvider,
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
