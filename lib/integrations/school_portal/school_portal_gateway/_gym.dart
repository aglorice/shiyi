// 体育馆预约系统对外接口集合 + 解析逻辑。
// 这是 Gateway 里最重的一个子领域：
// - 概览 / 搜索 / 我的预约（分页 + 客户端再过一道脏数据）
// - 提交流程（getSjdByRoom / getFill / checkSelfTodayYyData / checkCanApply
//   / startFlow / insertSelfToZtry，多轮串行请求）
// - 取消流程（qxPay / deleteZtcyYyData / T_WISEDU_CGYY_YY_SAVE）
// - 详情、评论、搜索模型、代码表
part of '../school_portal_gateway.dart';

mixin _GymGateway on _GatewayBase implements SchoolPortalGateway {
  /// 内存级 code 候选项缓存。key=codeUrl。
  /// 这些代码表（场馆类型/项目/状态）极少变动，一次会话内复用即可。
  /// 注意：mixin 里的字段会成为类的实例字段，跨调用共享。
  final Map<String, List<GymFilterOption>> _codeCache = {};

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

    final normalized = _normalizeDate(date);
    final weekday = normalized.weekday; // Monday=1, Sunday=7
    final weekMonday = normalized.subtract(Duration(days: weekday - 1));
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
    final flowId = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    _logger.info(
      '[Gym][Submit][$flowId] 开始提交预约 userId=${session.userId} '
      'venue="${draft.venue.name}" venueWid=${draft.venue.id} '
      'bizWid=${draft.bizWid ?? draft.venue.bizWid} '
      'date=${_formatDate(draft.date)} slot=${draft.slot.timeLabel} '
      'phone=${draft.phone ?? '-'}',
    );

    final validation = await validateSession(session);
    if (validation.isFailure) {
      _logger.warn(
        '[Gym][Submit][$flowId] 会话校验失败 '
        'reason=${validation.failureOrNull?.message}',
      );
      return FailureResult(validation.failureOrNull!);
    }

    // 同一份 formData（含 VERIFICATION/timestamp）必须在 checkCanApply 与
    // startFlow 之间共享，否则两次请求的 VERIFICATION 不一致会被后端拒绝。
    final formData = _buildGymApplyFormData(draft);
    _logger.infoBlock(
      '[Gym][Submit][$flowId] formData',
      _prettyJson(formData),
    );

    // ---- 0. getSjdByRoom ----
    // 拿这天该场地"实时剩余可约"的时段集合。比 getOpeningRoom.do 的 day1..day7
    // 更准确——已经被别人订掉/锁定的时段不会出现。
    // 如果用户选的 SYSJ 不在最新可约列表里，直接返回，省一次 checkCanApply 往返
    // 也避免给学校系统额外的风控压力。
    final venueRoomId = draft.venue.id;
    final sysj = formData['SYSJ']?.toString() ?? draft.slot.timeLabel;
    if (venueRoomId.isNotEmpty) {
      final dateStr = formData['YYRQ']?.toString() ?? _formatDate(draft.date);
      _logger.info(
        '[Gym][Submit][$flowId] >>> POST /modules/application/getSjdByRoom.do '
        'roomId=$venueRoomId applyDate=$dateStr',
      );
      final slotResult = await _portalApi.fetchGymData(
        session,
        path: '/modules/application/getSjdByRoom.do',
        formFields: {'applyDate': dateStr, 'roomId': venueRoomId},
      );
      if (slotResult case FailureResult<dynamic>(failure: final failure)) {
        _logger.warn(
          '[Gym][Submit][$flowId] <<< getSjdByRoom 网络失败 '
          'reason=${failure.message}（继续走 checkCanApply 兜底）',
        );
      } else {
        final raw = slotResult.dataOrNull;
        List<String> available = const [];
        if (raw is List) {
          available = raw
              .map((item) => item?.toString().trim() ?? '')
              .where((item) => item.isNotEmpty)
              .toList();
        }
        _logger.infoBlock(
          '[Gym][Submit][$flowId] getSjdByRoom response',
          _prettyJson(available),
        );
        if (available.isNotEmpty && !available.contains(sysj)) {
          _logger.warn(
            '[Gym][Submit][$flowId] getSjdByRoom 命中冲突 '
            '需要时段=$sysj 实时可约=${available.join(',')}',
          );
          return const FailureResult(BusinessFailure('该时段已被占用，请换一个时段。'));
        }
      }
    }

    // ---- 0a. getFill ----
    // 正式网页提交前会先 POST /modules/pay/getFill.do 拿到这次预约对应的金额，
    // 返回是纯文本/数字字面量（例如 "0.00"），仅用于前端展示「费用」并把
    // 用户视为「已查看费用须知」。哪怕金额是 0 也要打这一下，否则部分场地
    // 后续会以「未确认费用」拒绝预约。
    final fillFields = <String, dynamic>{
      'BIZ_WID': formData['BIZ_WID']?.toString() ?? '',
      'SYSJ': sysj,
    };
    _logger.info('[Gym][Submit][$flowId] >>> POST /modules/pay/getFill.do');
    _logger.infoBlock(
      '[Gym][Submit][$flowId] getFill request body',
      _prettyJson(fillFields),
    );
    final fillResult = await _portalApi.fetchGymData(
      session,
      path: '/modules/pay/getFill.do',
      formFields: fillFields,
    );
    if (fillResult case FailureResult<dynamic>(failure: final failure)) {
      _logger.warn(
        '[Gym][Submit][$flowId] <<< getFill 网络失败 '
        'reason=${failure.message}',
      );
      // 这一步是「告诉后端用户已查看费用」，单纯失败不阻断主流程，
      // 但要记录下来方便排查。
    } else {
      _logger.info(
        '[Gym][Submit][$flowId] <<< getFill 返回金额=${fillResult.dataOrNull}',
      );
    }

    // ---- 0b. checkSelfTodayYyData ----
    // 这一步对应正式网页提交前的"今日是否已预约"自检。
    // 如果当天已经有预约，后端会在这里直接返回非空 rows，
    // 走到 checkCanApply 反而会拿到容易误导用户的错误。
    final selfCheckFields = <String, dynamic>{
      'YYRQ': formData['YYRQ']?.toString() ?? _formatDate(draft.date),
    };
    _logger.info(
      '[Gym][Submit][$flowId] >>> POST '
      '/modules/application/checkSelfTodayYyData.do',
    );
    _logger.infoBlock(
      '[Gym][Submit][$flowId] checkSelfTodayYyData request body',
      _prettyJson(selfCheckFields),
    );
    final selfCheckResult = await _portalApi.fetchGymData(
      session,
      path: '/modules/application/checkSelfTodayYyData.do',
      formFields: selfCheckFields,
    );
    if (selfCheckResult case FailureResult<dynamic>(failure: final failure)) {
      _logger.warn(
        '[Gym][Submit][$flowId] <<< checkSelfTodayYyData 网络失败 '
        'reason=${failure.message}',
      );
      return FailureResult(failure);
    }
    _logger.infoBlock(
      '[Gym][Submit][$flowId] checkSelfTodayYyData response',
      _prettyJson(selfCheckResult.dataOrNull),
    );
    final existingCount = _extractGymRows(
      selfCheckResult.dataOrNull,
      dataKey: 'checkSelfTodayYyData',
    ).length;
    if (existingCount > 0) {
      const msg = '当天已存在预约记录，无法再次预约。';
      _logger.warn(
        '[Gym][Submit][$flowId] checkSelfTodayYyData 命中已有预约 count=$existingCount',
      );
      return const FailureResult(BusinessFailure(msg));
    }
    _logger.info('[Gym][Submit][$flowId] checkSelfTodayYyData 无冲突');

    // ---- 1. checkCanApply ----
    _logger.info(
      '[Gym][Submit][$flowId] >>> POST /modules/application/checkCanApply.do',
    );
    _logger.infoBlock(
      '[Gym][Submit][$flowId] checkCanApply request body',
      _prettyJson(formData),
    );
    final checkResult = await _portalApi.fetchGymData(
      session,
      path: '/modules/application/checkCanApply.do',
      formFields: formData,
    );
    if (checkResult case FailureResult<dynamic>(failure: final failure)) {
      _logger.warn(
        '[Gym][Submit][$flowId] <<< checkCanApply 网络失败 '
        'reason=${failure.message}',
      );
      return FailureResult(failure);
    }
    _logger.infoBlock(
      '[Gym][Submit][$flowId] checkCanApply response',
      _prettyJson(checkResult.dataOrNull),
    );

    final eligibilityResult = _parseGymEligibility(checkResult.dataOrNull);
    if (eligibilityResult case FailureResult<GymBookingEligibility>(
      failure: final failure,
    )) {
      _logger.warn(
        '[Gym][Submit][$flowId] checkCanApply 解析失败 '
        'reason=${failure.message}',
      );
      return FailureResult(failure);
    }
    if (eligibilityResult.dataOrNull?.canApply != true) {
      final msg = eligibilityResult.dataOrNull?.message ?? '预约校验未通过。';
      _logger.warn(
        '[Gym][Submit][$flowId] checkCanApply 拒绝预约 reason=$msg',
      );
      return FailureResult(BusinessFailure(msg));
    }
    _logger.info('[Gym][Submit][$flowId] checkCanApply 通过');

    // ---- 2. startFlow ----
    final startFlowFields = <String, dynamic>{
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
    };
    _logger.info(
      '[Gym][Submit][$flowId] >>> POST /sys/emapflow/tasks/startFlow.do',
    );
    _logger.infoBlock(
      '[Gym][Submit][$flowId] startFlow request body',
      _prettyJson(startFlowFields),
    );
    final startFlowResult = await _portalApi.fetchGymData(
      session,
      path: '/sys/emapflow/tasks/startFlow.do',
      formFields: startFlowFields,
    );
    if (startFlowResult case FailureResult<dynamic>(failure: final failure)) {
      _logger.warn(
        '[Gym][Submit][$flowId] <<< startFlow 网络失败 '
        'reason=${failure.message}',
      );
      return FailureResult(failure);
    }
    _logger.infoBlock(
      '[Gym][Submit][$flowId] startFlow response',
      _prettyJson(startFlowResult.dataOrNull),
    );

    final submitData = startFlowResult.dataOrNull;
    if (submitData is Map<String, dynamic>) {
      final succeed = submitData['succeed'];
      if (succeed == false || succeed == 'false') {
        final msg =
            _pickString(submitData, const ['msg', 'message']) ?? '预约提交失败。';
        _logger.warn(
          '[Gym][Submit][$flowId] startFlow succeed=false reason=$msg',
        );
        return FailureResult(BusinessFailure(msg));
      }
    }
    _logger.info('[Gym][Submit][$flowId] startFlow 成功');

    // ---- 3. insertSelfToZtry ----
    // startFlow 成功后必须再写一条同行人记录（申请人本人入 ZTRY），否则
    // 服务端会把这条预约视为"未完成同行人登记"而清掉/隐藏，
    // 表现就是"刚刚预约成功，过几分钟就查不到"。
    final applyWid = formData['WID'] as String?;
    if (applyWid != null && applyWid.isNotEmpty) {
      final ztryFields = <String, dynamic>{
        'APPLY_WID': applyWid,
        'USER_ID': session.userId,
        // 注意：是 BY5=1，不是 BY51。这个字段对应模型里的"是否提交"标记，
        // 抓包里值固定为 1，缺失会导致后端把这条预约视为"未完成同行人登记"
        // 直接置为已取消（详情页就会出现"刚预约就已取消"的现象）。
        'BY5': '1',
      };
      _logger.info(
        '[Gym][Submit][$flowId] >>> POST '
        '/modules/application/insertSelfToZtry.do',
      );
      _logger.infoBlock(
        '[Gym][Submit][$flowId] insertSelfToZtry request body',
        _prettyJson(ztryFields),
      );
      final ztryResult = await _portalApi.fetchGymData(
        session,
        path: '/modules/application/insertSelfToZtry.do',
        formFields: ztryFields,
      );
      if (ztryResult case FailureResult<dynamic>(failure: final failure)) {
        _logger.warn(
          '[Gym][Submit][$flowId] <<< insertSelfToZtry 网络失败 '
          'reason=${failure.message}',
        );
      } else {
        _logger.infoBlock(
          '[Gym][Submit][$flowId] insertSelfToZtry response',
          _prettyJson(ztryResult.dataOrNull),
        );
        final ztryData = ztryResult.dataOrNull;
        if (ztryData is Map<String, dynamic>) {
          final code = _pickString(ztryData, const ['code']);
          if (code != null && code != '0') {
            _logger.warn(
              '[Gym][Submit][$flowId] insertSelfToZtry 返回非成功 code=$code '
              'msg=${_pickString(ztryData, const ['msg', 'message'])}',
            );
          }
        }
      }
    } else {
      _logger.warn(
        '[Gym][Submit][$flowId] formData 中 WID 为空，跳过 insertSelfToZtry',
      );
    }

    _logger.info(
      '[Gym][Submit][$flowId] 提交流程完成 venue="${draft.venue.name}" '
      'slot=${draft.slot.timeLabel}',
    );

    // 远端列表里同一个 (venueName, slot, date) 经常会有多条记录——
    // 包括同场地同时段反复预约/取消形成的历史脏数据。
    // 不能简单"匹配第一条就返回"，否则会把上一次取消的记录当成本次结果。
    // 优先级：
    //   1. effective 状态是"未使用"
    //   2. 申请时间（SQSJ）最新
    //   3. 实在挑不到，使用占位记录，由后续 invalidate 修正
    final refreshedRecords = await fetchMyGymAppointments(
      session,
      page: 1,
      pageSize: 20,
    );
    if (refreshedRecords case Success<List<BookingRecord>>(
      data: final records,
    )) {
      final candidates = records.where((record) {
        return record.venueName == draft.venue.name &&
            record.slotLabel == draft.slot.timeLabel &&
            _normalizeDate(record.date) == _normalizeDate(draft.date);
      }).toList();

      _logger.info(
        '[Gym][Submit][$flowId] 远端列表命中候选 ${candidates.length} 条',
      );

      // 先在 effective=001（真正"未使用"）里挑最新的。
      BookingRecord? best;
      for (final record in candidates) {
        if (record.effectiveStatusCode != '001') {
          continue;
        }
        if (best == null) {
          best = record;
          continue;
        }
        final left = best.submittedAt;
        final right = record.submittedAt;
        if (left == null) {
          best = record;
        } else if (right != null && right.isAfter(left)) {
          best = record;
        }
      }

      if (best != null) {
        _logger.info(
          '[Gym][Submit][$flowId] 已在远端列表确认到新记录 '
          'recordId=${best.recordId} wid=${best.id} '
          'submittedAt=${best.submittedAt}',
        );
        return Success(best);
      }

      // 走到这说明：startFlow 返回 succeed=true，但远端列表里同
      // (场地 + 日期 + 时段) 的所有记录都已经处于"已取消/已使用"。
      // 实测情况下，学校后端会在以下场景静默拒约（即便 startFlow 显示 ok）：
      //   - 用户处于违约冷冻期（SFWY=1，WYXZTS 未结束）
      //   - 一周内同一项目预约次数已达上限
      //   - 同一时段已被自己或他人占用
      // 这种新记录创建出来就直接是 PAY_STATUS=CG_QX，
      // 详情页里继承的取消时间是上一次的，看起来就像"预约后立刻被自动取消"。
      // 与其返回成功让用户误会，不如直接告诉用户"系统拒约"。
      if (candidates.isNotEmpty) {
        BookingRecord newest = candidates.first;
        for (final record in candidates) {
          final left = newest.submittedAt;
          final right = record.submittedAt;
          if (left == null) {
            newest = record;
          } else if (right != null && right.isAfter(left)) {
            newest = record;
          }
        }
        _logger.warn(
          '[Gym][Submit][$flowId] 远端候选全部为非"未使用"状态，'
          'newest=${newest.recordId} effectiveStatus=${newest.effectiveStatus} '
          'payStatus=${newest.payStatusCode} 视为系统拒约',
        );
        final hint = newest.violation == '是' || newest.violation == '1'
            ? '系统拒绝预约：当前可能处于违约冷冻期。请稍后再试或换一个项目。'
            : '系统已自动取消该预约，可能受违约冷冻、次数上限或时段冲突限制。';
        return FailureResult(BusinessFailure(hint));
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

    // 服务端在按 SYZT 过滤时，没有把 PAY_STATUS=CG_QX 的脏数据排除掉。
    // 例如点"未使用"也会拉到 SYZT=001 + PAY_STATUS=CG_QX 的旧记录，
    // 这些记录在详情接口里实际是已取消状态。
    // 因此当用户显式选了状态，再用客户端的 effectiveStatusCode 过一道。
    final effectiveRecords =
        query.statusCode == null || query.statusCode!.isEmpty
            ? records
            : records
                .where((record) => record.effectiveStatusCode == query.statusCode)
                .toList();
    final filteredOut = records.length - effectiveRecords.length;
    if (filteredOut > 0) {
      _logger.info(
        '[Gateway] 客户端过滤掉 $filteredOut 条与状态 ${query.statusCode} 不一致的脏数据',
      );
    }

    final pageData = GymAppointmentPage(
      query: query,
      records: effectiveRecords,
      // totalSize 减去本页被过滤掉的条数，避免"远程总数 30，但实际显示 22"的违和感。
      totalSize: paging.totalSize - filteredOut,
      fetchedAt: DateTime.now(),
      origin: DataOrigin.remote,
    );
    _logger.info(
      '[Gateway] 我的场馆预约加载完成 count=${effectiveRecords.length} '
      'rawTotal=${paging.totalSize}',
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
          // 用综合状态填充详情，避免列表里"未使用 + PAY_STATUS=CG_QX"的脏数据
          // 让详情页错误地显示"未使用"。
          detail = AppointmentDetail(
            id: detail.id,
            venueName: detail.venueName,
            address: detail.address,
            slotLabel: detail.slotLabel,
            date: detail.date,
            status: record.effectiveStatus,
            statusCode: record.effectiveStatusCode,
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
            canCancel: record.isCancellable,
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
    final flowId = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    _logger.info(
      '[Gym][Cancel][$flowId] 开始取消预约 userId=${session.userId} '
      'wid=$appointmentId reason="${reason ?? '-'}"',
    );

    final validation = await validateSession(session);
    if (validation.isFailure) {
      _logger.warn(
        '[Gym][Cancel][$flowId] 会话校验失败 '
        'reason=${validation.failureOrNull?.message}',
      );
      return FailureResult(validation.failureOrNull!);
    }

    final now = DateTime.now();
    final qxsj =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';

    // ---- 1. qxPay ----
    // 抓包顺序里的第一步。这里走的是缴费网关的"取消订单"，对个人非付费预约
    // 通常返回 epay 通用 code（例如 #E2140600091, msg: epay.wisedu.edu.cn），
    // 表示"无支付订单需要取消"，**不视为错误**，不阻断主流程。
    final qxPayFields = <String, dynamic>{'WID': appointmentId};
    _logger.info('[Gym][Cancel][$flowId] >>> POST /modules/pay/qxPay.do');
    _logger.infoBlock(
      '[Gym][Cancel][$flowId] qxPay request body',
      _prettyJson(qxPayFields),
    );
    final qxPayResult = await _portalApi.fetchGymData(
      session,
      path: '/modules/pay/qxPay.do',
      formFields: qxPayFields,
    );
    if (qxPayResult case FailureResult<dynamic>(failure: final failure)) {
      _logger.warn(
        '[Gym][Cancel][$flowId] <<< qxPay 网络失败 reason=${failure.message}（继续）',
      );
    } else {
      _logger.infoBlock(
        '[Gym][Cancel][$flowId] qxPay response',
        _prettyJson(qxPayResult.dataOrNull),
      );
    }

    // ---- 2. deleteZtcyYyData ----
    // 抓包顺序里的第二步。把同行人表里的记录清掉。
    // 失败也不阻塞主流程，只记录 warn。
    final deleteFields = <String, dynamic>{'APPLY_WID': appointmentId};
    _logger.info(
      '[Gym][Cancel][$flowId] >>> POST '
      '/modules/myApplication/deleteZtcyYyData.do',
    );
    _logger.infoBlock(
      '[Gym][Cancel][$flowId] deleteZtcyYyData request body',
      _prettyJson(deleteFields),
    );
    final ztryResult = await _portalApi.fetchGymData(
      session,
      path: '/modules/myApplication/deleteZtcyYyData.do',
      formFields: deleteFields,
    );
    if (ztryResult case FailureResult<dynamic>(failure: final failure)) {
      _logger.warn(
        '[Gym][Cancel][$flowId] <<< deleteZtcyYyData 网络失败 '
        'reason=${failure.message}（继续）',
      );
    } else {
      _logger.infoBlock(
        '[Gym][Cancel][$flowId] deleteZtcyYyData response',
        _prettyJson(ztryResult.dataOrNull),
      );
      final ztryData = ztryResult.dataOrNull;
      if (ztryData is Map<String, dynamic>) {
        final code = _pickString(ztryData, const ['code']);
        if (code != null && code != '0') {
          _logger.warn(
            '[Gym][Cancel][$flowId] deleteZtcyYyData 返回非成功 code=$code '
            'msg=${_pickString(ztryData, const ['msg', 'message'])}',
          );
        }
      }
    }

    // ---- 3. T_WISEDU_CGYY_YY_SAVE ----
    // 真正落库的取消动作。前面两步是清理动作，这一步成功才算取消完成。
    final saveFields = <String, dynamic>{
      'WID': appointmentId,
      'QXYY': (reason == null || reason.isEmpty) ? '0' : reason,
      'QXSJ': qxsj,
      'SYZT': '003',
      'PAY_STATUS': 'CG_QX',
    };
    _logger.info(
      '[Gym][Cancel][$flowId] >>> POST '
      '/modules/myApplication/T_WISEDU_CGYY_YY_SAVE.do',
    );
    _logger.infoBlock(
      '[Gym][Cancel][$flowId] T_WISEDU_CGYY_YY_SAVE request body',
      _prettyJson(saveFields),
    );
    final result = await _portalApi.fetchGymData(
      session,
      path: '/modules/myApplication/T_WISEDU_CGYY_YY_SAVE.do',
      formFields: saveFields,
    );

    if (result case FailureResult<dynamic>(failure: final failure)) {
      _logger.warn(
        '[Gym][Cancel][$flowId] <<< T_WISEDU_CGYY_YY_SAVE 网络失败 '
        'reason=${failure.message}',
      );
      return FailureResult(failure);
    }
    _logger.infoBlock(
      '[Gym][Cancel][$flowId] T_WISEDU_CGYY_YY_SAVE response',
      _prettyJson(result.dataOrNull),
    );

    final data = result.dataOrNull;
    if (data is Map<String, dynamic>) {
      final code = _pickString(data, const ['code']);
      if (code != null && code != '0') {
        final msg = _pickString(data, const ['msg', 'message']) ?? '取消预约失败。';
        _logger.warn(
          '[Gym][Cancel][$flowId] T_WISEDU_CGYY_YY_SAVE 业务失败 '
          'code=$code msg=$msg',
        );
        return FailureResult(BusinessFailure(msg));
      }
    }

    _logger.info('[Gym][Cancel][$flowId] 取消流程完成 wid=$appointmentId');
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

  @override
  Future<Result<GymSearchModel>> fetchGymSearchModel(AppSession session) async {
    return _fetchSearchModel(
      session,
      path: '/modules/application/getRoomOrderSearchModel.do',
      logTag: '场馆搜索模型',
    );
  }

  @override
  Future<Result<GymSearchModel>> fetchGymAppointmentSearchModel(
    AppSession session,
  ) async {
    return _fetchSearchModel(
      session,
      path: '/modules/myApplication/getMyAppointmentListData.do',
      logTag: '我的预约搜索模型',
    );
  }

  Future<Result<GymSearchModel>> _fetchSearchModel(
    AppSession session, {
    required String path,
    required String logTag,
  }) async {
    _logger.info('[Gateway] 加载$logTag');
    final validation = await validateSession(session);
    if (validation.isFailure) {
      return FailureResult(validation.failureOrNull!);
    }

    final result = await _portalApi.fetchGymData(
      session,
      path: path,
      formFields: {'*searchMeta': '1'},
    );
    if (result case FailureResult<dynamic>(failure: final failure)) {
      return FailureResult(failure);
    }

    final model = await _parseSearchModel(session, result.dataOrNull);
    _logger.info('[Gateway] $logTag加载完成 controls=${model.controls.length}');
    return Success(model);
  }

  @override
  Future<Result<List<GymFilterOption>>> fetchGymCodeOptions(
    AppSession session, {
    required String codeUrl,
  }) async {
    final normalized = codeUrl.trim();
    if (normalized.isEmpty) {
      return const FailureResult(BusinessFailure('代码表 URL 为空。'));
    }
    final cached = _codeCache[normalized];
    if (cached != null) {
      return Success(cached);
    }

    final validation = await validateSession(session);
    if (validation.isFailure) {
      return FailureResult(validation.failureOrNull!);
    }

    var options = <GymFilterOption>[];
    final remotePost = await _portalApi.fetchGymCodeData(
      session,
      codeUrl: normalized,
      method: 'POST',
    );
    if (remotePost case Success<dynamic>(data: final data)) {
      options = _parseRemoteFilterOptions(data);
    }
    if (options.isEmpty) {
      final remoteGet = await _portalApi.fetchGymCodeData(
        session,
        codeUrl: normalized,
        method: 'GET',
      );
      if (remoteGet case Success<dynamic>(data: final data)) {
        options = _parseRemoteFilterOptions(data);
      }
    }

    if (options.isEmpty) {
      return const FailureResult(ParsingFailure('代码表候选项为空。'));
    }

    final deduped = _deduplicateFilterOptions(options);
    _codeCache[normalized] = deduped;
    return Success(deduped);
  }

  @override
  Future<Result<List<String>>> fetchGymRoomAvailableSlots(
    AppSession session, {
    required String roomId,
    required DateTime applyDate,
  }) async {
    if (roomId.trim().isEmpty) {
      return const FailureResult(BusinessFailure('roomId 为空。'));
    }
    final validation = await validateSession(session);
    if (validation.isFailure) {
      return FailureResult(validation.failureOrNull!);
    }

    final dateStr = _formatDate(applyDate);
    final fields = <String, dynamic>{
      'applyDate': dateStr,
      'roomId': roomId,
    };
    _logger.info(
      '[Gym] >>> POST /modules/application/getSjdByRoom.do '
      'roomId=$roomId applyDate=$dateStr',
    );
    final result = await _portalApi.fetchGymData(
      session,
      path: '/modules/application/getSjdByRoom.do',
      formFields: fields,
    );
    if (result case FailureResult<dynamic>(failure: final failure)) {
      _logger.warn('[Gym] <<< getSjdByRoom 失败 reason=${failure.message}');
      return FailureResult(failure);
    }

    // 接口返回是裸数组：["18:00-19:20","19:20-20:40", ...]
    final raw = result.dataOrNull;
    if (raw is List) {
      final slots = raw
          .map((item) => item?.toString().trim() ?? '')
          .where((item) => item.isNotEmpty)
          .toList();
      _logger.info('[Gym] <<< getSjdByRoom 命中 ${slots.length} 个可约时段');
      return Success(slots);
    }
    // 兜底：包了 datas/code 结构时尝试再解一层。
    if (raw is Map<String, dynamic>) {
      for (final key in const ['datas', 'data']) {
        final value = raw[key];
        if (value is List) {
          final slots = value
              .map((item) => item?.toString().trim() ?? '')
              .where((item) => item.isNotEmpty)
              .toList();
          _logger.info('[Gym] <<< getSjdByRoom 命中 ${slots.length} 个可约时段');
          return Success(slots);
        }
      }
    }
    _logger.warn('[Gym] <<< getSjdByRoom 响应格式无法识别 raw=$raw');
    return const Success(<String>[]);
  }

  // -------------------- 解析助手 --------------------

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
    final normalizedTarget =
        targetDate == null ? null : _normalizeDate(targetDate);
    final fallbackCapacity = _pickInt(row, const ['RNRS', 'capacity']) ?? 1;
    final now = DateTime.now();
    final today = _normalizeDate(now);

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

      // 过去日期一律跳过：体育馆系统不会让你约昨天的场。
      if (slotDate.isBefore(today)) {
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
        final startStr = parts[0].trim();
        final endStr = parts[1].trim();

        // 当天时段：起始时间已经到了/过了就不再放出来。
        // 这一步是"过了那个时段还能预约"的根因修复。
        if (slotDate == today) {
          final start = _parseTimeOnDate(slotDate, startStr);
          if (start != null && !start.isAfter(now)) {
            continue;
          }
        }

        slots.add(
          BookableSlot(
            id: '${venueId}_${slotDate.toIso8601String()}_$trimmed',
            startTime: startStr,
            endTime: endStr,
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

  DateTime? _parseTimeOnDate(DateTime date, String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) {
      return null;
    }
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) {
      return null;
    }
    return DateTime(date.year, date.month, date.day, hour, minute);
  }

  Map<String, dynamic> _buildGymApplyFormData(BookingDraft draft) {
    final yyrq = _formatDate(draft.date);
    final sysj = draft.slot.timeLabel;
    final bizWid = draft.bizWid ?? draft.venue.bizWid;
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final raw = '${draft.userAccount}$yyrq$sysj${bizWid}_WISEDU_$timestamp';
    final encoded = Uri.encodeComponent(raw);
    final verification = base64Encode(utf8.encode(encoded));

    // 关键：formData 里的 WID 不是场地 WID，而是「本次申请」的全新 UUID。
    // 学校前端 JS 里用的是 `g_wid = $.UUID()`，每次进预约表单都会新生成一个 32 位无连字符 UUID。
    // 之前我们把 draft.venue.id 直接当 WID 用，等于复用了场地 WID，
    // 后端会把这次提交识别为「对同一个 application 的重新提交」，
    // 把上一次的 PAY_STATUS=CG_QX、QXYY、QXSJ 全部带回来，
    // 表现就是「明明预约成功了，详情页却显示上次的取消信息」。
    final applyWid = _generateApplyWid();

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
      'WID': applyWid,
      'XGH': draft.userAccount,
      'BIZ_WID': bizWid,
      'SYZT': '001',
      'VERIFICATION': verification,
      'BCSQRS': 1,
      'USERID': draft.userAccount,
    };
  }

  /// 生成 32 位无连字符的随机 hex 串，对齐学校前端的 `$.UUID()` 输出。
  /// 例如：8f6d57b6e9a7489c823403e2e1c443e3
  String _generateApplyWid() {
    const hex = '0123456789abcdef';
    final buffer = StringBuffer();
    for (var i = 0; i < 32; i++) {
      buffer.write(hex[_random.nextInt(16)]);
    }
    return buffer.toString();
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
        'linkOpt': 'AND',
        'builderList': 'cbl_m_List',
        'builder': 'm_value_equal',
        'value': query.statusCode,
        'value_display': switch (query.statusCode) {
          '001' => '未使用',
          '002' => '已使用',
          '003' => '已取消',
          _ => query.statusCode,
        },
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
    final recordId = _pickString(map, const ['ID_', 'PROC_INST_ID_']);
    final bizWid = _pickString(map, const ['BIZ_WID', 'bizWid']);

    if (venueName == null) return null;

    final statusRaw = _pickString(map, const ['SYZT']);
    final statusDisplay = _pickString(map, const ['SYZT_DISPLAY']);
    final status =
        _gymStatusToLabel(statusRaw) ?? statusDisplay ?? statusRaw ?? '未知';

    final payStatusRaw = _pickString(map, const ['PAY_STATUS']);
    final payStatusDisplay = _pickString(map, const ['PAY_STATUS_DISPLAY']);
    final flowStatusRaw = _pickString(map, const ['FLOW_STATUS_']);
    final flowStatusDisplay = _pickString(map, const ['FLOW_STATUS__DISPLAY']);
    final venueTypeCode = _pickString(map, const ['HYSLX']);
    final venueTypeDisplay = _pickString(map, const ['HYSLX_DISPLAY']);
    final violation = _pickString(map, const ['SFWY_DISPLAY', 'SFWY']);

    DateTime? date;
    if (yyrq != null) {
      date = DateTime.tryParse(yyrq);
    }

    final sqsj = _pickString(map, const ['SQSJ']);
    DateTime? submittedAt;
    if (sqsj != null && sqsj.isNotEmpty) {
      // 学校系统返回 "yyyy-MM-dd HH:mm:ss"，DateTime.parse 不接受空格分隔，转一下。
      submittedAt = DateTime.tryParse(sqsj.replaceFirst(' ', 'T'));
    }

    // 取消按钮的可点性：
    // 1) 综合状态必须是"未使用"（兼顾 PAY_STATUS=CG_QX 的脏数据）
    // 2) 预约时段尚未开始
    final isPendingStatus = statusRaw == '001' && payStatusRaw != 'CG_QX';
    final slotNotStarted = _isSlotInFuture(date, sysj);
    final canCancel = isPendingStatus && slotNotStarted;

    return BookingRecord(
      id: wid,
      venueName: venueName,
      slotLabel: sysj ?? '时段未知',
      date: date ?? DateTime.now(),
      status: status,
      statusCode: statusRaw,
      canCancel: canCancel,
      recordId: recordId,
      bizWid: bizWid,
      payStatusCode: payStatusRaw,
      payStatusDisplay: payStatusDisplay,
      flowStatusCode: flowStatusRaw,
      flowStatusDisplay: flowStatusDisplay,
      venueTypeCode: venueTypeCode,
      venueTypeDisplay: venueTypeDisplay,
      submittedAt: submittedAt,
      violation: violation,
    );
  }

  /// 判断"预约日期 + SYSJ 起始时间"是否仍在未来。null 当作不限制返回 true。
  bool _isSlotInFuture(DateTime? date, String? sysj) {
    if (date == null) {
      return true;
    }
    final start = sysj?.split('-').first.trim();
    if (start == null || start.isEmpty) {
      // 没有时段信息时按"当天 00:00 之前不可取消"宽松处理：
      // 只要日期不是过去日期就允许。
      final today = DateTime(
        DateTime.now().year,
        DateTime.now().month,
        DateTime.now().day,
      );
      return !DateTime(date.year, date.month, date.day).isBefore(today);
    }
    final parts = start.split(':');
    if (parts.length != 2) {
      return true;
    }
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) {
      return true;
    }
    final slotStart = DateTime(date.year, date.month, date.day, hour, minute);
    return slotStart.isAfter(DateTime.now());
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

  VenueReview? _mapVenueReview(Map<String, dynamic> map) {
    final id = _pickString(map, const ['WID', 'wid']) ?? '';
    // 接口实际返回 `YYRXM`（预约人姓名）。之前漏读这个字段，所有评论都
    // 退化成兜底的 "匿名"。这里把 YYRXM 放在第一优先级，保留 XM/CZRXM
    // 兼容其他可能的接口形态。
    final rawUserName = _pickString(
      map,
      const ['YYRXM', 'XM', 'userName', 'CZRXM'],
    );
    final userName = _maskName(rawUserName);
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

  /// 中文姓名脱敏：保留首字 + 末字，中间用 `·` 替代。
  /// - "彭艳婷" → "彭·婷"
  /// - "陈安娜" → "陈·娜"
  /// - "袁琳" → "袁·"（两字名只保首字）
  /// - 单字 / 空 → "匿名"
  /// 避免出现真名外泄到陌生用户面前，又比"匿名"二字保留了一点存在感。
  String _maskName(String? raw) {
    if (raw == null) return '匿名';
    final name = raw.trim();
    if (name.isEmpty) return '匿名';
    if (name.length == 1) return '匿名';
    if (name.length == 2) return '${name[0]}·';
    return '${name[0]}·${name[name.length - 1]}';
  }

  // -------------------- 搜索模型 / code 候选项解析 --------------------

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
}
