// 考试安排：本科 jxgl 单接口 + 服务端字段重组，研究生 yjsc bindterm + kckccx_list。
part of '../school_portal_gateway.dart';

mixin _ExamsGateway on _GatewayBase implements SchoolPortalGateway {
  @override
  Future<Result<ExamScheduleSnapshot>> fetchExamSchedule(
    AppSession session, {
    String? termId,
  }) async {
    _logger.info('[Gateway] 开始加载考试安排 userId=${session.userId} termId=$termId');
    final validation = await validateSession(session);
    if (validation.isFailure) {
      _logger.warn('[Gateway] 考试安排加载前 session 校验失败');
      return FailureResult(validation.failureOrNull!);
    }

    if (session.isUndergraduate) {
      return _fetchUndergradExamSchedule(session, termId: termId);
    }

    // 1. 获取学期列表
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
    _logger.debug('[Gateway] 考试-学期原始记录数=${termMaps.length}');
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
    _logger.info('[Gateway] 考试目标学期 termCode=$termCode termName=$termName');

    // 2. 获取考试安排
    final result = await _portalApi.fetchYjsData(
      session,
      path: '/student/pygl/kckccx_list',
      method: 'POST',
      formFields: {'termcode': termCode},
    );
    if (result case FailureResult<dynamic>(failure: final failure)) {
      return FailureResult(failure);
    }

    final records = _collectRecordMaps(
      result.dataOrNull,
    ).map(_mapExamRecord).whereType<ExamRecord>().toList();
    _logger.debug(
      '[Gateway] 考试原始展开记录数=${_collectRecordMaps(result.dataOrNull).length}',
    );

    final availableTerms = _mapTerms(termMaps, selectedTermId: termCode);
    _logger.info('[Gateway] 考试安排解析完成 recordCount=${records.length}');
    _logger.debug(
      '[Gateway] 考试样例=${records.take(5).map((item) => '${item.courseName}:${item.dateLabel} ${item.timeLabel} ${item.location}').join(' | ')}',
    );
    return Success(
      ExamScheduleSnapshot(
        term: availableTerms.firstWhere(
          (item) => item.id == termCode,
          orElse: () => Term(
            id: termCode,
            name: termName,
            isSelected: _isSelectedTermCurrent(selectedTermMap),
          ),
        ),
        availableTerms: availableTerms,
        records: records,
        fetchedAt: DateTime.now(),
        origin: DataOrigin.remote,
      ),
    );
  }

  Future<Result<ExamScheduleSnapshot>> _fetchUndergradExamSchedule(
    AppSession session, {
    String? termId,
  }) async {
    final availableTerms = _generateUndergradTerms();
    final selectedTerm = _selectUndergradTerm(
      availableTerms,
      requestedTermId: termId,
    );

    final formFields = <String, dynamic>{
      'page': '1',
      'rows': '100',
      'sort': 'xsxm',
      'order': 'asc',
    };
    if (selectedTerm.id.isNotEmpty) {
      formFields['xnxqdm'] = selectedTerm.id;
    }

    final result = await _portalApi.fetchJxglData(
      session,
      path: '/new/student/xsksrw/paginateXsksrw',
      formFields: formFields,
    );
    if (result case FailureResult<dynamic>(failure: final failure)) {
      return FailureResult(failure);
    }

    final raw = result.dataOrNull;
    if (raw is! Map<String, dynamic>) {
      return const FailureResult(ParsingFailure('本科考试数据格式异常。'));
    }
    final authFailure = _extractUndergradJxglAuthFailure(raw);
    if (authFailure != null) {
      _logger.warn('[Gateway] 本科考试教务会话失效 reason=${authFailure.message}');
      return FailureResult(authFailure);
    }
    final rows = raw['rows'];
    if (rows is! List) {
      return const FailureResult(ParsingFailure('本科考试数据为空。'));
    }

    final processedRows = rows.whereType<Map>().map((m) {
      final map = Map<String, dynamic>.from(m.cast<dynamic, dynamic>());

      final kssj = _pickString(map, const ['kssj']);
      if (kssj != null && kssj.contains('--')) {
        final parts = kssj.split('--');
        if (parts.length == 2) {
          map['startTime'] = _trimSeconds(parts[0].trim());
          map['endTime'] = _trimSeconds(parts[1].trim());
        }
      }

      final assessmentForm = _pickString(map, const ['khxsmc']);
      if (assessmentForm != null && assessmentForm.isNotEmpty) {
        map['assessmentForm'] = assessmentForm;
      }

      final examPaperMode = _pickString(map, const ['ksxsmc']);
      if (examPaperMode != null && examPaperMode.isNotEmpty) {
        map['examPaperMode'] = examPaperMode;
      }

      final examCategory = _pickString(map, const ['kslbmc']);
      if (examCategory != null && examCategory.isNotEmpty) {
        map['examCategory'] = examCategory;
      }

      final examMethodParts = <String>[
        if (assessmentForm != null && assessmentForm.isNotEmpty) assessmentForm,
        if (examPaperMode != null && examPaperMode.isNotEmpty) examPaperMode,
      ];
      if (examMethodParts.isNotEmpty) {
        map['examMethod'] = examMethodParts.join(' · ');
      } else if (examCategory != null && examCategory.isNotEmpty) {
        map['examMethod'] = examCategory;
      }

      final teacher = _pickString(map, const ['jkteaxms']);
      if (teacher != null && teacher.isNotEmpty) {
        final teachers = _splitDisplayValues(teacher);
        if (teachers.isNotEmpty) {
          map['teacher'] = teachers.first;
          if (teachers.length > 1) {
            map['assistantTeacher'] = teachers.skip(1).join('、');
          }
        }
      }

      final zwh = _pickString(map, const ['zwh']);
      if (zwh != null && zwh.isNotEmpty) {
        map['seatNumber'] = zwh;
      }

      final candidateCount = _pickString(map, const ['ksrs', 'xs']);
      if (candidateCount != null && candidateCount.isNotEmpty) {
        map['candidateCount'] = candidateCount;
      }

      final locationParts = <String>[
        if (_pickString(map, const ['xqmc']) case final String campus) campus,
        if (_pickString(map, const ['kscdmc']) case final String room) room,
      ];
      if (locationParts.isNotEmpty) {
        map['location'] = locationParts.join(' · ');
      }

      final remark = _pickString(map, const ['bz']);
      if (remark != null && remark.isNotEmpty) {
        map['remark'] = remark;
      }

      return map;
    }).toList();

    final records = processedRows
        .map(_mapExamRecord)
        .whereType<ExamRecord>()
        .toList();

    _logger.info('[Gateway] 本科考试安排解析完成 recordCount=${records.length}');
    return Success(
      ExamScheduleSnapshot(
        term: selectedTerm,
        availableTerms: availableTerms,
        records: records,
        fetchedAt: DateTime.now(),
        origin: DataOrigin.remote,
      ),
    );
  }

  ExamRecord? _mapExamRecord(Map<String, dynamic> map) {
    final courseName = _pickString(map, const ['kcmc', 'courseName', 'name']);
    if (courseName == null) {
      return null;
    }

    final dateLabel =
        _pickString(map, const ['ksrq', 'date', 'examDate']) ?? '日期待定';
    final startTime = _pickString(map, const ['startTime', 'kssj']);
    final endTime = _pickString(map, const ['endTime', 'jssj']);
    final timeLabel = switch ((startTime, endTime)) {
      (final String start?, final String end?) => '$start-$end',
      (final String start?, _) => start,
      _ => _pickString(map, const ['sjdmc', 'timeLabel']) ?? '时间待定',
    };
    final locationParts = <String>[];
    for (final value in [
      _pickString(map, const ['location', 'dz', 'ksdd', 'kscdmc', 'address']),
      _pickString(map, const ['jsmc', 'roomName']),
    ]) {
      if (value == null || value.isEmpty || locationParts.contains(value)) {
        continue;
      }
      locationParts.add(value);
    }
    final location = locationParts.join(' ');

    return ExamRecord(
      courseName: courseName,
      dateLabel: dateLabel,
      timeLabel: timeLabel,
      location: location.isEmpty ? '地点待定' : location,
      courseCode: _pickString(map, const ['kcbh', 'courseCode']),
      className: _pickString(map, const ['bjmc', 'className']),
      examMethod: _pickString(map, const ['examMethod', 'khxs', 'examType']),
      primaryTeacher: _pickString(map, const ['zjjs', 'teacher']),
      assistantTeacher: _pickString(map, const ['assistantTeacher', 'fjjs']),
      candidateCount: _pickString(map, const ['ksrs', 'candidateCount']),
      seatNumber: _pickString(map, const ['zwh', 'seatNo', 'seatNumber']),
      remark: _pickString(map, const ['bz', 'remark', 'memo']),
      assessmentForm: _pickString(map, const ['assessmentForm']),
      examPaperMode: _pickString(map, const ['examPaperMode']),
      examCategory: _pickString(map, const ['examCategory']),
    );
  }

  List<String> _splitDisplayValues(String raw) {
    return raw
        .split(RegExp(r'[、,，/]'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  String _trimSeconds(String time) {
    // "10:30:00" → "10:30"
    final match = RegExp(r'^(\d{1,2}:\d{2}):\d{2}$').firstMatch(time);
    return match != null ? match.group(1)! : time;
  }
}
