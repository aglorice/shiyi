import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../core/logging/app_logger.dart';
import '../../modules/schedule/domain/entities/schedule_snapshot.dart';

/// 把 [ScheduleSnapshot] 转成 RFC 5545 风格的 .ics 字符串。
///
/// 设计：
/// - 学校排课只给出「第 N 周 周X 起讫时段」，没有具体日期。
///   因此调用方必须传一个 [referenceDate] 和 [referenceWeek]，
///   作为「这一周等于学期第几周」的锚点（首页和课表已经在用 g_referenceDate）。
/// - 一个 [ClassSession] 在 weekRange 范围内每周一节，用 RRULE COUNT 表示。
/// - 时间戳用 floating local time，避开时区差异（学校客户端基本都按本地时区显示）。
class ScheduleIcsExporter {
  ScheduleIcsExporter({this.logger = const AppLogger()});

  final AppLogger logger;

  /// 生成 ICS 字符串。返回 null 表示没有可导出的会话。
  String? buildIcs({
    required ScheduleSnapshot snapshot,
    required DateTime referenceDate,
    required int referenceWeek,
  }) {
    final entries = snapshot.entries;
    if (entries.isEmpty) {
      return null;
    }

    final week1Monday = _mondayOfWeek1(
      referenceDate: referenceDate,
      referenceWeek: referenceWeek,
    );
    final stamp = _formatStamp(DateTime.now());
    final termId = snapshot.term.id.replaceAll(RegExp(r'\s+'), '_');
    final termName = snapshot.term.name;

    final buffer = StringBuffer()
      ..writeln('BEGIN:VCALENDAR')
      ..writeln('VERSION:2.0')
      ..writeln('PRODID:-//uni_yi//schedule-export//ZH')
      ..writeln('CALSCALE:GREGORIAN')
      ..writeln('METHOD:PUBLISH')
      ..writeln(_foldLine('X-WR-CALNAME:$termName 课表'));

    for (final entry in entries) {
      final session = entry.session;
      final startWeek = session.weekRange.startWeek;
      final endWeek = session.weekRange.endWeek;
      if (endWeek < startWeek) {
        continue;
      }
      final dayOfWeek = session.dayOfWeek.clamp(1, 7);
      final startDate = week1Monday.add(
        Duration(days: (startWeek - 1) * 7 + (dayOfWeek - 1)),
      );
      final start = _composeDate(startDate, session.startTime);
      final end = _composeDate(startDate, session.endTime);
      if (start == null || end == null || !end.isAfter(start)) {
        continue;
      }

      final count = endWeek - startWeek + 1;
      final uid = '${entry.course.id}-w$startWeek-d$dayOfWeek-$termId'
          '@uni-yi';

      buffer
        ..writeln('BEGIN:VEVENT')
        ..writeln('UID:$uid')
        ..writeln('DTSTAMP:$stamp')
        ..writeln('DTSTART:${_formatLocal(start)}')
        ..writeln('DTEND:${_formatLocal(end)}')
        ..writeln(_foldLine('SUMMARY:${_escape(entry.course.name)}'));

      final descriptionParts = <String>[
        if (entry.course.teacher.trim().isNotEmpty)
          '教师 ${entry.course.teacher}',
        '节次 ${session.sectionLabel}',
        '周次 ${session.weekLabel}',
        if (entry.course.note?.trim().isNotEmpty ?? false)
          '备注 ${entry.course.note}',
      ];
      if (descriptionParts.isNotEmpty) {
        buffer.writeln(
          _foldLine(
            'DESCRIPTION:${_escape(descriptionParts.join('\\n'))}',
          ),
        );
      }
      final location = session.location.fullName;
      if (location.trim().isNotEmpty) {
        buffer.writeln(_foldLine('LOCATION:${_escape(location)}'));
      }
      if (count > 1) {
        buffer.writeln('RRULE:FREQ=WEEKLY;COUNT=$count');
      }
      buffer.writeln('END:VEVENT');
    }

    buffer.writeln('END:VCALENDAR');
    return buffer.toString();
  }

  /// 把 ICS 字符串落到临时目录，返回 [File]。文件名带学期 id，方便用户辨认。
  Future<File> writeToTemp({
    required String ics,
    required ScheduleSnapshot snapshot,
  }) async {
    final dir = await getTemporaryDirectory();
    final safeId = snapshot.term.id
        .replaceAll(RegExp(r'[^A-Za-z0-9_\-]+'), '_');
    final file = File('${dir.path}/uni_yi_schedule_$safeId.ics');
    await file.writeAsString(ics);
    logger.info(
      '[ICS] 已生成 ${file.path}（事件数=${ics.split('BEGIN:VEVENT').length - 1}）',
    );
    return file;
  }

  /// 学期第 1 周周一。
  /// 思路：用「[referenceDate] 所在那周的周一」减去 (referenceWeek-1) * 7 天。
  DateTime _mondayOfWeek1({
    required DateTime referenceDate,
    required int referenceWeek,
  }) {
    final normalized = DateTime(
      referenceDate.year,
      referenceDate.month,
      referenceDate.day,
    );
    final monday = normalized.subtract(
      Duration(days: normalized.weekday - 1),
    );
    return monday.subtract(Duration(days: (referenceWeek - 1) * 7));
  }

  DateTime? _composeDate(DateTime baseDay, String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return DateTime(baseDay.year, baseDay.month, baseDay.day, hour, minute);
  }

  String _formatStamp(DateTime utc) {
    final value = utc.toUtc();
    return '${_d4(value.year)}${_d2(value.month)}${_d2(value.day)}'
        'T${_d2(value.hour)}${_d2(value.minute)}${_d2(value.second)}Z';
  }

  /// 不带 Z 表示 floating local time，多数日历客户端会用本地时区解释。
  String _formatLocal(DateTime local) {
    return '${_d4(local.year)}${_d2(local.month)}${_d2(local.day)}'
        'T${_d2(local.hour)}${_d2(local.minute)}${_d2(local.second)}';
  }

  String _d2(int n) => n.toString().padLeft(2, '0');
  String _d4(int n) => n.toString().padLeft(4, '0');

  String _escape(String value) {
    return value
        .replaceAll(r'\', r'\\')
        .replaceAll(';', r'\;')
        .replaceAll(',', r'\,')
        .replaceAll('\n', r'\n');
  }

  /// RFC 5545 要求每行不超过 75 个 octet，超出要在 75 处折行并以单空格起始。
  /// 这里用更宽容的 73，避免不同实现对 utf8 多字节的边界 bug。
  String _foldLine(String line) {
    const limit = 73;
    if (line.length <= limit) return line;
    final buffer = StringBuffer();
    var index = 0;
    while (index < line.length) {
      final end = (index + limit < line.length) ? index + limit : line.length;
      if (index == 0) {
        buffer.write(line.substring(index, end));
      } else {
        buffer.write('\r\n ');
        buffer.write(line.substring(index, end));
      }
      index = end;
    }
    return buffer.toString();
  }
}
