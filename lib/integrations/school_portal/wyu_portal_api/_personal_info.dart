// 个人中心 (authserver/personalInfo) 相关接口：
// - 登录日志 / 应用访问 / 密码维护
// - 当前在线 + 踢出
// - IP 归属地查询
part of '../wyu_portal_api.dart';

extension WyuPortalPersonalInfo on WyuPortalApi {
  /// 在调用 personalInfo 下任意 ajax 接口之前，先 GET 一次首页跟随重定向。
  /// 这一步会让 authserver 给 personalInfo 子站盖上独立的 session cookie，
  /// 否则后续 ajax 全部 302 回 CAS。
  Future<void> _ensurePersonalInfoSession(_CookieStore cookieStore) async {
    if (_personalInfoReady.contains(cookieStore)) return;
    await _followGetRedirects(
      Uri.parse(_personalInfoIndexUrl),
      cookieStore,
    );
    _personalInfoReady.add(cookieStore);
  }

  /// operType: 0=认证 1=未知 2=密码 3=应用。
  Future<Result<UserLogPage>> queryUserLogs(
    AppSession session, {
    required UserLogType type,
    int pageIndex = 1,
    int pageSize = 10,
  }) async {
    final state = _stateForSession(session);
    final operType = switch (type) {
      UserLogType.authentication => 0,
      UserLogType.passwordMaintain => 2,
      UserLogType.appAccess => 3,
    };
    final body = <String, dynamic>{
      'operType': operType,
      'startTime': '',
      'endTime': '',
      'pageIndex': pageIndex,
      'pageSize': pageSize,
      'result': '',
      'typeCode': '',
      'n': _random.nextDouble().toString(),
    };
    if (type == UserLogType.appAccess) {
      body['appName'] = '';
      body['appId'] = '';
    } else if (type == UserLogType.authentication) {
      body['loginLocation'] = '';
    } else if (type == UserLogType.passwordMaintain) {
      body['appId'] = '';
    }

    try {
      await _ensurePersonalInfoSession(state.cookieStore);
      final response = await _postJson(
        Uri.parse(_userLogsUrl),
        body,
        state.cookieStore,
        extraHeaders: _personalInfoHeaders,
      );
      if (response.statusCode != 200) {
        return FailureResult(
          BusinessFailure('访问记录加载失败，状态码 ${response.statusCode}。'),
        );
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      if (json['code']?.toString() != '0') {
        final msg = json['message']?.toString() ?? '加载失败';
        return FailureResult(BusinessFailure(msg));
      }
      final datas = json['datas'] as Map<String, dynamic>? ?? const {};
      final total = (datas['total'] as num?)?.toInt() ?? 0;
      final list = (datas['data'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map((raw) => _parseUserLog(raw, type))
          .whereType<UserLogEntry>()
          .toList();
      return Success(UserLogPage(total: total, items: list));
    } on DioException catch (error, stackTrace) {
      return FailureResult(
        NetworkFailure(
          '网络异常，加载访问记录失败。',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    } catch (error, stackTrace) {
      return FailureResult(
        BusinessFailure(
          '访问记录解析失败。',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  Future<Result<List<OnlineSession>>> queryOnlineSessions(
    AppSession session,
  ) async {
    final state = _stateForSession(session);
    try {
      await _ensurePersonalInfoSession(state.cookieStore);
      final t = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final response = await _get(
        Uri.parse(_userOnlineUrl),
        state.cookieStore,
        queryParameters: {'t': '$t'},
      );
      // 302 = 服务端把 personalInfo 的 cookies 作废了。
      // 不能再当成普通 BusinessFailure，否则 UI 会显示"加载失败 状态码 302"，
      // 用户更看不懂。映射成 SessionExpiredFailure 让上层走"登录已过期"的统一文案。
      if (response.statusCode == 302) {
        _markCurrentSessionDead(session);
        return const FailureResult(SessionExpiredFailure('登录态已失效，请重新登录。'));
      }
      if (response.statusCode != 200) {
        return FailureResult(
          BusinessFailure('当前登录信息加载失败，状态码 ${response.statusCode}。'),
        );
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      if (json['code']?.toString() != '0') {
        return FailureResult(
          BusinessFailure(json['message']?.toString() ?? '加载失败'),
        );
      }
      final datas = json['datas'] as Map<String, dynamic>? ?? const {};
      final currentTgc = datas['currentBrowserTGC']?.toString() ?? '';
      final list = (datas['userOnline'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map((raw) => _parseOnlineSession(raw, currentTgc))
          .whereType<OnlineSession>()
          .toList();
      return Success(list);
    } on DioException catch (error, stackTrace) {
      return FailureResult(
        NetworkFailure(
          '网络异常，加载当前登录失败。',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    } catch (error, stackTrace) {
      return FailureResult(
        BusinessFailure(
          '当前登录解析失败。',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// 踢出某个在线会话。
  /// 返回值见 [KickOnlineResult]。
  ///
  /// 学校 authserver 对"踢自己"的反馈非常不稳定：
  /// - 多数时候 cookies 过期 + 302 跳到 CAS；
  /// - 偶尔会照样返回 200 + `code:"0"` 同时静默作废 cookies；
  /// - 列表里的 `isCurrent` 标记本身也不可靠（authserver 实际靠 token 字段
  ///   做匹配，但接口里 token 经常是 null）。
  ///
  /// 因此**不要**依赖 [isCurrent]/302 单一信号。这里的策略：
  /// 1) 调 removeUserOnline；
  /// 2) 若返回 302，直接判定 selfKicked；
  /// 3) 若返回 200 且 code=0，再做一次廉价的 queryUserOnline 探活；
  ///    如果探活返回 302（被踢回 CAS）就升级为 selfKicked，
  ///    否则才算真正的"踢了别人"。
  ///
  /// [isCurrent] 仅当作 UI 给的 hint 加速判断，不再作为唯一依据。
  Future<KickOnlineResult> kickOnlineSession(
    AppSession session, {
    required String id,
    bool isCurrent = false,
  }) async {
    final state = _stateForSession(session);
    try {
      await _ensurePersonalInfoSession(state.cookieStore);
      final response = await _postJson(
        Uri.parse(
          'https://authserver.wyu.edu.cn/personalInfo/UserOnline/user/removeUserOnline',
        ).replace(queryParameters: {'id': id}),
        {'n': _random.nextDouble().toString()},
        state.cookieStore,
        extraHeaders: _personalInfoHeaders,
      );

      // 1) 直接 302：肯定是 selfKick。
      if (response.statusCode == 302) {
        _logger.info('[SSO] kickOnlineSession 命中 302，判定 selfKicked');
        _markCurrentSessionDead(session);
        return KickOnlineResult.selfKicked;
      }

      if (response.statusCode != 200) {
        _logger.warn('[SSO] kickOnlineSession 非预期状态 ${response.statusCode}');
        return KickOnlineResult.error;
      }

      // 2) 200 但 code 非 0：业务失败。
      String? code;
      try {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        code = json['code']?.toString();
      } catch (_) {
        // 解析失败按宽松成功处理，进入 step 3 继续探活。
      }
      if (code != null && code != '0') {
        _logger.warn('[SSO] kickOnlineSession code=$code 视为业务失败');
        return KickOnlineResult.error;
      }

      // 3) 200 + code=0：探活看 cookies 是不是已经被作废。
      //    UI 提示 isCurrent=true 时直接当 selfKicked 跳过这一步，省一次往返。
      if (isCurrent) {
        _logger.info('[SSO] isCurrent=true，省略探活直接判定 selfKicked');
        _markCurrentSessionDead(session);
        return KickOnlineResult.selfKicked;
      }

      final probedSelfKick = await _probeSelfKickedAfterRemove(state);
      if (probedSelfKick) {
        _logger.info('[SSO] 探活命中 302，判定 selfKicked');
        _markCurrentSessionDead(session);
        return KickOnlineResult.selfKicked;
      }
      return KickOnlineResult.success;
    } on DioException {
      return KickOnlineResult.error;
    } catch (_) {
      return KickOnlineResult.error;
    }
  }

  /// 踢完之后立刻再 GET 一次 queryUserOnline。
  /// 若服务端返回 302 跳 CAS，说明 cookies 已经被作废 —— 即被踢自己。
  /// 这里不依赖正文，只看状态码 + Location，足够便宜。
  Future<bool> _probeSelfKickedAfterRemove(_RuntimeState state) async {
    try {
      final t = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final response = await _get(
        Uri.parse(_userOnlineUrl),
        state.cookieStore,
        queryParameters: {'t': '$t'},
      );
      if (response.statusCode == 302) {
        return true;
      }
      // 个别情况服务端返回 200 但正文是登录页 / code 非 0，也按已失效处理。
      if (response.statusCode == 200) {
        final body = response.body.trim();
        if (body.isEmpty) return false;
        try {
          final json = jsonDecode(body) as Map<String, dynamic>;
          final code = json['code']?.toString();
          // code 非 0 通常是 cookies 失效后服务端给的兜底错误，
          // 此时 message 会是"未登录"等。
          if (code != null && code != '0') {
            return true;
          }
        } catch (_) {
          // 不是 JSON：极可能是 CAS 登录 HTML。
          if (body.contains('统一身份认证') ||
              body.contains('/authserver/login')) {
            return true;
          }
        }
      }
      return false;
    } catch (_) {
      // 探活异常不当作 selfKick，避免误伤。
      return false;
    }
  }

  /// selfKick 公共清理：移除 runtimeStates + personalInfoReady 缓存。
  /// 抽出来防止两条分支只清一半。
  void _markCurrentSessionDead(AppSession session) {
    final removed = _runtimeStates.remove(session.userId);
    if (removed != null) {
      _personalInfoReady.remove(removed.cookieStore);
    }
  }

  /// 用学校 IP 归属地查询（无需登录态）。
  /// 返回 null 表示查询失败或拿不到。
  Future<String?> lookupIpLocation(String ip) async {
    if (ip.trim().isEmpty) return null;
    try {
      // 学校提供的 configIpAddress = https://ip.cn/?ip=
      // 直接走它结果是 HTML，解析麻烦。改走 ip.cn 的 JSON 接口（公开）。
      final response = await _dio.getUri<String>(
        Uri.parse('https://www.ip.cn/api/index?ip=$ip&type=0'),
        options: Options(
          headers: const {
            'Accept': 'application/json',
            'User-Agent':
                'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15',
          },
        ),
      );
      if (response.statusCode != 200) return null;
      final body = response.data;
      if (body == null) return null;
      final json = jsonDecode(body) as Map<String, dynamic>;
      final addr = json['address']?.toString();
      if (addr != null && addr.trim().isNotEmpty) return addr;
      return null;
    } catch (_) {
      return null;
    }
  }

  UserLogEntry? _parseUserLog(Map<String, dynamic> raw, UserLogType type) {
    try {
      switch (type) {
        case UserLogType.authentication:
          final ts = (raw['logintime'] as num?)?.toInt() ?? 0;
          final logoutTs = (raw['logouttime'] as num?)?.toInt();
          return UserLogEntry(
            id: raw['id']?.toString() ?? '',
            type: type,
            timestamp: DateTime.fromMillisecondsSinceEpoch(ts),
            timeLabel: raw['logintimeStr']?.toString() ?? '',
            success: (raw['result'] as num?)?.toInt() == 1,
            ip: raw['ip']?.toString() ?? '',
            title: raw['loginTypeDesc']?.toString() ?? '登录',
            subtitle: raw['loginname']?.toString(),
            location: raw['ipAddress']?.toString(),
            userAgent: raw['useragent']?.toString(),
            errorMessage: (raw['errorMsg']?.toString() ?? '').isEmpty
                ? null
                : raw['errorMsg']?.toString(),
            logoutTime: logoutTs == null
                ? null
                : DateTime.fromMillisecondsSinceEpoch(logoutTs),
            logoutTimeLabel: raw['logouttimeStr']?.toString(),
          );
        case UserLogType.appAccess:
          final ts = (raw['createtime'] as num?)?.toInt() ?? 0;
          return UserLogEntry(
            id: raw['id']?.toString() ?? '',
            type: type,
            timestamp: DateTime.fromMillisecondsSinceEpoch(ts),
            timeLabel: raw['createtimeStr']?.toString() ?? '',
            success: (raw['result'] as num?)?.toInt() == 1,
            ip: raw['clientIp']?.toString() ?? '',
            title: raw['appname']?.toString(),
            subtitle: raw['appurl']?.toString(),
            appUrl: raw['appurl']?.toString(),
          );
        case UserLogType.passwordMaintain:
          final ts = (raw['time'] as num?)?.toInt() ?? 0;
          return UserLogEntry(
            id: raw['id']?.toString() ?? '',
            type: type,
            timestamp: DateTime.fromMillisecondsSinceEpoch(ts),
            timeLabel: raw['timeStr']?.toString() ?? '',
            success: (raw['ifsuccess'] as num?)?.toInt() == 1,
            ip: raw['ip']?.toString() ?? '',
            title: raw['opertype']?.toString(),
            subtitle: raw['detail']?.toString(),
          );
      }
    } catch (_) {
      return null;
    }
  }

  OnlineSession? _parseOnlineSession(
    Map<String, dynamic> raw,
    String currentTgc,
  ) {
    try {
      final id = raw['id']?.toString() ?? '';
      final loginTs = (raw['logintime'] as num?)?.toInt() ?? 0;
      // currentBrowserTGC 形如 TGT-XXX-…null_main，无法直接和 id 对比；
      // authserver 实际通过 token 字段做匹配，但接口返回里 token 经常是 null。
      // 退而求其次：把"最早的那条且最近 30s 之内更新过"暂时不可靠，所以这里
      // 直接拿"useragent + clientType=1"过滤会更准；真要严格识别需另查。
      // 先按服务端是否回填 currentBrowserTGC 包含 id 做兜底。
      final isCurrent =
          currentTgc.isNotEmpty && currentTgc.contains(id.toUpperCase());
      return OnlineSession(
        id: id,
        ip: raw['ip']?.toString() ?? '',
        location: raw['ipAddress']?.toString() ?? '',
        userAgent: raw['useragent']?.toString() ?? '',
        loginTime: DateTime.fromMillisecondsSinceEpoch(loginTs),
        loginTimeLabel: raw['logintimeStr']?.toString() ?? '',
        loginTypeDesc: raw['loginTypeDesc']?.toString() ?? '',
        isCurrent: isCurrent,
      );
    } catch (_) {
      return null;
    }
  }
}
