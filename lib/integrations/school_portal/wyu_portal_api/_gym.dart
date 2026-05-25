// 体育馆预约系统：建立 SSO session、转发 lwWiseduCgyy 接口、代码表查询。
part of '../wyu_portal_api.dart';

extension WyuPortalGym on WyuPortalApi {
  Future<Result<dynamic>> fetchGymData(
    AppSession session, {
    required String path,
    Map<String, dynamic>? formFields,
  }) async {
    _logger.info(
      '[GYM] 准备请求体育馆接口 path=$path form=${_encodeForLog(formFields)}',
    );
    final state = _stateForSession(session);

    final sessionResult = await _ensureGymSession(session, state);
    if (sessionResult case FailureResult<void>(failure: final failure)) {
      return FailureResult(failure);
    }

    try {
      final uri = _resolveGymUri(path);
      final extraHeaders = <String, String>{
        'Referer': state.gymPcAccessUrl ?? 'https://ehall.wyu.edu.cn/',
        'X-Requested-With': 'XMLHttpRequest',
      };

      final response = await _postFormWithHeaders(
        uri,
        formFields ?? const {},
        state.cookieStore,
        extraHeaders,
      );

      if (response.statusCode != 200) {
        _logger.warn('[GYM] 请求失败 status=${response.statusCode}');
        return FailureResult(
          BusinessFailure('体育馆接口请求失败，状态码 ${response.statusCode}。'),
        );
      }

      final raw = response.body.trim();
      if (raw.isEmpty) {
        return const Success(null);
      }

      // 尝试 JSON 解析；不是 JSON（如 getFill 返回 "0.00"）就保留原文本。
      Object? decoded;
      try {
        decoded = jsonDecode(raw);
      } catch (_) {
        decoded = raw;
      }
      _logger.debug(
        '[GYM] 请求成功 path=$path response=${_encodeForLog(decoded)}',
      );
      return Success(decoded);
    } on DioException catch (error, stackTrace) {
      _logger.error(
        '[GYM] 体育馆接口请求失败 path=$path',
        error: error,
        stackTrace: stackTrace,
      );
      return FailureResult(
        NetworkFailure('体育馆接口请求失败。', cause: error, stackTrace: stackTrace),
      );
    } catch (error, stackTrace) {
      _logger.error(
        '[GYM] 体育馆接口解析失败 path=$path',
        error: error,
        stackTrace: stackTrace,
      );
      return FailureResult(
        ParsingFailure('体育馆接口响应解析失败。', cause: error, stackTrace: stackTrace),
      );
    }
  }

  Future<Result<dynamic>> fetchGymCodeData(
    AppSession session, {
    required String codeUrl,
    String method = 'POST',
  }) async {
    _logger.info('[GYM] 准备请求代码表 url=$codeUrl method=${method.toUpperCase()}');
    final state = _stateForSession(session);

    final sessionResult = await _ensureGymSession(session, state);
    if (sessionResult case FailureResult<void>(failure: final failure)) {
      return FailureResult(failure);
    }

    try {
      final uri = _normalizeGymUrl(codeUrl);
      final extraHeaders = <String, String>{
        'Referer': state.gymPcAccessUrl ?? 'https://ehall.wyu.edu.cn/',
        'X-Requested-With': 'XMLHttpRequest',
      };

      final response = switch (method.toUpperCase()) {
        'GET' => await _get(
          uri,
          state.cookieStore,
          queryParameters: {'_': DateTime.now().millisecondsSinceEpoch},
        ),
        _ => await _postFormWithHeaders(
          uri,
          const {},
          state.cookieStore,
          extraHeaders,
        ),
      };

      if (response.statusCode != 200) {
        return FailureResult(
          BusinessFailure('体育馆代码表请求失败，状态码 ${response.statusCode}。'),
        );
      }

      final raw = response.body.trim();
      if (raw.isEmpty) {
        return const Success(null);
      }

      return Success(jsonDecode(raw));
    } on DioException catch (error, stackTrace) {
      _logger.error(
        '[GYM] 体育馆代码表请求失败 url=$codeUrl',
        error: error,
        stackTrace: stackTrace,
      );
      return FailureResult(
        NetworkFailure('体育馆代码表请求失败。', cause: error, stackTrace: stackTrace),
      );
    } catch (error, stackTrace) {
      _logger.error(
        '[GYM] 体育馆代码表解析失败 url=$codeUrl',
        error: error,
        stackTrace: stackTrace,
      );
      return FailureResult(
        ParsingFailure('体育馆代码表响应解析失败。', cause: error, stackTrace: stackTrace),
      );
    }
  }

  Uri _resolveGymUri(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return Uri.parse(path);
    }
    if (path.startsWith('/sys/emapflow/')) {
      return Uri.parse('https://ehall.wyu.edu.cn/qljfwapp$path');
    }
    if (path.startsWith('/')) {
      return Uri.parse(
        'https://ehall.wyu.edu.cn/qljfwapp/sys/lwWiseduCgyy$path',
      );
    }
    return Uri.parse(
      'https://ehall.wyu.edu.cn/qljfwapp/sys/lwWiseduCgyy/${path.trimLeft()}',
    );
  }

  Uri _normalizeGymUrl(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return Uri.parse(url);
    }
    if (url.startsWith('/')) {
      return Uri.parse('https://ehall.wyu.edu.cn$url');
    }
    return Uri.parse('https://ehall.wyu.edu.cn/${url.trimLeft()}');
  }

  Future<String?> _fetchGymPcAccessUrl(_CookieStore cookieStore) async {
    try {
      // 先在顶层 appData 中查找
      final topResult = await _searchGymInServiceCard(
        cookieStore,
        typeId: null,
      );
      if (topResult != null) return topResult;

      // 未找到则深入「生活服务」分类查找
      _logger.info('[GYM] 顶层未找到，尝试「生活服务」分类 typeId=$_gymServiceTypeId');
      return _searchGymInServiceCard(cookieStore, typeId: _gymServiceTypeId);
    } catch (error, stackTrace) {
      _logger.error(
        '[GYM] 获取体育馆入口 URL 失败',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  Future<String?> _searchGymInServiceCard(
    _CookieStore cookieStore, {
    String? typeId,
  }) async {
    final uri = Uri.parse(
      'https://ehall.wyu.edu.cn/execCardMethod/$_serviceCardWid/SYS_CARD_SERVICEBUS?n=${_random.nextDouble()}',
    );
    final param = <String, dynamic>{'lang': 'zh_CN'};
    if (typeId != null) {
      param['typeId'] = typeId;
    }

    final response = await _postJson(uri, {
      'cardId': 'SYS_CARD_SERVICEBUS',
      'cardWid': _serviceCardWid,
      'method': 'renderData',
      'param': param,
    }, cookieStore);
    if (response.statusCode != 200) {
      _logger.warn('[GYM] 获取体育馆入口 URL 失败 status=${response.statusCode}');
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
      if (appName == '体育场馆预约') {
        final pcUrl = _stringValue(svc['pcAccessUrl']);
        if (pcUrl != null) {
          _logger.info(
            '[GYM] 从 ehall 获取到 pcAccessUrl: $pcUrl '
            '(typeId=${typeId ?? 'top'})',
          );
          return pcUrl;
        }
      }
    }

    _logger.warn(
      '[GYM] 未在 ehall 服务列表中找到体育场馆预约 '
      '(typeId=${typeId ?? 'top'})',
    );
    return null;
  }

  Future<Result<void>> _ensureGymSession(
    AppSession session,
    _RuntimeState state,
  ) async {
    if (state.gymPcAccessUrl != null) {
      _logger.debug('[GYM] 复用已缓存的 gym session');
      return const Success(null);
    }

    try {
      final pcAccessUrl = await _fetchGymPcAccessUrl(state.cookieStore);
      if (pcAccessUrl == null) {
        return const FailureResult(SessionExpiredFailure('未能获取体育馆预约系统入口地址。'));
      }

      _logger.info('[GYM] 建立体育馆预约应用态 pcAccessUrl=$pcAccessUrl');
      final uri = Uri.parse(pcAccessUrl);
      var response = await _get(uri, state.cookieStore);

      if (response.statusCode == 302 && response.location != null) {
        response = await _followGetRedirects(
          response.uri.resolve(response.location!),
          state.cookieStore,
        );
      }

      if (response.statusCode != 200) {
        _logger.warn('[GYM] 访问体育馆入口失败 status=${response.statusCode}');
        return FailureResult(
          BusinessFailure('体育馆预约系统访问失败，状态码 ${response.statusCode}。'),
        );
      }

      state.gymPcAccessUrl = pcAccessUrl;
      _logger.info('[GYM] 体育馆预约应用态建立成功');
      return const Success(null);
    } on DioException catch (error, stackTrace) {
      _logger.error('[GYM] 建立体育馆预约会话失败', error: error, stackTrace: stackTrace);
      return FailureResult(
        NetworkFailure('建立体育馆预约会话失败。', cause: error, stackTrace: stackTrace),
      );
    }
  }
}
