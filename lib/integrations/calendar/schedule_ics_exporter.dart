import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../app/settings/schedule_timing_preference.dart';
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

  /// 五邑大学按节次的标准上下课时间。本科生教务返回的 schedule.startTime 是
  /// "第N节" 这种文案，这里做一次映射兜底。
  /// 第 1~5 节 上午；6~10 下午；11~13 晚上。
  static const _sectionStartHm = <int, String>{
    1: '08:00',
    2: '08:50',
    3: '09:50',
    4: '10:40',
    5: '11:30',
    6: '14:00',
    7: '14:50',
    8: '15:50',
    9: '16:40',
    10: '17:30',
    11: '19:00',
    12: '19:50',
    13: '20:50',
  };
  static const _sectionEndHm = <int, String>{
    1: '08:45',
    2: '09:35',
    3: '10:35',
    4: '11:25',
    5: '12:15',
    6: '14:45',
    7: '15:35',
    8: '16:35',
    9: '17:25',
    10: '18:15',
    11: '19:45',
    12: '20:35',
    13: '21:35',
  };

  /// 生成 ICS 字符串。返回 null 表示没有可导出的会话。
  /// [skipped] 会被填充被跳过的原因列表，便于调用方提示用户。
  /// [timing] 如果 enabled，则按用户自定义的节次时间表覆盖默认。
  /// [onlyFutureFrom] 给定时只保留实际开始时间晚于该时刻的课次，
  /// 默认 null 表示导出整学期。
  String? buildIcs({
    required ScheduleSnapshot snapshot,
    required DateTime referenceDate,
    required int referenceWeek,
    List<String>? skipped,
    ScheduleTimingPreference? timing,
    DateTime? onlyFutureFrom,
  }) {
    final entries = snapshot.entries;
    if (entries.isEmpty) {
      return null;
    }

    final customTimes = (timing != null && timing.enabled)
        ? timing.resolveSectionTimes()
        : const <int, ({String start, String end})>{};
    final cutoff = onlyFutureFrom;

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

    var written = 0;
    for (final entry in entries) {
      final session = entry.session;
      var weeks = session.effectiveWeeks;
      // 1. 过滤掉已经过去的课次（启用 onlyFutureFrom 时）。
      if (cutoff != null) {
        weeks = _filterFutureWeeks(
          weeks: weeks,
          dayOfWeek: session.dayOfWeek.clamp(1, 7),
          week1Monday: week1Monday,
          cutoff: cutoff,
        );
      }
      if (weeks.isEmpty) {
        skipped?.add(
          '${entry.course.name}：'
          '${cutoff == null ? "未识别出周次" : "今天之后已无课次"}',
        );
        continue;
      }
      final dayOfWeek = session.dayOfWeek.clamp(1, 7);

      final times = _resolveTimes(session, customTimes);
      if (times == null) {
        skipped?.add(
          '${entry.course.name}：无法识别时间 '
          '(start="${session.startTime}", end="${session.endTime}", '
          'sec=${session.startSection}-${session.endSection})',
        );
        continue;
      }

      final baseDescriptionParts = <String>[
        if (entry.course.teacher.trim().isNotEmpty)
          '教师 ${entry.course.teacher}',
        '节次 ${session.sectionLabel}',
        '周次 ${session.weekLabel}',
        if (entry.course.note?.trim().isNotEmpty ?? false)
          '备注 ${entry.course.note}',
      ];
      final location = session.location.fullName;
      final locationLine =
          (location.trim().isEmpty || location == '地点待定')
              ? null
              : _foldLine('LOCATION:${_escape(location)}');
      final summaryLine = _foldLine('SUMMARY:${_escape(entry.course.name)}');

      // 2. 不再用 RRULE 压缩，而是每一周都写一条独立的 VEVENT。
      // 这样所有日历客户端都能直接看到 12/13/14/... 周的具体事件，
      // UID 中包含具体周号保证唯一性，重复导入也不会冲突。
      for (final w in weeks) {
        final startDate = week1Monday.add(
          Duration(days: (w - 1) * 7 + (dayOfWeek - 1)),
        );
        final start = _composeDate(startDate, times.$1);
        final end = _composeDate(startDate, times.$2);
        if (start == null || end == null || !end.isAfter(start)) {
          skipped?.add('${entry.course.name}：起讫时间组装失败 (week=$w)');
          continue;
        }

        final descriptionParts = <String>[
          '第 $w 周',
          ...baseDescriptionParts,
        ];
        final descriptionLine = _foldLine(
          'DESCRIPTION:${_escape(descriptionParts.join('\\n'))}',
        );

        final uid =
            '${entry.course.id}-w${w}d$dayOfWeek-$termId@uni-yi';

        buffer
          ..writeln('BEGIN:VEVENT')
          ..writeln('UID:$uid')
          ..writeln('DTSTAMP:$stamp')
          ..writeln('DTSTART:${_formatLocal(start)}')
          ..writeln('DTEND:${_formatLocal(end)}')
          ..writeln(summaryLine)
          ..writeln(descriptionLine);
        if (locationLine != null) {
          buffer.writeln(locationLine);
        }
        buffer.writeln('END:VEVENT');
        written++;
      }
    }

    buffer.writeln('END:VCALENDAR');

    if (written == 0) {
      logger.warn(
        '[ICS] 一个事件都没写入。entries=${entries.length} '
        'skipped=${skipped?.length ?? 0}',
      );
      return null;
    }
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

  /// 解析 [session] 起止时间，返回 (start "HH:mm", end "HH:mm")。
  /// 优先级：
  /// 1. [customTimes] 命中（来自用户自定义时间表）；
  /// 2. session.startTime 已经是 HH:mm；
  /// 3. session 提供 startSection/endSection，去 [_sectionStartHm] 表里查；
  /// 4. session.startTime 形如「第N节」，用正则抽出 N 再查表。
  (String, String)? _resolveTimes(
    ClassSession session,
    Map<int, ({String start, String end})> customTimes,
  ) {
    final startSec = session.startSection ?? _matchSectionNumber(session.startTime);
    final endSec = session.endSection ?? _matchSectionNumber(session.endTime);

    if (customTimes.isNotEmpty) {
      if (startSec != null && endSec != null) {
        final s = customTimes[startSec];
        final e = customTimes[endSec];
        if (s != null && e != null) return (s.start, e.end);
      }
    }

    final hmStart = _matchHhmm(session.startTime);
    final hmEnd = _matchHhmm(session.endTime);
    if (hmStart != null && hmEnd != null) {
      return (hmStart, hmEnd);
    }

    if (startSec != null && endSec != null) {
      final s = _sectionStartHm[startSec];
      final e = _sectionEndHm[endSec];
      if (s != null && e != null) return (s, e);
    }
    return null;
  }

  String? _matchHhmm(String value) {
    final match = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(value);
    if (match == null) return null;
    final h = int.tryParse(match.group(1)!) ?? 0;
    final m = int.tryParse(match.group(2)!) ?? 0;
    return '${_d2(h)}:${_d2(m)}';
  }

  int? _matchSectionNumber(String value) {
    final match = RegExp(r'(\d+)').firstMatch(value);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
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

  /// 只保留实际开始时间晚于 [cutoff] 的周次。
  List<int> _filterFutureWeeks({
    required List<int> weeks,
    required int dayOfWeek,
    required DateTime week1Monday,
    required DateTime cutoff,
  }) {
    final result = <int>[];
    for (final w in weeks) {
      // 把这一节的"那一天"取出来，没必要管 HH:mm —— 只要那天 23:59 之后就保留。
      final day = week1Monday.add(
        Duration(days: (w - 1) * 7 + (dayOfWeek - 1)),
      );
      // cutoff 当作"今天 00:00"或当前时间皆可。这里用"day 23:59 > cutoff"
      // 这种语义保留所有"今天起还会发生"的课次。
      final dayEnd = DateTime(day.year, day.month, day.day, 23, 59);
      if (dayEnd.isAfter(cutoff)) {
        result.add(w);
      }
    }
    return result;
  }

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
