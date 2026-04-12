import 'dart:convert';
import 'dart:math';

import '../../core/error/failure.dart';
import '../../core/logging/app_logger.dart';
import '../../core/models/data_origin.dart';
import '../../core/result/result.dart';
import '../../modules/auth/domain/entities/app_session.dart';
import '../../modules/auth/domain/entities/school_credential.dart';
import '../../modules/electricity/domain/entities/electricity_dashboard.dart';
import '../../modules/exams/domain/entities/exam_schedule_snapshot.dart';
import '../../modules/grades/domain/entities/grades_snapshot.dart';
import '../../modules/gym_booking/domain/entities/appointment_detail.dart';
import '../../modules/gym_booking/domain/entities/gym_appointment_page.dart';
import '../../modules/gym_booking/domain/entities/gym_booking_overview.dart';
import '../../modules/gym_booking/domain/entities/gym_search_filter.dart';
import '../../modules/gym_booking/domain/entities/gym_venue_search_page.dart';
import '../../modules/gym_booking/domain/entities/venue_detail.dart';
import '../../modules/gym_booking/domain/entities/venue_review.dart';
import '../../modules/schedule/domain/entities/schedule_snapshot.dart';
import '../../modules/services/domain/entities/service_card_data.dart';
import '../../modules/services/domain/entities/service_launch_data.dart';
import 'sso/session_validator.dart';
import 'sso/sso_login_orchestrator.dart';
import 'wyu_portal_api.dart';

abstract class SchoolPortalGateway {
  Future<Result<AppSession>> login(SchoolCredential credential);
  Future<Result<AppSession>> refreshSession(SchoolCredential credential);
  Future<Result<void>> validateSession(AppSession session);
  Future<Result<ScheduleSnapshot>> fetchSchedule(
    AppSession session, {
    String? termId,
  });
  Future<Result<GradesSnapshot>> fetchGrades(
    AppSession session, {
    String? termId,
  });
  Future<Result<ExamScheduleSnapshot>> fetchExamSchedule(
    AppSession session, {
    String? termId,
  });
  Future<Result<ElectricityDashboard>> fetchElectricityDashboard(
    AppSession session,
  );
  Future<Result<GymBookingOverview>> fetchGymBookingOverview(
    AppSession session, {
    required DateTime date,
  });
  Future<Result<BookingRecord>> submitGymBooking(
    AppSession session, {
    required BookingDraft draft,
  });
  Future<Result<GymBookingEligibility>> checkGymBookingEligibility(
    AppSession session, {
    required BookingDraft draft,
  });
  Future<Result<List<BookingRecord>>> fetchMyGymAppointments(
    AppSession session, {
    int page = 1,
    int pageSize = 20,
  });
  Future<Result<GymAppointmentPage>> fetchMyGymAppointmentsPage(
    AppSession session, {
    required GymAppointmentQuery query,
  });

  Future<Result<GymVenueSearchPage>> searchGymVenues(
    AppSession session, {
    required GymVenueSearchQuery query,
  });

  Future<Result<AppointmentDetail>> fetchGymAppointmentDetail(
    AppSession session, {
    required String wid,
  });

  Future<Result<void>> cancelGymAppointment(
    AppSession session, {
    required String appointmentId,
    String? reason,
  });

  Future<Result<VenueDetail>> fetchGymRoomDetail(
    AppSession session, {
    required String wid,
  });

  Future<Result<VenueReviewPage>> fetchGymRoomReviews(
    AppSession session, {
    required String bizWid,
    int page = 1,
    int pageSize = 10,
  });

  Future<Result<GymSearchModel>> fetchGymSearchModel(AppSession session);
  Future<Result<List<ServiceCardGroup>>> fetchServiceCards(AppSession session);
  Future<Result<List<ServiceItem>>> fetchServiceCategoryItems(
    AppSession session, {
    required String cardWid,
    required ServiceCategory category,
  });
  Future<Result<ServiceLaunchData>> prepareServiceLaunch(
    AppSession session, {
    required ServiceItem item,
  });
}

class WyuSchoolPortalGateway implements SchoolPortalGateway {
  WyuSchoolPortalGateway({
    required SsoLoginOrchestrator loginOrchestrator,
    required SessionValidator sessionValidator,
    required WyuPortalApi portalApi,
    required AppLogger logger,
  }) : _loginOrchestrator = loginOrchestrator,
       _sessionValidator = sessionValidator,
       _portalApi = portalApi,
       _logger = logger;

  final SsoLoginOrchestrator _loginOrchestrator;
  final SessionValidator _sessionValidator;
  final WyuPortalApi _portalApi;
  final AppLogger _logger;
  final Random _random = Random();

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
    if (snapshot != null) {
      _logger.info(
        '[Gateway] 课表解析完成 term=${snapshot.term.name} currentWeek=${snapshot.currentWeek} '
        'courseCount=${snapshot.courses.length} entryCount=${snapshot.entries.length}',
      );
      _logger.debug(
        '[Gateway] 课表样例=${snapshot.entries.take(5).map((item) => '${item.session.weekdayLabel} ${item.session.startTime}-${item.session.endTime} ${item.course.name}@${item.session.location.fullName}').join(' | ')}',
      );
    } else {
      _logger.warn('[Gateway] 课表解析结果为空');
    }
    return snapshot == null
        ? const FailureResult(ParsingFailure('课表数据解析失败。'))
        : Success(snapshot);
  }

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

  @override
  Future<Result<ElectricityDashboard>> fetchElectricityDashboard(
    AppSession session,
  ) async {
    return const FailureResult(BusinessFailure('电费查询将在后续接入。'));
  }

  @override
  Future<Result<GymBookingOverview>> fetchGymBookingOverview(
    AppSession session, {
    required DateTime date,
  }) async {
    _logger.info('[Gateway] 开始加载场馆预约 userId=${session.userId} date=$date');
    final validation = await validateSession(session);
    if (validation.isFailure) {
      _logger.warn('[Gateway] 场馆预约加载前 session 校验失败');
      return FailureResult(validation.failureOrNull!);
    }

    final today = _normalizeDate(DateTime.now());
    final weekday = today.weekday; // Monday=1, Sunday=7
    final weekMonday = today.subtract(Duration(days: weekday - 1));
    final weekSunday = weekMonday.add(const Duration(days: 6));

    final beginDate = _formatDate(weekMonday);
    final endDate = _formatDate(weekSunday);

    final roomResult = await _portalApi.fetchGymData(
      session,
      path: '/modules/application/getOpeningRoom.do',
      formFields: {
        'BEGIN': beginDate,
        'END': endDate,
        'querySetting': '[]',
        'pageSize': '100',
        'pageNumber': '1',
      },
    );
    if (roomResult case FailureResult<dynamic>(failure: final failure)) {
      return FailureResult(failure);
    }

    final parsed = _parseGymRoomData(roomResult.dataOrNull, targetDate: date);
    if (parsed == null) {
      return const FailureResult(ParsingFailure('场馆数据解析失败。'));
    }

    final recordsResult = await _portalApi.fetchGymData(
      session,
      path: '/modules/myApplication/getMyAppointmentListData.do',
      formFields: {'pageSize': '50', 'pageNumber': '1'},
    );
    final records = _parseGymAppointmentRecords(recordsResult.dataOrNull);

    _logger.info(
      '[Gateway] 场馆预约加载完成 venueCount=${parsed.venues.length} '
      'slotCount=${parsed.slotsByVenue.values.fold<int>(0, (s, l) => s + l.length)} '
      'recordCount=${records.length}',
    );

    return Success(parsed.copyWith(records: records));
  }

  @override
  Future<Result<GymVenueSearchPage>> searchGymVenues(
    AppSession session, {
    required GymVenueSearchQuery query,
  }) async {
    _logger.info(
      '[Gateway] 搜索场馆 userId=${session.userId} '
      'date=${query.date} page=${query.pageNumber} keyword=${query.keyword}',
    );
    final validation = await validateSession(session);
    if (validation.isFailure) {
      return FailureResult(validation.failureOrNull!);
    }

    final formFields = <String, dynamic>{
      'BEGIN': _formatDate(query.date),
      'END': _formatDate(query.date),
      'pageSize': '${query.pageSize}',
      'pageNumber': '${query.pageNumber}',
    };
    if (query.venueId != null && query.venueId!.isNotEmpty) {
      formFields['WID'] = query.venueId!;
    }

    final querySetting = _buildVenueQuerySetting(query);
    if (querySetting != null) {
      formFields['querySetting'] = jsonEncode(querySetting);
    }

    final result = await _portalApi.fetchGymData(
      session,
      path: '/modules/application/getOpeningRoom.do',
      formFields: formFields,
    );
    if (result case FailureResult<dynamic>(failure: final failure)) {
      return FailureResult(failure);
    }

    final page = _parseGymVenueSearchPage(result.dataOrNull, query: query);
    if (page == null) {
      return const FailureResult(ParsingFailure('场馆搜索结果解析失败。'));
    }

    _logger.info(
      '[Gateway] 场馆搜索完成 page=${page.query.pageNumber} '
      'count=${page.venues.length} total=${page.totalSize}',
    );
    return Success(page);
  }

  @override
  Future<Result<BookingRecord>> submitGymBooking(
    AppSession session, {
    required BookingDraft draft,
  }) async {
    _logger.info(
      '[Gateway] 提交场馆预约 userId=${session.userId} '
      'venue=${draft.venue.name} date=${draft.date} '
      'slot=${draft.slot.timeLabel}',
    );
    final validation = await validateSession(session);
    if (validation.isFailure) {
      return FailureResult(validation.failureOrNull!);
    }

    final formData = _buildGymApplyFormData(draft);
    final eligibilityResult = await checkGymBookingEligibility(
      session,
      draft: draft,
    );
    if (eligibilityResult case FailureResult<GymBookingEligibility>(
      failure: final failure,
    )) {
      return FailureResult(failure);
    }
    if (eligibilityResult.dataOrNull?.canApply != true) {
      return FailureResult(
        BusinessFailure(eligibilityResult.dataOrNull?.message ?? '预约校验未通过。'),
      );
    }

    final startFlowResult = await _portalApi.fetchGymData(
      session,
      path: '/sys/emapflow/tasks/startFlow.do',
      formFields: {
        'formData': jsonEncode(formData),
        'id': 'start',
        'sendMessage': 'true',
        'commandType': 'start',
        'execute': 'do_start',
        'name': '提交',
        'commandEvent':
            'com.wisedu.emap.lwWiseduCgyy.service.Impl.ApplyCheckFlowService',
        'url': '/sys/emapflow/tasks/startFlow.do',
        'buttonType': 'success',
        'taskId': '',
        'defKey': 'lwWiseduCgyy.MainFlow',
      },
    );
    if (startFlowResult case FailureResult<dynamic>(failure: final failure)) {
      return FailureResult(failure);
    }

    final submitData = startFlowResult.dataOrNull;
    if (submitData is Map<String, dynamic>) {
      final succeed = submitData['succeed'];
      if (succeed == false || succeed == 'false') {
        final msg =
            _pickString(submitData, const ['msg', 'message']) ?? '预约提交失败。';
        return FailureResult(BusinessFailure(msg));
      }
    }

    _logger.info('[Gateway] 场馆预约提交成功 venue=${draft.venue.name}');

    final refreshedRecords = await fetchMyGymAppointments(
      session,
      page: 1,
      pageSize: 20,
    );
    if (refreshedRecords case Success<List<BookingRecord>>(
      data: final records,
    )) {
      for (final record in records) {
        if (record.venueName == draft.venue.name &&
            record.slotLabel == draft.slot.timeLabel &&
            _normalizeDate(record.date) == _normalizeDate(draft.date)) {
          return Success(record);
        }
      }
    }

    return Success(
      BookingRecord(
        id: draft.venue.id,
        venueName: draft.venue.name,
        slotLabel: draft.slot.timeLabel,
        date: draft.date,
        status: '未使用',
        statusCode: '001',
        canCancel: true,
      ),
    );
  }

  @override
  Future<Result<GymBookingEligibility>> checkGymBookingEligibility(
    AppSession session, {
    required BookingDraft draft,
  }) async {
    final checkResult = await _portalApi.fetchGymData(
      session,
      path: '/modules/application/checkCanApply.do',
      formFields: _buildGymApplyFormData(draft),
    );
    if (checkResult case FailureResult<dynamic>(failure: final failure)) {
      return FailureResult(failure);
    }

    return _parseGymEligibility(checkResult.dataOrNull);
  }

  @override
  Future<Result<List<BookingRecord>>> fetchMyGymAppointments(
    AppSession session, {
    int page = 1,
    int pageSize = 20,
  }) async {
    final pageResult = await fetchMyGymAppointmentsPage(
      session,
      query: GymAppointmentQuery(pageNumber: page, pageSize: pageSize),
    );
    if (pageResult case Success<GymAppointmentPage>(data: final resultPage)) {
      return Success(resultPage.records);
    }
    return FailureResult(pageResult.failureOrNull!);
  }

  @override
  Future<Result<GymAppointmentPage>> fetchMyGymAppointmentsPage(
    AppSession session, {
    required GymAppointmentQuery query,
  }) async {
    _logger.info(
      '[Gateway] 加载我的场馆预约 userId=${session.userId} page=${query.pageNumber}',
    );
    final validation = await validateSession(session);
    if (validation.isFailure) {
      return FailureResult(validation.failureOrNull!);
    }

    final formFields = <String, dynamic>{
      'pageSize': '${query.pageSize}',
      'pageNumber': '${query.pageNumber}',
    };
    final querySetting = _buildAppointmentQuerySetting(query);
    if (querySetting != null) {
      formFields['querySetting'] = jsonEncode(querySetting);
    }

    final result = await _portalApi.fetchGymData(
      session,
      path: '/modules/myApplication/getMyAppointmentListData.do',
      formFields: formFields,
    );
    if (result case FailureResult<dynamic>(failure: final failure)) {
      return FailureResult(failure);
    }

    final records = _parseGymAppointmentRecords(result.dataOrNull);
    final paging = _extractPagingInfo(
      result.dataOrNull,
      dataKey: 'getMyAppointmentListData',
    );
    final pageData = GymAppointmentPage(
      query: query,
      records: records,
      totalSize: paging.totalSize,
      fetchedAt: DateTime.now(),
      origin: DataOrigin.remote,
    );
    _logger.info(
      '[Gateway] 我的场馆预约加载完成 count=${records.length} total=${paging.totalSize}',
    );
    return Success(pageData);
  }

  @override
  Future<Result<AppointmentDetail>> fetchGymAppointmentDetail(
    AppSession session, {
    required String wid,
  }) async {
    _logger.info('[Gateway] 加载预约详情 userId=${session.userId} wid=$wid');
    final validation = await validateSession(session);
    if (validation.isFailure) {
      return FailureResult(validation.failureOrNull!);
    }

    final result = await _portalApi.fetchGymData(
      session,
      path: '/modules/myApplication/getMyAppointmentData.do',
      formFields: {'WID': wid},
    );
    if (result case FailureResult<dynamic>(failure: final failure)) {
      return FailureResult(failure);
    }

    final rows = _extractGymRows(
      result.dataOrNull,
      dataKey: 'getMyAppointmentData',
    );
    if (rows.isEmpty) {
      return const FailureResult(ParsingFailure('未找到预约详情。'));
    }

    final row = rows.first;
    var detail = _mapAppointmentDetail(row);
    if (detail == null) {
      return const FailureResult(ParsingFailure('预约详情解析失败。'));
    }

    if (detail.status == '未知' || detail.statusCode == null) {
      final recordsResult = await fetchMyGymAppointments(
        session,
        page: 1,
        pageSize: 50,
      );
      if (recordsResult case Success<List<BookingRecord>>(
        data: final records,
      )) {
        final matched = records.where((item) => item.id == wid).toList();
        if (matched.isNotEmpty) {
          final record = matched.first;
          detail = AppointmentDetail(
            id: detail.id,
            venueName: detail.venueName,
            address: detail.address,
            slotLabel: detail.slotLabel,
            date: detail.date,
            status: record.status,
            statusCode: record.statusCode,
            attendeeName: detail.attendeeName,
            phone: detail.phone,
            department: detail.department,
            venueType: detail.venueType,
            sportName: detail.sportName,
            bookingType: detail.bookingType,
            attendeeCount: detail.attendeeCount,
            venueCode: detail.venueCode,
            businessWid: detail.businessWid,
            cancelReasonCode: detail.cancelReasonCode,
            cancelTime: detail.cancelTime,
            rating: detail.rating,
            reviewContent: detail.reviewContent,
            checkInTime: detail.checkInTime,
            checkOutTime: detail.checkOutTime,
            durationMinutes: detail.durationMinutes,
            canCancel: record.canCancel,
          );
        }
      }
    }

    _logger.info('[Gateway] 预约详情加载完成 wid=$wid');
    return Success(detail);
  }

  @override
  Future<Result<void>> cancelGymAppointment(
    AppSession session, {
    required String appointmentId,
    String? reason,
  }) async {
    _logger.info('[Gateway] 取消预约 wid=$appointmentId');
    final validation = await validateSession(session);
    if (validation.isFailure) {
      return FailureResult(validation.failureOrNull!);
    }

    final now = DateTime.now();
    final qxsj =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';

    final result = await _portalApi.fetchGymData(
      session,
      path: '/modules/myApplication/T_WISEDU_CGYY_YY_SAVE.do',
      formFields: {
        'WID': appointmentId,
        'QXYY': (reason == null || reason.isEmpty) ? '0' : reason,
        'QXSJ': qxsj,
        'SYZT': '003',
        'PAY_STATUS': 'CG_QX',
      },
    );

    if (result case FailureResult<dynamic>(failure: final failure)) {
      return FailureResult(failure);
    }

    final data = result.dataOrNull;
    if (data is Map<String, dynamic>) {
      final code = _pickString(data, const ['code']);
      if (code != null && code != '0') {
        final msg = _pickString(data, const ['msg', 'message']) ?? '取消预约失败。';
        return FailureResult(BusinessFailure(msg));
      }
    }

    _logger.info('[Gateway] 取消预约成功 wid=$appointmentId');
    return const Success(null);
  }

  @override
  Future<Result<VenueDetail>> fetchGymRoomDetail(
    AppSession session, {
    required String wid,
  }) async {
    _logger.info('[Gateway] 加载场地详情 wid=$wid');
    final validation = await validateSession(session);
    if (validation.isFailure) {
      return FailureResult(validation.failureOrNull!);
    }

    final result = await _portalApi.fetchGymData(
      session,
      path: '/modules/application/getRoomDetail.do',
      formFields: {'WID': wid},
    );
    if (result case FailureResult<dynamic>(failure: final failure)) {
      return FailureResult(failure);
    }

    final rows = _extractGymRows(result.dataOrNull, dataKey: 'getRoomDetail');
    if (rows.isEmpty) {
      return const FailureResult(ParsingFailure('未找到场地详情。'));
    }

    final row = rows.first;
    final name =
        _pickString(row, const ['HYSMC', 'NAME', 'BIZ_WID_DISPLAY']) ?? '';
    final detail = VenueDetail(
      id: wid,
      name: name,
      address: _pickString(row, const ['XXDZ', 'address']),
      venueType: _pickString(row, const ['HYSLX_DISPLAY', 'HYSLX']),
      department: _pickString(row, const ['GLBM_DISPLAY', 'GLBMMC']),
      capacity: _pickInt(row, const ['RNRS', 'capacity']) ?? 0,
      maxAdvanceDays: _pickInt(row, const ['TQYYTS']),
      openStatus: _pickString(row, const ['KFZT_DISPLAY', 'KFZT']),
      bookable: _pickString(row, const ['YYSH_DISPLAY', 'YYSH']),
    );

    _logger.info('[Gateway] 场地详情加载完成 name=$name');
    return Success(detail);
  }

  @override
  Future<Result<VenueReviewPage>> fetchGymRoomReviews(
    AppSession session, {
    required String bizWid,
    int page = 1,
    int pageSize = 10,
  }) async {
    _logger.info('[Gateway] 加载场地评论 bizWid=$bizWid page=$page');
    final validation = await validateSession(session);
    if (validation.isFailure) {
      return FailureResult(validation.failureOrNull!);
    }

    final result = await _portalApi.fetchGymData(
      session,
      path: '/modules/application/getRecentRoomRate.do',
      formFields: {
        'BIZ_WID': bizWid,
        'pageSize': '$pageSize',
        'pageNumber': '$page',
      },
    );
    if (result case FailureResult<dynamic>(failure: final failure)) {
      return FailureResult(failure);
    }

    final rows = _extractGymRows(
      result.dataOrNull,
      dataKey: 'getRecentRoomRate',
    );
    final reviews = rows.map(_mapVenueReview).whereType<VenueReview>().toList();

    final totalCount = _extractTotalCount(
      result.dataOrNull,
      'getRecentRoomRate',
    );

    _logger.info(
      '[Gateway] 场地评论加载完成 count=${reviews.length} total=$totalCount',
    );
    return Success(
      VenueReviewPage(
        reviews: reviews,
        totalCount: totalCount,
        pageNumber: page,
        pageSize: pageSize,
      ),
    );
  }

  VenueReview? _mapVenueReview(Map<String, dynamic> map) {
    final id = _pickString(map, const ['WID', 'wid']) ?? '';
    final userName =
        _pickString(map, const ['XM', 'userName', 'CZRXM']) ?? '匿名';
    final ratingRaw = _pickDouble(map, const ['PF', 'rating', 'SCORE']);
    if (ratingRaw == null) return null;

    final czrq = _pickString(map, const ['CZRQ', 'createdAt']);
    final createdAt = czrq != null ? DateTime.tryParse(czrq) : null;

    return VenueReview(
      id: id,
      userName: userName,
      rating: ratingRaw,
      content: _pickString(map, const ['PJNR', 'content', 'remark']),
      createdAt: createdAt,
    );
  }

  int _extractTotalCount(dynamic raw, String dataKey) {
    if (raw is! Map<String, dynamic>) return 0;
    final datas = raw['datas'];
    if (datas is! Map<String, dynamic>) return 0;
    final sub = datas[dataKey];
    if (sub is! Map<String, dynamic>) return 0;
    return _pickInt(sub, const [
          'totalSize',
          'total',
          'totalCount',
          'totalResult',
        ]) ??
        0;
  }

  @override
  Future<Result<GymSearchModel>> fetchGymSearchModel(AppSession session) async {
    _logger.info('[Gateway] 加载场馆搜索模型');
    final validation = await validateSession(session);
    if (validation.isFailure) {
      return FailureResult(validation.failureOrNull!);
    }

    final result = await _portalApi.fetchGymData(
      session,
      path: '/modules/application/getRoomOrderSearchModel.do',
      formFields: {'*searchMeta': '1'},
    );
    if (result case FailureResult<dynamic>(failure: final failure)) {
      return FailureResult(failure);
    }

    final model = await _parseSearchModel(session, result.dataOrNull);
    _logger.info(
      '[Gateway] 搜索模型加载完成 controls=${model.controls.length} '
      'venueTypes=${model.venueTypes.length} sports=${model.sports.length}',
    );
    return Success(model);
  }

  Future<GymSearchModel> _parseSearchModel(
    AppSession session,
    dynamic raw,
  ) async {
    final controls = <GymSearchControl>[];
    final venueTypes = <GymFilterOption>[];
    final sports = <GymFilterOption>[];

    final rawControls = _extractSearchControls(raw);
    if (rawControls.isEmpty) {
      return GymSearchModel(
        controls: controls,
        venueTypes: venueTypes,
        sports: sports,
      );
    }

    for (final control in rawControls) {
      if (control is! Map) {
        continue;
      }
      final controlMap = Map<String, dynamic>.from(
        control.cast<dynamic, dynamic>(),
      );
      final name = _pickString(controlMap, const ['name']);
      if (name == null || name.isEmpty) {
        continue;
      }
      final caption = _pickString(controlMap, const ['caption']) ?? name;
      final defaultBuilder =
          _pickString(controlMap, const ['defaultBuilder', 'builder']) ??
          'm_value_equal';
      final builderList = _pickString(controlMap, const ['builderList']);
      final url = _pickString(controlMap, const ['url']);

      var options = _parseInlineFilterOptions(controlMap);
      if (options.isEmpty && url != null && url.isNotEmpty) {
        final remotePost = await _portalApi.fetchGymCodeData(
          session,
          codeUrl: url,
          method: 'POST',
        );
        if (remotePost case Success<dynamic>(data: final data)) {
          options = _parseRemoteFilterOptions(data);
        }
        if (options.isEmpty) {
          final remoteGet = await _portalApi.fetchGymCodeData(
            session,
            codeUrl: url,
            method: 'GET',
          );
          if (remoteGet case Success<dynamic>(data: final data)) {
            options = _parseRemoteFilterOptions(data);
          }
        }
      }

      final resolvedOptions = _deduplicateFilterOptions(
        options
            .map(
              (option) => option.copyWith(
                controlName: name,
                caption: caption,
                builder: defaultBuilder,
                builderList: builderList,
                url: url,
              ),
            )
            .toList(),
      );
      controls.add(
        GymSearchControl(
          name: name,
          caption: caption,
          defaultBuilder: defaultBuilder,
          builderList: builderList,
          url: url,
          options: resolvedOptions,
        ),
      );

      if (name.contains('HYSLX') || name.contains('venueType')) {
        venueTypes.addAll(resolvedOptions);
      } else if (name.contains('GLBM') || name.contains('sport')) {
        sports.addAll(resolvedOptions);
      }
    }

    return GymSearchModel(
      controls: controls,
      venueTypes: _deduplicateFilterOptions(venueTypes),
      sports: _deduplicateFilterOptions(sports),
    );
  }

  List<dynamic> _extractSearchControls(dynamic raw) {
    if (raw is! Map<String, dynamic>) {
      return const [];
    }

    final candidates = <dynamic>[
      raw,
      raw['searchMeta'],
      raw['getRoomOrderSearchModel'],
    ];

    final datas = raw['datas'];
    if (datas is Map<String, dynamic>) {
      candidates.addAll([
        datas,
        datas['searchMeta'],
        datas['getRoomOrderSearchModel'],
      ]);
    }

    for (final candidate in candidates) {
      final controls = _readSearchControls(candidate);
      if (controls.isNotEmpty) {
        return controls;
      }
    }

    return const [];
  }

  List<dynamic> _readSearchControls(dynamic candidate) {
    if (candidate is! Map) {
      return const [];
    }
    final map = Map<String, dynamic>.from(candidate.cast<dynamic, dynamic>());
    final directControls = map['controls'];
    if (directControls is List) {
      return directControls;
    }

    final searchMeta = map['searchMeta'];
    if (searchMeta is Map) {
      final nested = _readSearchControls(searchMeta);
      if (nested.isNotEmpty) {
        return nested;
      }
    }

    return const [];
  }

  List<GymFilterOption> _parseInlineFilterOptions(
    Map<String, dynamic> control,
  ) {
    final options = <GymFilterOption>[];
    final optionValues = control['optionValues'];
    if (optionValues is! List) {
      return options;
    }

    for (final opt in optionValues) {
      if (opt is! Map) {
        continue;
      }
      final map = Map<String, dynamic>.from(opt.cast<dynamic, dynamic>());
      final id = _pickString(map, const ['id', 'value']) ?? '';
      final label = _pickString(map, const ['label', 'text', 'name']) ?? id;
      if (id.isNotEmpty) {
        options.add(GymFilterOption(id: id, label: label));
      }
    }

    return options;
  }

  List<GymFilterOption> _parseRemoteFilterOptions(dynamic raw) {
    if (raw is! Map<String, dynamic>) {
      return const [];
    }
    final datas = raw['datas'];
    if (datas is! Map<String, dynamic>) {
      return const [];
    }
    final code = datas['code'];
    if (code is! Map<String, dynamic>) {
      return const [];
    }
    final rows = code['rows'];
    if (rows is! List) {
      return const [];
    }

    final options = <GymFilterOption>[];
    for (final row in rows) {
      if (row is! Map) {
        continue;
      }
      final map = Map<String, dynamic>.from(row.cast<dynamic, dynamic>());
      final id = _pickString(map, const ['id', 'value']) ?? '';
      final label = _pickString(map, const ['name', 'label', 'text']) ?? id;
      if (id.isNotEmpty) {
        options.add(GymFilterOption(id: id, label: label));
      }
    }
    return options;
  }

  List<GymFilterOption> _deduplicateFilterOptions(
    List<GymFilterOption> options,
  ) {
    final deduped = <String, GymFilterOption>{};
    for (final option in options) {
      deduped[option.id] = option;
    }
    return deduped.values.toList();
  }

  @override
  Future<Result<AppSession>> login(SchoolCredential credential) {
    return _loginOrchestrator.login(credential);
  }

  @override
  Future<Result<AppSession>> refreshSession(SchoolCredential credential) {
    return _loginOrchestrator.login(credential);
  }

  @override
  Future<Result<void>> validateSession(AppSession session) {
    return _sessionValidator.validate(session);
  }

  @override
  Future<Result<List<ServiceCardGroup>>> fetchServiceCards(
    AppSession session,
  ) async {
    _logger.info('[Gateway] 开始加载服务卡片 userId=${session.userId}');
    final validation = await validateSession(session);
    if (validation.isFailure) {
      _logger.warn('[Gateway] 服务卡片加载前 session 校验失败');
      return FailureResult(validation.failureOrNull!);
    }

    final groups = <ServiceCardGroup>[];

    final serviceCardResult = await _portalApi.fetchServiceCardData(
      session,
      _serviceCardWid,
    );
    if (serviceCardResult case Success<Map<String, dynamic>>(
      data: final data,
    )) {
      final group = _parseServiceCardGroup('校园服务', _serviceCardWid, data);
      if (group != null) {
        groups.add(group);
      }
    } else {
      _logger.warn('[Gateway] 校园服务卡片加载失败');
    }

    final yjsCardResult = await _portalApi.fetchServiceCardData(
      session,
      _yjsServiceCardWid,
    );
    if (yjsCardResult case Success<Map<String, dynamic>>(data: final data)) {
      final group = _parseServiceCardGroup('系统直通车', _yjsServiceCardWid, data);
      if (group != null) {
        groups.add(group);
      }
    } else {
      _logger.warn('[Gateway] 系统直通车卡片加载失败');
    }

    if (groups.isEmpty) {
      return const FailureResult(ParsingFailure('未加载到任何服务数据。'));
    }

    _logger.info(
      '[Gateway] 服务卡片加载完成 groupCount=${groups.length} '
      'totalItems=${groups.fold<int>(0, (sum, g) => sum + g.items.length)}',
    );
    return Success(groups);
  }

  @override
  Future<Result<List<ServiceItem>>> fetchServiceCategoryItems(
    AppSession session, {
    required String cardWid,
    required ServiceCategory category,
  }) async {
    _logger.info(
      '[Gateway] 开始加载服务分类 cardWid=$cardWid typeId=${category.typeId} typeName=${category.typeName}',
    );
    final validation = await validateSession(session);
    if (validation.isFailure) {
      _logger.warn('[Gateway] 服务分类加载前 session 校验失败');
      return FailureResult(validation.failureOrNull!);
    }

    final result = await _portalApi.fetchServiceCardData(
      session,
      cardWid,
      typeId: category.typeId,
    );
    if (result case FailureResult<Map<String, dynamic>>(
      failure: final failure,
    )) {
      return FailureResult(failure);
    }

    final parsed = _parseServiceCardGroup(
      '分类服务',
      cardWid,
      result.requireValue(),
    );
    if (parsed == null) {
      return const FailureResult(ParsingFailure('服务分类解析失败。'));
    }

    final items = parsed.itemsForCategory(category);
    if (items.isNotEmpty) {
      return Success(items);
    }

    return Success(parsed.items);
  }

  @override
  Future<Result<ServiceLaunchData>> prepareServiceLaunch(
    AppSession session, {
    required ServiceItem item,
  }) async {
    _logger.info(
      '[Gateway] 准备进入服务 app=${item.appName} userId=${session.userId}',
    );
    final validation = await validateSession(session);
    if (validation.isFailure) {
      _logger.warn('[Gateway] 服务跳转前 session 校验失败');
      return FailureResult(validation.failureOrNull!);
    }

    return _portalApi.prepareServiceLaunch(session, item: item);
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
    if (snapshot != null) {
      _logger.info(
        '[Gateway] 本科课表解析完成 term=${snapshot.term.name} '
        'courseCount=${snapshot.courses.length} entryCount=${snapshot.entries.length}',
      );
    }
    return snapshot == null
        ? Success(
            ScheduleSnapshot(
              term: selectedTerm,
              availableTerms: availableTerms,
              courses: const [],
              fetchedAt: DateTime.now(),
              origin: DataOrigin.remote,
            ),
          )
        : Success(snapshot);
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

  List<Term> _generateUndergradTerms() {
    final now = DateTime.now();
    final terms = <Term>[];
    final currentAcademicYear = now.month >= 9 ? now.year : now.year - 1;
    final currentTermId = _currentUndergradTermId(now);

    for (
      var academicYear = currentAcademicYear;
      academicYear >= currentAcademicYear - 3;
      academicYear--
    ) {
      final firstTerm = _buildUndergradTerm(academicYear, 1);
      final secondTerm = _buildUndergradTerm(academicYear, 2);

      if (firstTerm.id == currentTermId) {
        terms
          ..add(firstTerm.copyWith(isSelected: true))
          ..add(secondTerm);
        continue;
      }
      if (secondTerm.id == currentTermId) {
        terms
          ..add(secondTerm.copyWith(isSelected: true))
          ..add(firstTerm);
        continue;
      }

      terms
        ..add(secondTerm)
        ..add(firstTerm);
    }

    return terms;
  }

  Term _selectUndergradTerm(List<Term> terms, {String? requestedTermId}) {
    if (requestedTermId != null && requestedTermId.isNotEmpty) {
      final match = terms.where((t) => t.id == requestedTermId);
      if (match.isNotEmpty) return match.first;
    }
    final selected = terms.where((t) => t.isSelected);
    if (selected.isNotEmpty) return selected.first;
    return terms.isNotEmpty ? terms.last : const Term(id: '', name: '未知学期');
  }

  Term _buildUndergradTerm(int academicYear, int semesterIndex) {
    final termCode = '$academicYear${semesterIndex.toString().padLeft(2, '0')}';
    return Term(
      id: termCode,
      name: _formatUndergradTermName(termCode) ?? termCode,
    );
  }

  String _currentUndergradTermId(DateTime now) {
    final academicYear = now.month >= 9 ? now.year : now.year - 1;
    final semesterIndex = now.month >= 3 && now.month <= 8 ? 2 : 1;
    return '$academicYear${semesterIndex.toString().padLeft(2, '0')}';
  }

  String? _formatUndergradTermName(String? termCode) {
    if (termCode == null) {
      return null;
    }

    final match = RegExp(r'^(20\d{2})(0[12])$').firstMatch(termCode);
    if (match == null) {
      return termCode;
    }

    final academicYear = int.parse(match.group(1)!);
    final semesterCode = match.group(2)!;
    final displayEndYear = (academicYear + 1) % 100;
    final semesterLabel = switch (semesterCode) {
      '01' => '第一学期',
      '02' => '第二学期',
      _ => termCode,
    };
    return '$academicYear-${displayEndYear.toString().padLeft(2, '0')} $semesterLabel';
  }

  bool _isAllTermsSelection(String? termId) => termId != null && termId.isEmpty;

  List<String> _splitDisplayValues(String raw) {
    return raw
        .split(RegExp(r'[、,，/]'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  Failure? _extractUndergradJxglAuthFailure(Map<String, dynamic> raw) {
    final code = _pickString(raw, const ['code', 'status']);
    final message = _pickString(raw, const ['message', 'msg', 'error']);
    if (code != '-401' &&
        code != '401' &&
        !_looksLikeSessionExpiredMessage(message)) {
      return null;
    }
    return SessionExpiredFailure(message ?? '教务系统会话已失效。');
  }

  bool _looksLikeSessionExpiredMessage(String? message) {
    if (message == null || message.isEmpty) {
      return false;
    }
    return message.contains('尚未登录') ||
        message.contains('请先登录') ||
        message.contains('登录失效') ||
        message.contains('已在别处登录') ||
        message.contains('被迫退出');
  }

  GymBookingOverview? _parseGymRoomData(
    dynamic raw, {
    required DateTime targetDate,
  }) {
    final page = _parseGymVenueSearchPage(
      raw,
      query: GymVenueSearchQuery(
        date: targetDate,
        pageNumber: 1,
        pageSize: 100,
      ),
    );
    if (page == null) {
      return null;
    }

    final venues = page.venues;
    final slotsByVenue = page.slotsByVenue;
    final today = _normalizeDate(DateTime.now());
    const advanceWindowDays = 7;

    final targetNorm = _normalizeDate(targetDate);
    final hasTargetSlots = slotsByVenue.values.any(
      (slots) => slots.any((s) => _normalizeDate(s.date) == targetNorm),
    );

    if (!hasTargetSlots && targetNorm.isBefore(today)) {
      _logger.warn('[Gateway] 所选日期在可预约范围之前');
    }

    return GymBookingOverview(
      date: targetDate,
      venues: venues,
      slotsByVenue: slotsByVenue,
      rule: BookingRule(
        summary: '支持预约未来 $advanceWindowDays 天的场地',
        advanceWindowDays: advanceWindowDays,
        supportsSameDay: true,
      ),
      records: const [],
      fetchedAt: DateTime.now(),
      origin: DataOrigin.remote,
    );
  }

  GymVenueSearchPage? _parseGymVenueSearchPage(
    dynamic raw, {
    required GymVenueSearchQuery query,
  }) {
    final rows = _extractGymRows(raw, dataKey: 'getOpeningRoom');
    final paging = _extractPagingInfo(raw, dataKey: 'getOpeningRoom');

    final venues = <Venue>[];
    final slotsByVenue = <String, List<BookableSlot>>{};
    for (final row in rows) {
      final venue = _mapVenueFromRoomRow(row);
      if (venue == null) {
        continue;
      }

      final slots = _extractSlotsFromRoomRow(
        row,
        venueId: venue.id,
        targetDate: query.date,
      );
      venues.add(venue);
      slotsByVenue[venue.id] = slots;
    }

    return GymVenueSearchPage(
      query: query,
      venues: venues,
      slotsByVenue: slotsByVenue,
      totalSize: paging.totalSize,
      fetchedAt: DateTime.now(),
      origin: DataOrigin.remote,
    );
  }

  List<BookingRecord> _parseGymAppointmentRecords(dynamic raw) {
    // Response: { "code": "0", "datas": { "getMyAppointmentListData": { "rows": [...] } } }
    final rows = _extractGymRows(raw, dataKey: 'getMyAppointmentListData');
    return rows
        .map(_mapGymAppointmentRecord)
        .whereType<BookingRecord>()
        .toList();
  }

  List<Map<String, dynamic>> _extractGymRows(
    dynamic raw, {
    required String dataKey,
  }) {
    if (raw is! Map<String, dynamic>) return const [];

    // Try "datas.{dataKey}.rows" structure first
    final datas = raw['datas'];
    if (datas is Map<String, dynamic>) {
      final sub = datas[dataKey];
      if (sub is Map<String, dynamic>) {
        final rowsRaw = sub['rows'];
        if (rowsRaw is List) {
          return rowsRaw
              .whereType<Map>()
              .map((m) => Map<String, dynamic>.from(m.cast<dynamic, dynamic>()))
              .toList();
        }
      }
    }

    // Fallback: "data.rows" or "data"
    final data = raw['data'];
    if (data is Map<String, dynamic>) {
      final rowsRaw = data['rows'];
      if (rowsRaw is List) {
        return rowsRaw
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m.cast<dynamic, dynamic>()))
            .toList();
      }
      return [data];
    }

    return const [];
  }

  ({int pageNumber, int pageSize, int totalSize}) _extractPagingInfo(
    dynamic raw, {
    required String dataKey,
  }) {
    if (raw is! Map<String, dynamic>) {
      return (pageNumber: 1, pageSize: 0, totalSize: 0);
    }

    final datas = raw['datas'];
    if (datas is! Map<String, dynamic>) {
      return (pageNumber: 1, pageSize: 0, totalSize: 0);
    }
    final sub = datas[dataKey];
    if (sub is! Map<String, dynamic>) {
      return (pageNumber: 1, pageSize: 0, totalSize: 0);
    }

    return (
      pageNumber: _pickInt(sub, const ['pageNumber']) ?? 1,
      pageSize: _pickInt(sub, const ['pageSize']) ?? 0,
      totalSize: _pickInt(sub, const ['totalSize', 'total', 'totalCount']) ?? 0,
    );
  }

  Venue? _mapVenueFromRoomRow(Map<String, dynamic> row) {
    final wid = _pickString(row, const ['WID', 'wid']) ?? '';
    final bizWid = _pickString(row, const ['BIZ_WID', 'bizWid']) ?? '';
    final name = _pickString(row, const [
      'HYSMC',
      'BIZ_WID_DISPLAY',
      'WID_DISPLAY',
      'NAME',
      'name',
    ]);
    if (name == null) {
      return null;
    }

    final venueType = _pickString(row, const ['HYSLX_DISPLAY', 'venueType']);
    final venueTypeId = _pickString(row, const ['HYSLX', 'venueTypeId']);
    final sportName = _pickString(row, const ['GLBM_DISPLAY', 'GLBMMC']);
    final sportId = _pickString(row, const ['GLBM', 'departmentId']);
    final address = _pickString(row, const ['XXDZ', 'address']);
    final openStatus = _pickString(row, const ['KFZT_DISPLAY', 'KFZT']);
    final approvalMode = _pickString(row, const ['YYSH_DISPLAY', 'YYSH']);
    final venueCode = _pickString(row, const ['HYSBH', 'code']);
    final capacity = _pickInt(row, const ['RNRS', 'capacity']) ?? 0;

    return Venue(
      id: wid.isNotEmpty ? wid : bizWid,
      name: name,
      location: address ?? sportName ?? venueType ?? '',
      bizWid: bizWid.isNotEmpty ? bizWid : wid,
      venueType: venueType,
      venueTypeId: venueTypeId,
      sportId: sportId,
      sportName: sportName,
      department: sportName,
      departmentId: sportId,
      venueCode: venueCode,
      address: address,
      openStatus: openStatus,
      approvalMode: approvalMode,
      capacity: capacity,
    );
  }

  List<BookableSlot> _extractSlotsFromRoomRow(
    Map<String, dynamic> row, {
    required String venueId,
    DateTime? targetDate,
  }) {
    final slots = <BookableSlot>[];
    final normalizedTarget = targetDate == null
        ? null
        : _normalizeDate(targetDate);
    final fallbackCapacity = _pickInt(row, const ['RNRS', 'capacity']) ?? 1;

    for (var dayNum = 1; dayNum <= 7; dayNum++) {
      final dayData = row['day$dayNum'];
      if (dayData is! Map) {
        continue;
      }

      final dayMap = Map<String, dynamic>.from(
        dayData.cast<dynamic, dynamic>(),
      );
      final dateStr = _pickString(dayMap, const ['date']);
      if (dateStr == null) {
        continue;
      }
      final parsedDate = DateTime.tryParse(dateStr);
      if (parsedDate == null) {
        continue;
      }

      final slotDate = _normalizeDate(parsedDate);
      if (normalizedTarget != null && slotDate != normalizedTarget) {
        continue;
      }

      final timesText = _pickString(dayMap, const ['times']) ?? '';
      if (timesText.isEmpty) {
        continue;
      }

      for (final timeSegment in timesText.split(',')) {
        final trimmed = timeSegment.trim();
        if (trimmed.isEmpty) {
          continue;
        }
        final parts = trimmed.split('-');
        if (parts.length != 2) {
          continue;
        }

        slots.add(
          BookableSlot(
            id: '${venueId}_${slotDate.toIso8601String()}_$trimmed',
            startTime: parts[0].trim(),
            endTime: parts[1].trim(),
            capacity: fallbackCapacity,
            remaining: 1,
            date: slotDate,
            weekday: slotDate.weekday,
          ),
        );
      }
    }

    return slots;
  }

  Map<String, dynamic> _buildGymApplyFormData(BookingDraft draft) {
    final yyrq = _formatDate(draft.date);
    final sysj = draft.slot.timeLabel;
    final bizWid = draft.bizWid ?? draft.venue.bizWid;
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final raw = '${draft.userAccount}$yyrq$sysj${bizWid}_WISEDU_$timestamp';
    final encoded = Uri.encodeComponent(raw);
    final verification = base64Encode(utf8.encode(encoded));

    return {
      'YYRXM': draft.attendeeName,
      'YYLX_DISPLAY': '个人预约',
      'YYLX': '001',
      'YYRQ': yyrq,
      'SYSJ': sysj,
      'SYRS': '1',
      'LXDH': draft.phone ?? '',
      'HYSLX_DISPLAY': draft.venue.venueType ?? '',
      'HYSLX': draft.venue.venueTypeId ?? '',
      'GLBM_DISPLAY': draft.venue.sportName ?? draft.venue.department ?? '',
      'GLBM': draft.venue.sportId ?? draft.venue.departmentId ?? '',
      'HYSMC': draft.venue.name,
      'HYZT': '',
      'HYMS': '',
      'BZ': '',
      'FJ': '',
      'WID': draft.venue.id,
      'XGH': draft.userAccount,
      'BIZ_WID': bizWid,
      'SYZT': '001',
      'VERIFICATION': verification,
      'BCSQRS': 1,
      'USERID': draft.userAccount,
    };
  }

  Result<GymBookingEligibility> _parseGymEligibility(dynamic raw) {
    if (raw is! Map<String, dynamic>) {
      return const FailureResult(ParsingFailure('预约校验响应结构异常。'));
    }

    final code = _pickString(raw, const ['code']);
    if (code != null && code != '0') {
      final msg = _pickString(raw, const ['msg', 'message']) ?? '预约校验未通过。';
      return FailureResult(BusinessFailure(msg));
    }

    final data = raw['data'];
    if (data is! Map<String, dynamic>) {
      return const Success(GymBookingEligibility(canApply: true));
    }

    final canApply = _pickString(data, const ['canApply']);
    if (canApply == 'false' || canApply == '0') {
      final message =
          _pickString(data, const ['msg']) ??
          _pickString(raw, const ['msg', 'message']) ??
          '预约校验未通过。';
      return Success(GymBookingEligibility(canApply: false, message: message));
    }

    return const Success(GymBookingEligibility(canApply: true));
  }

  List<dynamic>? _buildVenueQuerySetting(GymVenueSearchQuery query) {
    final groups = <dynamic>[];
    final keyword = query.keyword.trim();

    if (keyword.isNotEmpty) {
      groups.add([
        {
          'caption': '场地名称',
          'name': 'HYSMC',
          'value': keyword,
          'builder': 'include',
          'linkOpt': 'OR',
        },
      ]);
    }

    if (query.venueTypeId != null && query.venueTypeId!.isNotEmpty) {
      final entry = <String, dynamic>{
        'name': 'HYSLX',
        'caption': '场馆类型',
        'builder': query.venueTypeBuilder ?? 'm_value_equal',
        'linkOpt': 'AND',
        'builderList': query.venueTypeBuilderList ?? 'cbl_m_List',
        'value': query.venueTypeId,
      };
      if (query.venueTypeLabel != null && query.venueTypeLabel!.isNotEmpty) {
        entry['value_display'] = query.venueTypeLabel;
      }
      groups.add(entry);
    }

    if (query.sportId != null && query.sportId!.isNotEmpty) {
      final entry = <String, dynamic>{
        'name': 'GLBM',
        'caption': '体育项目',
        'builder': query.sportBuilder ?? 'm_value_equal',
        'linkOpt': 'AND',
        'builderList': query.sportBuilderList ?? 'cbl_m_List',
        'value': query.sportId,
      };
      if (query.sportLabel != null && query.sportLabel!.isNotEmpty) {
        entry['value_display'] = query.sportLabel;
      }
      groups.add(entry);
    }

    return groups.isEmpty ? null : groups;
  }

  List<dynamic>? _buildAppointmentQuerySetting(GymAppointmentQuery query) {
    final groups = <dynamic>[];
    final keyword = query.keyword.trim();

    if (keyword.isNotEmpty) {
      groups.add([
        {
          'caption': '场地名称',
          'name': 'HYSMC',
          'value': keyword,
          'builder': 'include',
          'linkOpt': 'OR',
        },
      ]);
    }

    if (query.statusCode != null && query.statusCode!.isNotEmpty) {
      groups.add({
        'name': 'SYZT',
        'caption': '使用状态',
        'builder': 'equal',
        'linkOpt': 'AND',
        'value': query.statusCode,
      });
    }

    return groups.isEmpty ? null : groups;
  }

  BookingRecord? _mapGymAppointmentRecord(Map<String, dynamic> map) {
    final venueName = _pickString(map, const [
      'HYSMC',
      'BIZ_WID_DISPLAY',
      'HYSLX_DISPLAY',
      'venueName',
      'CDMC',
    ]);
    final sysj = _pickString(map, const ['SYSJ', 'SJ', 'timeRange']);
    final yyrq = _pickString(map, const ['YYRQ', 'YYSJ', 'date']);
    final wid = _pickString(map, const ['WID', 'wid']) ?? '';

    if (venueName == null) return null;

    final statusRaw = _pickString(map, const ['SYZT', 'PAY_STATUS']);
    final statusDisplay = _pickString(map, const [
      'SYZT_DISPLAY',
      'PAY_STATUS_DISPLAY',
      'PAY_STATUS',
    ]);
    final status =
        _gymStatusToLabel(statusRaw) ?? statusDisplay ?? statusRaw ?? '未知';

    DateTime? date;
    if (yyrq != null) {
      date = DateTime.tryParse(yyrq);
    }

    return BookingRecord(
      id: wid,
      venueName: venueName,
      slotLabel: sysj ?? '时段未知',
      date: date ?? DateTime.now(),
      status: status,
      statusCode: statusRaw,
      canCancel: statusRaw == '001',
    );
  }

  String? _gymStatusToLabel(String? code) {
    if (code == null) return null;
    return switch (code) {
      '001' => '未使用',
      '002' => '已使用',
      '003' => '已取消',
      _ => null,
    };
  }

  AppointmentDetail? _mapAppointmentDetail(Map<String, dynamic> map) {
    final venueName = _pickString(map, const [
      'HYSMC',
      'BIZ_WID_DISPLAY',
      'HYSLX_DISPLAY',
      'venueName',
      'CDMC',
    ]);
    final wid = _pickString(map, const ['WID', 'wid']) ?? '';
    if (venueName == null) return null;

    final sysj = _pickString(map, const ['SYSJ', 'SJ', 'timeRange']);
    final yyrq = _pickString(map, const ['YYRQ', 'YYSJ', 'date']);
    final statusRaw = _pickString(map, const ['SYZT']);
    final statusDisplay = _pickString(map, const ['SYZT_DISPLAY']);
    final status =
        _gymStatusToLabel(statusRaw) ?? statusDisplay ?? statusRaw ?? '未知';

    DateTime? date;
    if (yyrq != null) {
      date = DateTime.tryParse(yyrq);
    }

    return AppointmentDetail(
      id: wid,
      venueName: venueName,
      address: _pickString(map, const ['XXDZ', 'address']),
      slotLabel: sysj ?? '时段未知',
      date: date ?? DateTime.now(),
      status: status,
      statusCode: statusRaw,
      attendeeName: _pickString(map, const [
        'YYRXM',
        'XM',
        'attendeeName',
        'XGH_DISPLAY',
      ]),
      phone: _pickString(map, const ['LXDH', 'phone']),
      department: _pickString(map, const [
        'GLBM_DISPLAY',
        'GLBMMC',
        'department',
      ]),
      venueType: _pickString(map, const ['HYSLX_DISPLAY', 'HYSLX']),
      sportName: _pickString(map, const ['GLBM_DISPLAY', 'GLBMMC']),
      bookingType: _pickString(map, const ['YYLX_DISPLAY', 'YYLX']),
      attendeeCount: _pickString(map, const ['SYRS']),
      venueCode: _pickString(map, const ['HYSBH']),
      businessWid: _pickString(map, const ['BIZ_WID']),
      cancelReasonCode: _pickString(map, const ['QXYY']),
      cancelTime: _pickString(map, const ['QXSJ']),
      rating: _pickString(map, const ['PF']),
      reviewContent: _pickString(map, const ['PJNR']),
      checkInTime: _pickString(map, const ['QDSJ']),
      checkOutTime: _pickString(map, const ['QTSJ']),
      durationMinutes: _pickString(map, const ['YDSC']),
      canCancel: statusRaw == '001' || status == '未使用',
    );
  }

  DateTime _normalizeDate(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  String _formatDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  ServiceCardGroup? _parseServiceCardGroup(
    String cardName,
    String cardWid,
    Map<String, dynamic> raw,
  ) {
    final data = raw['data'];
    if (data is! Map<String, dynamic>) return null;

    final categories = _parseServiceCategories(data);
    final items = _parseServiceItems(data);
    if (items.isEmpty && categories.isEmpty) return null;

    // If classifyData was empty, fall back to deriving categories from items
    if (categories.isEmpty && items.isNotEmpty) {
      final categoryMap = <String, ServiceCategory>{};
      final countMap = <String, int>{};
      for (final item in items) {
        countMap[item.typeId] = (countMap[item.typeId] ?? 0) + 1;
        if (!categoryMap.containsKey(item.typeId)) {
          categoryMap[item.typeId] = ServiceCategory(
            typeId: item.typeId,
            typeName: item.typeId.isEmpty ? '其他' : item.typeId,
            count: countMap[item.typeId]!,
          );
        } else {
          categoryMap[item.typeId] = categoryMap[item.typeId]!.copyWith(
            count: countMap[item.typeId],
          );
        }
      }
      categories.addAll(categoryMap.values);
    }

    return ServiceCardGroup(
      cardWid: cardWid,
      cardName: cardName,
      categories: categories,
      items: items,
    );
  }

  List<ServiceCategory> _parseServiceCategories(Map<String, dynamic> data) {
    final categories = <ServiceCategory>[];
    final classifyData = data['classifyData'];
    if (classifyData is! List) {
      return categories;
    }

    for (final cls in classifyData) {
      if (cls is! Map<String, dynamic>) continue;
      final show = cls['show'];
      if (show == false || show == 0) continue;
      final typeId = _pickString(cls, const ['typeId']);
      final typeName = _pickString(cls, const ['typeName']) ?? '其他';
      final count = _pickInt(cls, const ['count']) ?? 0;
      if (typeId != null && typeId.isNotEmpty) {
        categories.add(
          ServiceCategory(typeId: typeId, typeName: typeName, count: count),
        );
      }
    }

    return categories;
  }

  List<ServiceItem> _parseServiceItems(Map<String, dynamic> data) {
    final appData = data['appData'];
    if (appData is! List) {
      return const [];
    }

    final items = <ServiceItem>[];
    for (final svc in appData) {
      if (svc is! Map<String, dynamic>) continue;

      final appName = _pickString(svc, const [
        'appName',
        'serviceName',
        'name',
        'title',
      ]);
      if (appName == null || appName.isEmpty) continue;

      final appId =
          _pickString(svc, const ['appId', 'serviceId', 'wid', 'id']) ??
          appName;
      final iconLink = _pickString(svc, const [
        'iconLink',
        'icon',
        'iconUrl',
        'img',
        'logo',
      ]);
      final pcAccessUrl = _pickString(svc, const [
        'pcAccessUrl',
        'url',
        'pcUrl',
      ]);
      final mobileAccessUrl = _pickString(svc, const [
        'mobileAccessUrl',
        'mobileUrl',
      ]);
      final wid = _pickString(svc, const ['wid', 'serviceWid', 'appWid']);

      final typeId =
          _pickString(svc, const [
            'typeId',
            'categoryId',
            'appTypeId',
            'classifyId',
            'classifyID',
            'typeID',
          ]) ??
          '';
      final typeName = _pickString(svc, const [
        'typeName',
        'categoryName',
        'appTypeName',
        'classifyName',
      ]);

      items.add(
        ServiceItem(
          appId: appId,
          appName: appName,
          iconLink: iconLink,
          pcAccessUrl: pcAccessUrl,
          mobileAccessUrl: mobileAccessUrl,
          wid: wid,
          typeId: typeId,
          typeName: typeName,
        ),
      );
    }

    return items;
  }

  static const _serviceCardWid = '8558486040491173';
  static const _yjsServiceCardWid = '017434820995445355';

  ScheduleSnapshot? _mapSchedule({
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

    if (grouped.isEmpty) {
      return null;
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

      final teacherAndLocation = index < lines.length
          ? lines[index++].trim()
          : '';
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

  Map<String, dynamic> _selectScheduleTerm(
    List<Map<String, dynamic>> terms, {
    String? requestedTermId,
  }) {
    if (requestedTermId != null && requestedTermId.isNotEmpty) {
      for (final term in terms) {
        if (_pickString(term, const ['termcode', 'termCode']) ==
            requestedTermId) {
          return term;
        }
      }
    }

    for (final term in terms) {
      if (_isSelectedTermCurrent(term)) {
        return term;
      }
    }
    return terms.first;
  }

  List<Term> _mapTerms(
    List<Map<String, dynamic>> termMaps, {
    required String selectedTermId,
  }) {
    return termMaps.map((map) {
      final id = _pickString(map, const ['termcode', 'termCode']) ?? '';
      final name =
          _pickString(map, const ['termname', 'termName', 'name']) ?? id;
      return Term(id: id, name: name, isSelected: id == selectedTermId);
    }).toList();
  }

  bool _isSelectedTermCurrent(Map<String, dynamic> termMap) {
    final value = _pickString(termMap, const [
      'selected',
      'dqxnq',
      'isCurrent',
      'currentFlag',
      'sfmr',
    ]);
    return value == '1' || value?.toLowerCase() == 'true';
  }

  List<Map<String, dynamic>> _collectRecordMaps(dynamic value) {
    final items = <Map<String, dynamic>>[];

    void visit(dynamic node) {
      if (node is List) {
        for (final item in node) {
          visit(item);
        }
        return;
      }

      if (node is! Map) {
        return;
      }

      final map = Map<String, dynamic>.from(node.cast<dynamic, dynamic>());
      items.add(map);
      for (final child in map.values) {
        visit(child);
      }
    }

    visit(value);
    return items;
  }

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

  int _nonce() => _random.nextInt(100000);

  String _trimSeconds(String time) {
    // "10:30:00" → "10:30"
    final match = RegExp(r'^(\d{1,2}:\d{2}):\d{2}$').firstMatch(time);
    return match != null ? match.group(1)! : time;
  }

  String? _pickString(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value == null) {
        continue;
      }
      final text = value.toString().trim();
      if (text.isNotEmpty) {
        return text;
      }
    }
    return null;
  }

  int? _pickInt(Map<String, dynamic> map, List<String> keys) {
    final value = _pickString(map, keys);
    if (value == null) {
      return null;
    }
    return int.tryParse(value);
  }

  double? _pickDouble(Map<String, dynamic> map, List<String> keys) {
    final value = _pickString(map, keys);
    if (value == null) {
      return null;
    }
    return double.tryParse(value);
  }
}

class _ParsedScheduleSession {
  const _ParsedScheduleSession({
    required this.courseId,
    required this.courseName,
    required this.teacher,
    required this.courseCode,
    required this.note,
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    required this.weekRange,
    required this.location,
    required this.startSection,
    required this.endSection,
    required this.weekDescription,
    required this.dayLabel,
  });

  final String courseId;
  final String courseName;
  final String teacher;
  final String? courseCode;
  final String? note;
  final int dayOfWeek;
  final String startTime;
  final String endTime;
  final WeekRange weekRange;
  final TeachingLocation location;
  final int? startSection;
  final int? endSection;
  final String? weekDescription;
  final String? dayLabel;
}

class _MutableParsedScheduleSession {
  _MutableParsedScheduleSession({
    required this.courseId,
    required this.courseName,
    required this.teacher,
    required this.courseCode,
    required this.note,
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    required this.weekRange,
    required this.location,
    required this.startSection,
    required this.endSection,
    required this.weekDescription,
    required this.dayLabel,
  });

  final String courseId;
  final String courseName;
  final String teacher;
  final String? courseCode;
  final String? note;
  final int dayOfWeek;
  String startTime;
  String endTime;
  final WeekRange weekRange;
  final TeachingLocation location;
  final int startSection;
  int endSection;
  final String? weekDescription;
  final String? dayLabel;

  _ParsedScheduleSession toImmutable() {
    return _ParsedScheduleSession(
      courseId: courseId,
      courseName: courseName,
      teacher: teacher,
      courseCode: courseCode,
      note: note,
      dayOfWeek: dayOfWeek,
      startTime: startTime,
      endTime: endTime,
      weekRange: weekRange,
      location: location,
      startSection: startSection,
      endSection: endSection,
      weekDescription: weekDescription,
      dayLabel: dayLabel,
    );
  }
}

class _ParsedYjsGridCellCourse {
  const _ParsedYjsGridCellCourse({
    required this.courseName,
    required this.teacher,
    required this.location,
    required this.weekRange,
    required this.weekDescription,
    required this.note,
  });

  final String courseName;
  final String teacher;
  final TeachingLocation location;
  final WeekRange weekRange;
  final String weekDescription;
  final String? note;
}

class TestingSchoolPortalGateway implements SchoolPortalGateway {
  const TestingSchoolPortalGateway();

  @override
  Future<Result<List<ServiceCardGroup>>> fetchServiceCards(
    AppSession session,
  ) async {
    return const FailureResult(BusinessFailure('测试环境未接入校园服务。'));
  }

  @override
  Future<Result<List<ServiceItem>>> fetchServiceCategoryItems(
    AppSession session, {
    required String cardWid,
    required ServiceCategory category,
  }) async {
    return const FailureResult(BusinessFailure('测试环境未接入校园服务分类。'));
  }

  @override
  Future<Result<ServiceLaunchData>> prepareServiceLaunch(
    AppSession session, {
    required ServiceItem item,
  }) async {
    final url = item.launchCandidates.isNotEmpty
        ? item.launchCandidates.first
        : '';
    if (url.isEmpty) {
      return const FailureResult(BusinessFailure('测试环境未接入服务跳转。'));
    }
    return Success(
      ServiceLaunchData(
        initialUrl: url,
        resolvedUrl: url,
        cookies: session.cookies,
      ),
    );
  }

  @override
  Future<Result<ElectricityDashboard>> fetchElectricityDashboard(
    AppSession session,
  ) async {
    return const FailureResult(BusinessFailure('测试环境未接入电费。'));
  }

  @override
  Future<Result<ExamScheduleSnapshot>> fetchExamSchedule(
    AppSession session, {
    String? termId,
  }) async {
    return const FailureResult(BusinessFailure('测试环境未接入考试安排。'));
  }

  @override
  Future<Result<GradesSnapshot>> fetchGrades(
    AppSession session, {
    String? termId,
  }) async {
    return const FailureResult(BusinessFailure('测试环境未接入成绩查询。'));
  }

  @override
  Future<Result<GymBookingOverview>> fetchGymBookingOverview(
    AppSession session, {
    required DateTime date,
  }) async {
    return const FailureResult(BusinessFailure('测试环境未接入体育馆预约。'));
  }

  @override
  Future<Result<ScheduleSnapshot>> fetchSchedule(
    AppSession session, {
    String? termId,
  }) async {
    return const FailureResult(BusinessFailure('测试环境未接入课表查询。'));
  }

  @override
  Future<Result<AppSession>> login(SchoolCredential credential) async {
    return Success(
      AppSession(
        userId: credential.username,
        displayName: credential.username,
        cookies: const [
          PortalCookie(
            name: 'CASTGC',
            value: 'testing',
            domain: 'authserver.wyu.edu.cn',
          ),
        ],
        issuedAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(hours: 8)),
        profile: PortalUserProfile(
          userName: credential.username,
          userAccount: credential.username,
        ),
      ),
    );
  }

  @override
  Future<Result<AppSession>> refreshSession(SchoolCredential credential) {
    return login(credential);
  }

  @override
  Future<Result<BookingRecord>> submitGymBooking(
    AppSession session, {
    required BookingDraft draft,
  }) async {
    return const FailureResult(BusinessFailure('测试环境未接入体育馆预约。'));
  }

  @override
  Future<Result<GymBookingEligibility>> checkGymBookingEligibility(
    AppSession session, {
    required BookingDraft draft,
  }) async {
    return const FailureResult(BusinessFailure('测试环境未接入预约校验。'));
  }

  @override
  Future<Result<List<BookingRecord>>> fetchMyGymAppointments(
    AppSession session, {
    int page = 1,
    int pageSize = 20,
  }) async {
    return const FailureResult(BusinessFailure('测试环境未接入体育馆预约。'));
  }

  @override
  Future<Result<GymAppointmentPage>> fetchMyGymAppointmentsPage(
    AppSession session, {
    required GymAppointmentQuery query,
  }) async {
    return const FailureResult(BusinessFailure('测试环境未接入体育馆预约。'));
  }

  @override
  Future<Result<GymVenueSearchPage>> searchGymVenues(
    AppSession session, {
    required GymVenueSearchQuery query,
  }) async {
    return const FailureResult(BusinessFailure('测试环境未接入体育馆预约。'));
  }

  @override
  Future<Result<AppointmentDetail>> fetchGymAppointmentDetail(
    AppSession session, {
    required String wid,
  }) async {
    return const FailureResult(BusinessFailure('测试环境未接入预约详情。'));
  }

  @override
  Future<Result<void>> cancelGymAppointment(
    AppSession session, {
    required String appointmentId,
    String? reason,
  }) async {
    return const FailureResult(BusinessFailure('测试环境未接入取消预约。'));
  }

  @override
  Future<Result<VenueDetail>> fetchGymRoomDetail(
    AppSession session, {
    required String wid,
  }) async {
    return const FailureResult(BusinessFailure('测试环境未接入场地详情。'));
  }

  @override
  Future<Result<VenueReviewPage>> fetchGymRoomReviews(
    AppSession session, {
    required String bizWid,
    int page = 1,
    int pageSize = 10,
  }) async {
    return const FailureResult(BusinessFailure('测试环境未接入场地评论。'));
  }

  @override
  Future<Result<GymSearchModel>> fetchGymSearchModel(AppSession session) async {
    return const FailureResult(BusinessFailure('测试环境未接入搜索模型。'));
  }

  @override
  Future<Result<void>> validateSession(AppSession session) async {
    return const Success(null);
  }
}
