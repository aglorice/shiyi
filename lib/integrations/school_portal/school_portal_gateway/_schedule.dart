// 课表：本科走 jxgl，研究生走 yjsc 学期 + 课程矩阵。
// 本文件还把课表/研究生网格 / 周次 / 时段 / 教学楼信息的解析助手放在一起。
part of '../school_portal_gateway.dart';

mixin _ScheduleGateway on _GatewayBase implements SchoolPortalGateway {
  @override
  Future<Result<ScheduleSnapshot>> fetchSchedule(
    AppSession session, {
    String? termId,
  }) async {
    _logger.info('[Gateway] 开始加载课表 userId=${session.userId} termId=$termId');
    final validation = await validateSession(session);
    if (validation.isFailure) {
      _logger.warn('[Gateway] 课表加载前 session 校验失败');
      return FailureResult(validation.failureOrNull!);
    }

    if (session.isUndergraduate) {
      return _fetchUndergradSchedule(session, termId: termId);
    }

    final termsResult = await _portalApi.fetchYjsData(
      session,
      path: '/student/default/bindterm',
      method: 'GET',
      queryParameters: {'_': _nonce()},
    );
    if (termsResult case FailureResult<dynamic>(failure: final failure)) {
      return FailureResult(failure);
    }

    final termMaps = _collectRecordMaps(termsResult.dataOrNull)
        .where(
          (map) => _pickString(map, const ['termcode', 'termCode']) != null,
        )
        .toList();
    _logger.debug('[Gateway] 学期原始记录数=${termMaps.length}');
    if (termMaps.isEmpty) {
      return const FailureResult(ParsingFailure('未找到研究生教务学期列表。'));
    }

    final selectedTermMap = _selectScheduleTerm(
      termMaps,
      requestedTermId: termId,
    );
    final termCode = _pickString(selectedTermMap, const [
      'termcode',
      'termCode',
    ]);
    final termName =
        _pickString(selectedTermMap, const ['termname', 'termName', 'name']) ??
        termCode ??
        '当前学期';
    if (termCode == null || termCode.isEmpty) {
      return const FailureResult(ParsingFailure('学期编号解析失败。'));
    }
    _logger.info('[Gateway] 课表目标学期 termCode=$termCode termName=$termName');

    final courseResult = await _portalApi.fetchYjsData(
      session,
      path: '/student/pygl/py_kbcx_ew',
      method: 'POST',
      formFields: {'kblx': 'xs', 'termcode': termCode},
    );
    if (courseResult case FailureResult<dynamic>(failure: final failure)) {
      return FailureResult(failure);
    }

    final studentCardResult = await _portalApi.fetchYjsData(
      session,
      path: '/student/default/getxscardinfo',
      method: 'GET',
      queryParameters: {'_': _nonce()},
    );

    final snapshot = _mapSchedule(
      raw: courseResult.dataOrNull,
      termId: termCode,
      termName: termName,
      availableTerms: _mapTerms(termMaps, selectedTermId: termCode),
      isCurrentTerm: _isSelectedTermCurrent(selectedTermMap),
      currentWeekSource: studentCardResult.dataOrNull,
    );
    if (snapshot.courses.isEmpty) {
      _logger.info('[Gateway] 课表解析完成（课程为空） term=${snapshot.term.name}');
    } else {
      _logger.info(
        '[Gateway] 课表解析完成 term=${snapshot.term.name} currentWeek=${snapshot.currentWeek} '
        'courseCount=${snapshot.courses.length} entryCount=${snapshot.entries.length}',
      );
      _logger.debug(
        '[Gateway] 课表样例=${snapshot.entries.take(5).map((item) => '${item.session.weekdayLabel} ${item.session.startTime}-${item.session.endTime} ${item.course.name}@${item.session.location.fullName}').join(' | ')}',
      );
    }
    return Success(snapshot);
  }

  Future<Result<ScheduleSnapshot>> _fetchUndergradSchedule(
    AppSession session, {
    String? termId,
  }) async {
    final availableTerms = _generateUndergradTerms();
    final selectedTerm = _selectUndergradTerm(
      availableTerms,
      requestedTermId: termId,
    );
    _logger.info(
      '[Gateway] 本科课表目标学期 termId=${selectedTerm.id} termName=${selectedTerm.name}',
    );

    final result = await _portalApi.fetchJxglData(
      session,
      path: '/new/student/xsgrkb/getCalendarWeekDatas',
      formFields: {'xnxqdm': selectedTerm.id, 'zc': '', 'd1': '', 'd2': ''},
    );
    if (result case FailureResult<dynamic>(failure: final failure)) {
      return FailureResult(failure);
    }

    final raw = result.dataOrNull;
    if (raw is Map<String, dynamic>) {
      final authFailure = _extractUndergradJxglAuthFailure(raw);
      if (authFailure != null) {
        _logger.warn('[Gateway] 本科课表教务会话失效 reason=${authFailure.message}');
        return FailureResult(authFailure);
      }
      final code = _pickString(raw, const ['code']);
      if (code != null && code != '0') {
        final msg = _pickString(raw, const ['message', 'msg']) ?? '课表数据获取失败';
        _logger.warn('[Gateway] 本科课表接口返回业务错误 code=$code msg=$msg');
        return Success(
          ScheduleSnapshot(
            term: selectedTerm,
            availableTerms: availableTerms,
            courses: const [],
            fetchedAt: DateTime.now(),
            origin: DataOrigin.remote,
          ),
        );
      }
    }

    List<dynamic>? dataRows;
    if (raw is Map<String, dynamic>) {
      final data = raw['data'];
      if (data is List) {
        dataRows = data;
      }
    }

    if (dataRows == null || dataRows.isEmpty) {
      _logger.info('[Gateway] 本科课表数据为空 term=${selectedTerm.name}');
      return Success(
        ScheduleSnapshot(
          term: selectedTerm,
          availableTerms: availableTerms,
          courses: const [],
          fetchedAt: DateTime.now(),
          origin: DataOrigin.remote,
        ),
      );
    }

    final snapshot = _mapSchedule(
      raw: {'rows': dataRows},
      termId: selectedTerm.id,
      termName: selectedTerm.name,
      availableTerms: availableTerms,
      isCurrentTerm: selectedTerm.isSelected,
      currentWeekSource: null,
    );
    _logger.info(
      '[Gateway] 本科课表解析完成 term=${snapshot.term.name} '
      'courseCount=${snapshot.courses.length} entryCount=${snapshot.entries.length}',
    );
    return Success(snapshot);
  }

  // -------------------- 课表数据 → 领域对象 --------------------

  ScheduleSnapshot _mapSchedule({
    required dynamic raw,
    required String termId,
    required String termName,
    required List<Term> availableTerms,
    required bool isCurrentTerm,
    required dynamic currentWeekSource,
  }) {
    final grouped = <String, List<ClassSession>>{};
    final courseMeta =
        <
          String,
          ({String name, String teacher, String? courseCode, String? note})
        >{};

    final sessions = _parseScheduleSessions(raw);
    for (final session in sessions) {
      grouped.putIfAbsent(session.courseId, () => []);
      grouped[session.courseId]!.add(
        ClassSession(
          dayOfWeek: session.dayOfWeek,
          startTime: session.startTime,
          endTime: session.endTime,
          weekRange: session.weekRange,
          location: session.location,
          teacher: session.teacher,
          startSection: session.startSection,
          endSection: session.endSection,
          weekDescription: session.weekDescription,
          dayLabel: session.dayLabel,
        ),
      );
      courseMeta[session.courseId] = (
        name: session.courseName,
        teacher: session.teacher,
        courseCode: session.courseCode,
        note: session.note,
      );
    }

    final courses = grouped.entries.map((entry) {
      final meta = courseMeta[entry.key]!;
      return Course(
        id: entry.key,
        name: meta.name,
        teacher: meta.teacher,
        courseCode: meta.courseCode,
        note: meta.note,
        sessions: entry.value,
      );
    }).toList();

    return ScheduleSnapshot(
      term: availableTerms.firstWhere(
        (item) => item.id == termId,
        orElse: () =>
            Term(id: termId, name: termName, isSelected: isCurrentTerm),
      ),
      availableTerms: availableTerms,
      currentWeek: isCurrentTerm
          ? _extractCurrentWeek(currentWeekSource)
          : null,
      courses: courses,
      fetchedAt: DateTime.now(),
      origin: DataOrigin.remote,
    );
  }

  List<_ParsedScheduleSession> _parseScheduleSessions(dynamic raw) {
    final flatSessions = _parseFlatScheduleSessions(raw);
    if (flatSessions.isNotEmpty) {
      _logger.debug(
        '[Gateway] 课表解析命中扁平记录结构 sessionCount=${flatSessions.length}',
      );
      return flatSessions;
    }

    final gridSessions = _parseYjsGridScheduleSessions(raw);
    if (gridSessions.isNotEmpty) {
      _logger.debug('[Gateway] 课表解析命中矩阵结构 sessionCount=${gridSessions.length}');
    }
    return gridSessions;
  }

  List<_ParsedScheduleSession> _parseFlatScheduleSessions(dynamic raw) {
    final sessions = <_ParsedScheduleSession>[];

    for (final map in _collectRecordMaps(raw)) {
      final courseName = _pickString(map, const ['kcmc', 'courseName', 'name']);
      final teacher =
          _pickString(map, const ['jsmc', 'teacher', 'jsxm', 'teaxms']) ?? '';
      final courseCode = _pickString(map, const ['kcdm', 'kcbh', 'courseCode']);
      final dayOfWeek = _resolveDayOfWeek(map);
      if (courseName == null || dayOfWeek == null) {
        continue;
      }

      final courseId =
          courseCode ??
          _pickString(map, const ['courseId']) ??
          '$courseName-${teacher.isEmpty ? 'unknown' : teacher}';
      final sectionRange = _resolveSectionRange(map);
      final timeRange = _resolveTimeRange(map, sectionRange);
      final weekRange = _resolveWeekRange(map);

      sessions.add(
        _ParsedScheduleSession(
          courseId: courseId,
          courseName: courseName,
          teacher: teacher,
          courseCode: courseCode,
          note: _pickString(map, const ['bz', 'remark', 'memo']),
          dayOfWeek: dayOfWeek,
          startTime: timeRange.$1,
          endTime: timeRange.$2,
          weekRange: weekRange,
          location: TeachingLocation(
            campus: _pickString(map, const ['xqmc', 'campusName', 'xq']) ?? '',
            building:
                _pickString(map, const ['jxlmc', 'buildingName', 'jxl']) ?? '',
            room: _pickString(map, const ['cdmc', 'roomName', 'jxcdmc']) ?? '',
          ),
          startSection: sectionRange?.$1,
          endSection: sectionRange?.$2,
          weekDescription: _pickString(map, const ['zc', 'weekRange', 'zcsm']),
          dayLabel: _pickString(map, const ['weekdayLabel', 'dayLabel']),
        ),
      );
    }

    return sessions;
  }

  List<_ParsedScheduleSession> _parseYjsGridScheduleSessions(dynamic raw) {
    final rows = switch (raw) {
      {'rows': final List<dynamic> value} =>
        value
            .whereType<Map>()
            .map(
              (item) =>
                  Map<String, dynamic>.from(item.cast<dynamic, dynamic>()),
            )
            .toList(),
      _ => const <Map<String, dynamic>>[],
    };
    if (rows.isEmpty) {
      return const <_ParsedScheduleSession>[];
    }

    final sessions = <_MutableParsedScheduleSession>[];
    for (final row in rows) {
      final section = _pickInt(row, const ['jcid', 'mc']);
      if (section == null) {
        continue;
      }

      for (var dayOfWeek = 1; dayOfWeek <= 7; dayOfWeek++) {
        final cellValue = row['z$dayOfWeek'];
        final rawCell = cellValue?.toString().trim() ?? '';
        if (rawCell.isEmpty) {
          continue;
        }

        final cellCourses = _parseYjsGridCell(rawCell);
        for (final cellCourse in cellCourses) {
          _MutableParsedScheduleSession? matched;
          for (var index = sessions.length - 1; index >= 0; index--) {
            final candidate = sessions[index];
            if (candidate.dayOfWeek == dayOfWeek &&
                candidate.endSection == section - 1 &&
                candidate.courseName == cellCourse.courseName &&
                candidate.teacher == cellCourse.teacher &&
                candidate.location.room == cellCourse.location.room &&
                candidate.weekDescription == cellCourse.weekDescription &&
                candidate.note == cellCourse.note) {
              matched = candidate;
              break;
            }
          }

          if (matched != null) {
            matched.endSection = section;
            matched.endTime = _sectionLabel(section);
            continue;
          }

          sessions.add(
            _MutableParsedScheduleSession(
              courseId:
                  '${cellCourse.courseName}-${cellCourse.teacher.isEmpty ? 'unknown' : cellCourse.teacher}',
              courseName: cellCourse.courseName,
              teacher: cellCourse.teacher,
              courseCode: null,
              note: cellCourse.note,
              dayOfWeek: dayOfWeek,
              startTime: _sectionLabel(section),
              endTime: _sectionLabel(section),
              weekRange: cellCourse.weekRange,
              location: cellCourse.location,
              startSection: section,
              endSection: section,
              weekDescription: cellCourse.weekDescription,
              dayLabel: null,
            ),
          );
        }
      }
    }

    return sessions.map((item) => item.toImmutable()).toList()
      ..sort((left, right) {
        final byDay = left.dayOfWeek.compareTo(right.dayOfWeek);
        if (byDay != 0) {
          return byDay;
        }
        final leftSection = left.startSection ?? 0;
        final rightSection = right.startSection ?? 0;
        return leftSection.compareTo(rightSection);
      });
  }

  List<_ParsedYjsGridCellCourse> _parseYjsGridCell(String rawCell) {
    final normalized = rawCell
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '\n')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('\r', '');
    final lines = normalized
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && line.toLowerCase() != 'null')
        .toList();
    if (lines.isEmpty) {
      return const <_ParsedYjsGridCellCourse>[];
    }

    final courses = <_ParsedYjsGridCellCourse>[];
    var index = 0;
    while (index < lines.length) {
      final courseName = lines[index++].trim();
      if (courseName.isEmpty || _looksLikeWeekLine(courseName)) {
        continue;
      }

      String? note;
      if (index < lines.length && !_looksLikeWeekLine(lines[index])) {
        note = lines[index++].trim();
      }

      if (index >= lines.length || !_looksLikeWeekLine(lines[index])) {
        continue;
      }
      final weekDescription = lines[index++].trim();
      final weekRange = _weekRangeFromText(weekDescription);
      if (weekRange == null) {
        continue;
      }

      final teacherAndLocation =
          index < lines.length ? lines[index++].trim() : '';
      final parsedTeacherAndLocation = _parseTeacherAndLocation(
        teacherAndLocation,
      );

      courses.add(
        _ParsedYjsGridCellCourse(
          courseName: courseName,
          teacher: parsedTeacherAndLocation.teacher,
          location: parsedTeacherAndLocation.location,
          weekRange: weekRange,
          weekDescription: weekDescription
              .replaceAll('[', '')
              .replaceAll(']', ''),
          note: note,
        ),
      );
    }

    return courses;
  }

  bool _looksLikeWeekLine(String value) {
    return value.contains('周');
  }

  WeekRange? _weekRangeFromText(String? raw) {
    if (raw == null) {
      return null;
    }
    final normalized = raw.replaceAll('[', '').replaceAll(']', '').trim();
    final rangeMatch = RegExp(r'(\d+)\D+(\d+)\s*周?').firstMatch(normalized);
    if (rangeMatch != null) {
      return WeekRange(
        startWeek: int.parse(rangeMatch.group(1)!),
        endWeek: int.parse(rangeMatch.group(2)!),
      );
    }

    final singleMatch = RegExp(r'(\d+)\s*周?').firstMatch(normalized);
    if (singleMatch != null) {
      final week = int.parse(singleMatch.group(1)!);
      return WeekRange(startWeek: week, endWeek: week);
    }

    return null;
  }

  ({String teacher, TeachingLocation location}) _parseTeacherAndLocation(
    String raw,
  ) {
    final match = RegExp(r'^(.+?)\[(.+?)\]$').firstMatch(raw.trim());
    if (match == null) {
      return (
        teacher: raw.trim(),
        location: const TeachingLocation(campus: '', building: '', room: ''),
      );
    }

    return (
      teacher: match.group(1)!.trim(),
      location: TeachingLocation(
        campus: '',
        building: '',
        room: match.group(2)!.trim(),
      ),
    );
  }

  String _sectionLabel(int section) => '第$section节';

  int? _extractCurrentWeek(dynamic raw) {
    for (final map in _collectRecordMaps(raw)) {
      final week = _pickInt(map, const [
        'dqzc',
        'dqszc',
        'week',
        'currentWeek',
      ]);
      if (week != null) {
        return week;
      }
    }
    return null;
  }

  int? _resolveDayOfWeek(Map<String, dynamic> map) {
    final raw = _pickString(map, const ['xq', 'skxq', 'dayOfWeek', 'weekday']);
    if (raw == null) {
      return null;
    }

    final number = int.tryParse(raw);
    if (number != null && number >= 1 && number <= 7) {
      return number;
    }

    const labels = {
      '一': 1,
      '二': 2,
      '三': 3,
      '四': 4,
      '五': 5,
      '六': 6,
      '日': 7,
      '天': 7,
    };
    for (final entry in labels.entries) {
      if (raw.contains(entry.key)) {
        return entry.value;
      }
    }
    return null;
  }

  (int, int)? _resolveSectionRange(Map<String, dynamic> map) {
    final start = _pickInt(map, const ['ksjc', 'startSection', 'ps']);
    final end = _pickInt(map, const ['jsjc', 'endSection', 'pe']);
    if (start != null && end != null) {
      return (start, end);
    }

    final raw = _pickString(map, const ['jcs', 'jc', 'sectionRange']);
    if (raw == null) {
      return null;
    }

    final match = RegExp(r'(\d+)\D+(\d+)').firstMatch(raw);
    if (match != null) {
      return (int.parse(match.group(1)!), int.parse(match.group(2)!));
    }

    final single = int.tryParse(raw);
    return single == null ? null : (single, single);
  }

  (String, String) _resolveTimeRange(
    Map<String, dynamic> map,
    (int, int)? sectionRange,
  ) {
    final startTime = _pickString(map, const ['kssj', 'startTime']);
    final endTime = _pickString(map, const ['jssj', 'endTime']);
    if (startTime != null && endTime != null) {
      return (startTime, endTime);
    }

    if (sectionRange != null) {
      return ('第${sectionRange.$1}节', '第${sectionRange.$2}节');
    }

    return ('待定', '待定');
  }

  WeekRange _resolveWeekRange(Map<String, dynamic> map) {
    final start = _pickInt(map, const ['ksz', 'startWeek']);
    final end = _pickInt(map, const ['jsz', 'endWeek']);
    if (start != null && end != null) {
      return WeekRange(startWeek: start, endWeek: end);
    }

    final raw = _pickString(map, const ['zc', 'weekRange', 'zcsm']);
    if (raw != null) {
      // Try comma-separated weeks like "9,6,7,8"
      if (raw.contains(',') && !raw.contains('-')) {
        final parts = raw
            .split(',')
            .map((s) => int.tryParse(s.trim()))
            .whereType<int>()
            .toList();
        if (parts.isNotEmpty) {
          return WeekRange(
            startWeek: parts.reduce((a, b) => a < b ? a : b),
            endWeek: parts.reduce((a, b) => a > b ? a : b),
          );
        }
      }

      final match = RegExp(r'(\d+)\D+(\d+)').firstMatch(raw);
      if (match != null) {
        return WeekRange(
          startWeek: int.parse(match.group(1)!),
          endWeek: int.parse(match.group(2)!),
        );
      }
      final single = int.tryParse(raw);
      if (single != null) {
        return WeekRange(startWeek: single, endWeek: single);
      }
    }

    return const WeekRange(startWeek: 1, endWeek: 20);
  }
}
