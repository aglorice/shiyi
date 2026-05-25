// 研究生教务系统 (yjsc.wyu.edu.cn)：通过 ehall 拿到入口 URL，
// 走 CAS 拿 Service Ticket，最后从重定向 URL 抠出 SessionId 持久化。
part of '../wyu_portal_api.dart';

extension WyuPortalYjs on WyuPortalApi {
  Future<Result<dynamic>> fetchYjsData(
    AppSession session, {
    required String path,
    required String method,
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? formFields,
  }) async {
    _logger.info(
      '[YJS] 准备请求教务接口 method=${method.toUpperCase()} path=$path '
      'query=${_encodeForLog(queryParameters)} form=${_encodeForLog(formFields)}',
    );
    final state = _stateForSession(session);
    final sidResult = await _ensureYjsSession(session, state);
    if (sidResult case FailureResult<String>(failure: final failure)) {
      _logger.warn('[YJS] 无法获取教务 session reason=${failure.message}');
      return FailureResult(failure);
    }

    final firstAttempt = await _requestYjs(
      state: state,
      sessionId: sidResult.dataOrNull!,
      path: path,
      method: method,
      queryParameters: queryParameters,
      formFields: formFields,
    );
    if (firstAttempt.isSuccess) {
      _logger.debug('[YJS] 教务接口首次请求成功 path=$path');
      return firstAttempt;
    }

    _logger.warn('[YJS] 教务接口首次请求失败，尝试刷新 session path=$path');
    state.yjsSessionId = null;
    final refreshedSid = await _ensureYjsSession(session, state);
    if (refreshedSid case FailureResult<String>(failure: final failure)) {
      _logger.warn('[YJS] 教务 session 刷新失败 reason=${failure.message}');
      return FailureResult(failure);
    }

    return _requestYjs(
      state: state,
      sessionId: refreshedSid.dataOrNull!,
      path: path,
      method: method,
      queryParameters: queryParameters,
      formFields: formFields,
    );
  }

  Future<Result<dynamic>> _requestYjs({
    required _RuntimeState state,
    required String sessionId,
    required String path,
    required String method,
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? formFields,
  }) async {
    try {
      final uri = Uri.parse('https://yjsc.wyu.edu.cn/(S($sessionId))$path');
      _logger.debug(
        '[YJS] 发起教务请求 sessionId=${_maskShort(sessionId)} '
        'method=${method.toUpperCase()} uri=$uri',
      );
      final response = switch (method.toUpperCase()) {
        'POST' => await _postForm(
          uri,
          formFields ?? const {},
          state.cookieStore,
        ),
        _ => await _get(
          uri,
          state.cookieStore,
          queryParameters: queryParameters,
        ),
      };

      if (response.statusCode == 302 || _looksLikeHtml(response.body)) {
        _logger.warn(
          '[YJS] 教务响应疑似失效 status=${response.statusCode} '
          'location=${response.location} body=${_summarizeBody(response.body)}',
        );
        return const FailureResult(SessionExpiredFailure('教务系统会话已失效。'));
      }

      final raw = response.body.trim();
      if (raw.isEmpty) {
        _logger.debug('[YJS] 教务响应为空 path=$path');
        return const Success(null);
      }

      try {
        final decrypted = _decryptYjsPayload(raw);
        final decoded = jsonDecode(decrypted);
        _logger.debug(
          '[YJS] 教务响应解密成功 path=$path decrypted=${_summarizeBody(decrypted)} parsed=${_encodeForLog(decoded)}',
        );
        return Success(decoded);
      } catch (decryptError, decryptStackTrace) {
        _logger.warn(
          '[YJS] 教务响应 AES 解密失败，尝试按明文 JSON 解析 '
          'path=$path raw=${_summarizeBody(raw)}',
        );
        _logger.debug(
          '[YJS] 解密失败原因 error=$decryptError stackTrace=$decryptStackTrace',
        );
        try {
          final decoded = jsonDecode(raw);
          _logger.debug(
            '[YJS] 教务响应按明文 JSON 解析成功 path=$path parsed=${_encodeForLog(decoded)}',
          );
          return Success(decoded);
        } catch (error, stackTrace) {
          _logger.error(
            '[YJS] 教务响应最终解析失败 path=$path raw=${_summarizeBody(raw)}',
            error: error,
            stackTrace: stackTrace,
          );
          return FailureResult(
            ParsingFailure('教务系统响应解密失败。', cause: error, stackTrace: stackTrace),
          );
        }
      }
    } on DioException catch (error, stackTrace) {
      _logger.error(
        '[YJS] 访问研究生教务系统失败 path=$path',
        error: error,
        stackTrace: stackTrace,
      );
      return FailureResult(
        NetworkFailure('访问研究生教务系统失败。', cause: error, stackTrace: stackTrace),
      );
    }
  }

  Future<Result<String>> _ensureYjsSession(
    AppSession session,
    _RuntimeState state,
  ) async {
    final runtimeSid = state.yjsSessionId;
    if (runtimeSid != null && runtimeSid.isNotEmpty) {
      _logger.debug(
        '[YJS] 复用运行时 sessionId=${_maskShort(runtimeSid)} userId=${session.userId}',
      );
      return Success(runtimeSid);
    }

    if (session.yjsSessionId != null && session.yjsSessionId!.isNotEmpty) {
      state.yjsSessionId = session.yjsSessionId;
      _logger.debug(
        '[YJS] 复用持久化 sessionId=${_maskShort(session.yjsSessionId)} userId=${session.userId}',
      );
      return Success(session.yjsSessionId!);
    }

    _logger.info('[YJS] 当前无可用 session，准备通过 SSO 进入教务系统');
    return _initYjsSession(session.userId, state.cookieStore);
  }

  Future<String?> _fetchYjsPcAccessUrl(_CookieStore cookieStore) async {
    try {
      final uri = Uri.parse(
        'https://ehall.wyu.edu.cn/execCardMethod/$_yjsServiceCardWid/SYS_CARD_SERVICEBUS?n=${_random.nextDouble()}',
      );
      final response = await _postJson(uri, {
        'cardId': 'SYS_CARD_SERVICEBUS',
        'cardWid': _yjsServiceCardWid,
        'method': 'renderData',
        'param': {'lang': 'zh_CN'},
      }, cookieStore);
      if (response.statusCode != 200) {
        _logger.warn('[YJS] 获取研究生系统入口 URL 失败 status=${response.statusCode}');
        return null;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;
      final data = decoded['data'];
      if (data is! Map<String, dynamic>) return null;
      final appData = data['appData'];
      if (appData is! List) return null;

      for (final svc in appData) {
        if (svc is! Map<String, dynamic>) continue;
        final appName = svc['appName'] ?? svc['serviceName'];
        if (appName == '研究生系统') {
          final pcUrl = _stringValue(svc['pcAccessUrl']);
          if (pcUrl != null) {
            _logger.info('[YJS] 从 ehall 获取到 pcAccessUrl: $pcUrl');
            return pcUrl;
          }
        }
      }
      _logger.warn('[YJS] 未在 ehall 服务列表中找到研究生系统');
      return null;
    } catch (error, stackTrace) {
      _logger.error(
        '[YJS] 获取研究生系统入口 URL 失败',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  Future<Result<String>> _initYjsSession(
    String userId,
    _CookieStore cookieStore,
  ) async {
    try {
      _logger.info('[YJS] 通过 SSO 进入研究生教务系统 userId=$userId');

      // Step 1: 从 ehall 动态获取研究生系统的 pcAccessUrl
      final pcAccessUrl = await _fetchYjsPcAccessUrl(cookieStore);
      if (pcAccessUrl == null) {
        return const FailureResult(SessionExpiredFailure('未能获取研究生教务系统入口地址。'));
      }

      // Step 2: pcAccessUrl 可能返回 http，yjsc 需要 https，
      // 否则 HTTP→HTTPS 重定向会消耗 ticket
      var serviceUrl = pcAccessUrl;
      if (serviceUrl.startsWith('http://')) {
        serviceUrl = 'https://${serviceUrl.substring(7)}';
      }

      // Step 3: 利用已有的 TGT cookie，请求 CAS 获取 yjsc 的 Service Ticket
      final casUri = _buildLoginUri(service: serviceUrl);
      _logger.info('[YJS] 通过 CAS 获取教务系统 session service=$serviceUrl');
      final casResp = await _get(casUri, cookieStore);
      _logger.info(
        '[YJS] CAS 响应 status=${casResp.statusCode} location=${casResp.location}',
      );
      if (casResp.statusCode != 302 ||
          casResp.location == null ||
          casResp.location!.isEmpty) {
        _logger.warn('[YJS] CAS 未返回重定向，可能 TGT 已失效');
        return const FailureResult(SessionExpiredFailure('CAS 认证失败，请重新登录。'));
      }

      // Step 4: 访问 yjsc 验证 ST
      final ticketUrl = casResp.uri.resolve(casResp.location!);
      final yjscResp = await _get(ticketUrl, cookieStore);
      _logger.info(
        '[YJS] yjsc 验证 ST status=${yjscResp.statusCode} location=${yjscResp.location}',
      );
      if (yjscResp.statusCode != 302 ||
          yjscResp.location == null ||
          yjscResp.location!.isEmpty) {
        _logger.warn('[YJS] yjsc 验证 ST 后未重定向');
        return const FailureResult(
          SessionExpiredFailure('教务系统 Service Ticket 验证失败。'),
        );
      }

      // Step 5: 从重定向 URL 提取 Session ID（Location 可能是相对路径）
      var location = yjscResp.location!;
      if (location.startsWith('/')) {
        location = 'https://yjsc.wyu.edu.cn$location';
      }
      _logger.info('[YJS] 最终 URL: $location');

      final sid = _extractYjsSessionId(location);
      if (sid == null || sid.isEmpty) {
        _logger.warn('[YJS] 未能从重定向 URL 中提取 session url=$location');
        return const FailureResult(SessionExpiredFailure('未能建立研究生教务系统会话。'));
      }

      // Step 6: 访问最终 URL 完成会话建立
      await _get(Uri.parse(location), cookieStore);

      final state = _runtimeStates[userId];
      if (state != null) {
        state.yjsSessionId = sid;
      }
      _logger.info('[YJS] 教务系统 session 建立成功 sessionId=${_maskShort(sid)}');
      return Success(sid);
    } on DioException catch (error, stackTrace) {
      _logger.error(
        '[YJS] 初始化研究生教务系统会话失败',
        error: error,
        stackTrace: stackTrace,
      );
      return FailureResult(
        NetworkFailure('初始化研究生教务系统会话失败。', cause: error, stackTrace: stackTrace),
      );
    }
  }

  String _decryptYjsPayload(String ciphertextBase64) {
    final encrypter = encrypt.Encrypter(
      encrypt.AES(_yjsAesKey, mode: encrypt.AESMode.ecb, padding: 'PKCS7'),
    );
    return encrypter.decrypt64(ciphertextBase64);
  }

  String? _extractYjsSessionId(String input) {
    final match = RegExp(r'\(S\(([^)]+)\)\)').firstMatch(input);
    return match?.group(1);
  }
}
