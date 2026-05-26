import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../app/settings/schedule_timing_preference.dart';
import '../../core/logging/app_logger.dart';
import '../../modules/schedule/domain/entities/schedule_snapshot.dart';

/// 上课提醒服务。负责：
/// - 申请通知权限（首次开启时）；
/// - 把 [ScheduleSnapshot] 解析成"未来若干天的课节开始时间"，
///   按用户设置的提前分钟给每节课排一条本地提醒；
/// - 在用户调用 [reschedule] 之前先全部 cancel，避免课表更新后老的提醒还在响。
///
/// 设计说明：
/// - 只排"未来 7 天"的提醒，避免一次性写入几百条让系统拒绝；
///   课表通常一周更新一次，每周自动 reschedule 一次足够。
/// - 通道 ID 固定 `class_reminders`，通知 ID 用 sessionUniqueKey 哈希到 31 位整数。
class ClassReminderService {
  ClassReminderService({required AppLogger logger}) : _logger = logger;

  final AppLogger _logger;
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const _channelId = 'class_reminders';
  static const _channelName = '上课提醒';
  static const _channelDescription = '在每节课开始前推送提醒';

  bool _initialized = false;

  Future<void> _ensureInit() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    // 简单起见用本地时区，flutter_local_notifications 19+ 可以通过
    // tz.local 自动读到设备时区；这里再 fallback 到 Asia/Shanghai。
    try {
      // 没有官方 API 直接读设备时区名，留给 timezone 默认取本地。
      tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
    } catch (_) {
      // 忽略：用 default。
    }

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
    );

    // 显式建一个 Android 通道，老设备需要。
    final androidImpl = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidImpl?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDescription,
        importance: Importance.high,
      ),
    );

    _initialized = true;
  }

  /// 申请发送通知权限。第一次开启提醒时调用。
  /// 返回 true 即用户授权。
  Future<bool> requestPermission() async {
    await _ensureInit();
    if (kIsWeb) return false;

    if (Platform.isAndroid) {
      // Android 13+ 需要 POST_NOTIFICATIONS。
      final status = await Permission.notification.request();
      if (!status.isGranted) {
        _logger.warn('[REMINDER] Android 通知权限未授权 status=$status');
        return false;
      }
      // Android 12+ 需要精确闹钟权限（exact alarm）才能按指定时间触发。
      // permission_handler 没暴露 SCHEDULE_EXACT_ALARM，
      // 这里走 plugin 自带的 canScheduleExactNotifications + intent。
      final androidImpl = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final canExact =
          await androidImpl?.canScheduleExactNotifications() ?? true;
      if (!canExact) {
        _logger.info('[REMINDER] 请求精确闹钟权限');
        await androidImpl?.requestExactAlarmsPermission();
      }
      return true;
    }

    if (Platform.isIOS) {
      final iosImpl = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      final result = await iosImpl?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return result ?? false;
    }

    return false;
  }

  /// 全部撤销已排程的上课提醒。
  Future<void> cancelAll() async {
    await _ensureInit();
    await _plugin.cancelAll();
    _logger.info('[REMINDER] 已撤销全部上课提醒');
  }

  /// 用最新的课表 + 时间偏好重新排程。
  /// [reminderLeadMinutes] 为 0 表示"准点提醒"。
  /// 默认排未来 7 天。
  Future<int> reschedule({
    required ScheduleSnapshot snapshot,
    required ScheduleTimingPreference timing,
    required int reminderLeadMinutes,
    int rangeDays = 7,
  }) async {
    await _ensureInit();
    if (kIsWeb) {
      _logger.info('[REMINDER] Web 不支持本地通知，跳过 reschedule');
      return 0;
    }
    await _plugin.cancelAll();

    if (!timing.enabled) {
      _logger.info('[REMINDER] 未启用具体时间设置，无法生成精确提醒');
      return 0;
    }
    final sectionTimes = timing.resolveSectionTimes();
    if (sectionTimes.isEmpty) {
      return 0;
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    var scheduled = 0;

    for (var dayOffset = 0; dayOffset <= rangeDays; dayOffset++) {
      final date = today.add(Duration(days: dayOffset));
      final dayOfWeek = date.weekday; // 1..7
      // displayWeek 是从 snapshot 读出来的"今日所在第几教学周"。
      // 加 dayOffset / 7 拿目标日所在的周。
      final targetWeek = snapshot.displayWeek + (dayOffset ~/ 7);

      final entries = snapshot.entriesForWeek(week: targetWeek);
      for (final entry in entries) {
        final session = entry.session;
        if (session.dayOfWeek != dayOfWeek) continue;
        final sectionStart = session.startSection;
        if (sectionStart == null) continue;
        final sectionTime = sectionTimes[sectionStart];
        if (sectionTime == null) continue;
        final parsed = _parseHm(sectionTime.start);
        if (parsed == null) continue;

        final classStart = DateTime(
          date.year,
          date.month,
          date.day,
          parsed.$1,
          parsed.$2,
        );
        final fireAt = classStart.subtract(
          Duration(minutes: reminderLeadMinutes),
        );
        if (!fireAt.isAfter(now)) continue;

        await _scheduleOne(
          fireAt: fireAt,
          title: _composeTitle(reminderLeadMinutes, entry.course.name),
          body: _composeBody(session, sectionTime, entry.course.teacher),
          payload: 'class:${entry.course.id}:${session.dayOfWeek}:'
              '${session.startSection}',
        );
        scheduled++;
      }
    }

    _logger.info('[REMINDER] 已排程 $scheduled 条上课提醒（未来 $rangeDays 天）');
    return scheduled;
  }

  Future<void> _scheduleOne({
    required DateTime fireAt,
    required String title,
    required String body,
    required String payload,
  }) async {
    final tzFireAt = tz.TZDateTime.from(fireAt, tz.local);
    // ID 只能是 32 位整数，用 (毫秒时间戳 ^ payload.hashCode) 折叠到 0..2^31-1。
    final id =
        (fireAt.millisecondsSinceEpoch.toUnsigned(31) ^
                payload.hashCode.toUnsigned(31))
            .toUnsigned(31);

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tzFireAt,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: payload,
    );
  }

  String _composeTitle(int leadMinutes, String courseName) {
    if (leadMinutes <= 0) {
      return '$courseName 即将开始';
    }
    return '$leadMinutes 分钟后：$courseName';
  }

  String _composeBody(
    ClassSession session,
    ({String start, String end}) sectionTime,
    String teacher,
  ) {
    final time = '${sectionTime.start} - ${sectionTime.end}';
    final location = session.location.fullName;
    final parts = <String>[time];
    if (location.isNotEmpty) parts.add(location);
    if (teacher.isNotEmpty) parts.add(teacher);
    return parts.join(' · ');
  }

  (int, int)? _parseHm(String value) {
    final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(value.trim());
    if (match == null) return null;
    final h = int.tryParse(match.group(1)!);
    final m = int.tryParse(match.group(2)!);
    if (h == null || m == null) return null;
    return (h, m);
  }
}
