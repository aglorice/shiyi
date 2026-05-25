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
  /// 学校 authserver 的同一个接口对"踢自己"的反馈不是稳定的：
  /// - 大多数时候会让当前 cookies 过期并 302 跳到登录页；
  /// - 偶尔（实测高峰期）会照样返回 200 + `code:"0"` 同时静默失效 cookies。
  ///
  /// 因此 [isCurrent] 必须由 UI 显式传入：当踢的是 isCurrent=true 的会话
  /// 时，无论 200 还是 302 都按 [KickOnlineResult.selfKicked] 处理，
  /// 这样调用方可以稳定地走"清本地 + 回登录页"逻辑。
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

      // 踢自己：302 是最确定的信号；isCurrent=true 时 200 也按 selfKick。
      final selfKicked =
          response.statusCode == 302 || (isCurrent && response.statusCode == 200);
      if (selfKicked) {
        // 即便 200，本地也要把这条 session 关联的 cookieStore 一并清掉，
        // 否则下一次请求还是会带着已经被服务端作废的 cookies 出去。
        final removed = _runtimeStates.remove(session.userId);
        if (removed != null) {
          _personalInfoReady.remove(removed.cookieStore);
        }
        return KickOnlineResult.selfKicked;
      }

      if (response.statusCode != 200) {
        return KickOnlineResult.error;
      }
      try {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final code = json['code']?.toString();
        if (code == '0') {
          return KickOnlineResult.success;
        }
        return KickOnlineResult.error;
      } catch (_) {
        // 主体 JSON 解析失败但状态 200，认为成功（极少数情况）。
        return KickOnlineResult.success;
      }
    } on DioException {
      return KickOnlineResult.error;
    } catch (_) {
      return KickOnlineResult.error;
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
