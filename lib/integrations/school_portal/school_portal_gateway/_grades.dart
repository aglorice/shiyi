// 成绩：本科走 jxgl 单接口，研究生走 yjsc bindterm + xscjcx_list。
part of '../school_portal_gateway.dart';

mixin _GradesGateway on _GatewayBase implements SchoolPortalGateway {
  @override
  Future<Result<GradesSnapshot>> fetchGrades(
    AppSession session, {
    String? termId,
  }) async {
    _logger.info('[Gateway] 开始加载成绩 userId=${session.userId} termId=$termId');
    final validation = await validateSession(session);
    if (validation.isFailure) {
      _logger.warn('[Gateway] 成绩加载前 session 校验失败');
      return FailureResult(validation.failureOrNull!);
    }

    if (session.isUndergraduate) {
      return _fetchUndergradGrades(session, termId: termId);
    }

    var selectedTermId = '';
    Term? selectedTerm;
    var availableTerms = const <Term>[];
    final termsResult = await _portalApi.fetchYjsData(
      session,
      path: '/student/default/bindterm',
      method: 'GET',
      queryParameters: {'_': _nonce()},
    );
    if (termsResult case Success<dynamic>(data: final data)) {
      final termMaps = _collectRecordMaps(data)
          .where(
            (map) => _pickString(map, const ['termcode', 'termCode']) != null,
          )
          .toList();
      if (termMaps.isNotEmpty) {
        final selectedTermMap = _isAllTermsSelection(termId)
            ? null
            : _selectScheduleTerm(termMaps, requestedTermId: termId);
        selectedTermId = selectedTermMap == null
            ? ''
            : _pickString(selectedTermMap, const ['termcode', 'termCode']) ??
                  '';
        availableTerms = _mapTerms(termMaps, selectedTermId: selectedTermId);
        if (selectedTermMap != null && selectedTermId.isNotEmpty) {
          selectedTerm = availableTerms.firstWhere(
            (item) => item.id == selectedTermId,
            orElse: () => Term(
              id: selectedTermId,
              name:
                  _pickString(selectedTermMap, const [
                    'termname',
                    'termName',
                    'name',
                  ]) ??
                  selectedTermId,
              isSelected: _isSelectedTermCurrent(selectedTermMap),
            ),
          );
        }
        _logger.debug('[Gateway] 成绩-学期原始记录数=${termMaps.length}');
      }
    } else {
      _logger.warn('[Gateway] 成绩学期列表获取失败，回退到成绩记录内的学期标签');
    }

    final result = await _portalApi.fetchYjsData(
      session,
      path: '/student/pygl/xscjcx_list',
      method: 'GET',
      queryParameters: {'_': _nonce()},
    );
    if (result case FailureResult<dynamic>(failure: final failure)) {
      return FailureResult(failure);
    }

    final allRecords = _collectRecordMaps(
      result.dataOrNull,
    ).map(_mapGradeRecord).whereType<GradeRecord>().toList();
    _logger.debug(
      '[Gateway] 成绩原始展开记录数=${_collectRecordMaps(result.dataOrNull).length}',
    );
    if (allRecords.isEmpty) {
      return const FailureResult(ParsingFailure('未解析到成绩记录。'));
    }
    final records = selectedTerm == null
        ? allRecords
        : allRecords
              .where(
                (item) => GradesSnapshot.matchesTermName(
                  item.termName,
                  selectedTerm!.name,
                ),
              )
              .toList();

    _logger.info(
      '[Gateway] 成绩解析完成 recordCount=${records.length} '
      'selectedTerm=${selectedTerm?.name ?? '全部学期'} '
      'terms=${allRecords.map((item) => item.termName).toSet().join(' | ')}',
    );
    _logger.debug(
      '[Gateway] 成绩样例=${allRecords.take(5).map((item) => '${item.termName}:${item.courseName}=${item.grade}').join(' | ')}',
    );
    return Success(
      GradesSnapshot(
        records: records,
        availableTerms: availableTerms,
        fetchedAt: DateTime.now(),
        origin: DataOrigin.remote,
        selectedTerm: selectedTerm,
      ),
    );
  }

  Future<Result<GradesSnapshot>> _fetchUndergradGrades(
    AppSession session, {
    String? termId,
  }) async {
    final availableTerms = _generateUndergradTerms();
    final selectedTerm = _isAllTermsSelection(termId)
        ? null
        : _selectUndergradTerm(availableTerms, requestedTermId: termId);
    _logger.info(
      '[Gateway] 本科成绩目标学期 termId=${selectedTerm?.id ?? 'ALL'} '
      'termName=${selectedTerm?.name ?? '全部学期'}',
    );

    final formFields = <String, dynamic>{
      'source': 'kccjlist',
      'page': '1',
      'rows': '100',
      'sort': 'xnxqdm,kcmc',
      'order': 'asc',
    };
    if (selectedTerm != null && selectedTerm.id.isNotEmpty) {
      formFields['xnxqdm'] = selectedTerm.id;
    }

    final result = await _portalApi.fetchJxglData(
      session,
      path: '/new/student/xskccj/kccjDatas',
      formFields: formFields,
    );
    if (result case FailureResult<dynamic>(failure: final failure)) {
      return FailureResult(failure);
    }

    final raw = result.dataOrNull;
    if (raw is! Map<String, dynamic>) {
      return const FailureResult(ParsingFailure('本科成绩数据格式异常。'));
    }
    final authFailure = _extractUndergradJxglAuthFailure(raw);
    if (authFailure != null) {
      _logger.warn('[Gateway] 本科成绩教务会话失效 reason=${authFailure.message}');
      return FailureResult(authFailure);
    }
    final rows = raw['rows'];
    if (rows is! List) {
      return const FailureResult(ParsingFailure('本科成绩数据为空。'));
    }

    final records = rows
        .whereType<Map>()
        .map(
          (m) => _mapGradeRecord(
            Map<String, dynamic>.from(m.cast<dynamic, dynamic>()),
          ),
        )
        .whereType<GradeRecord>()
        .toList();

    _logger.info(
      '[Gateway] 本科成绩解析完成 recordCount=${records.length} '
      'selectedTerm=${selectedTerm?.name ?? '全部学期'} '
      'terms=${records.map((item) => item.termName).toSet().join(' | ')}',
    );
    return Success(
      GradesSnapshot(
        records: records,
        availableTerms: availableTerms,
        fetchedAt: DateTime.now(),
        origin: DataOrigin.remote,
        selectedTerm: selectedTerm,
      ),
    );
  }

  GradeRecord? _mapGradeRecord(Map<String, dynamic> map) {
    final courseName = _pickString(map, const ['kcmc', 'courseName', 'name']);
    final grade = _pickString(map, const [
      'cj',
      'zcj',
      'zpcj',
      'score',
      'grade',
      'cjmsz',
    ]);
    if (courseName == null || grade == null) {
      return null;
    }

    return GradeRecord(
      courseName: courseName,
      termName:
          _pickString(map, const [
            'kkxq',
            'termname',
            'xqmc',
            'xnxqmc',
            'termName',
          ]) ??
          _formatUndergradTermName(_pickString(map, const ['xnxqdm'])) ??
          '未分学期',
      grade: grade,
      courseCode: _pickString(map, const ['kcbh', 'kcdm', 'courseCode']),
      credit: _pickDouble(map, const ['kcxf', 'xf', 'credit']),
      gradePoint: _pickDouble(map, const ['jd', 'cjjd', 'gradePoint']),
      assessmentMethod: _pickString(map, const [
        'khfs',
        'ksxz',
        'khfsmc',
        'assessment',
      ]),
      teacher: _pickString(map, const ['rkjs', 'jsmc', 'teacher']),
      classHours: _pickString(map, const ['xs', 'classHours']),
    );
  }
}
