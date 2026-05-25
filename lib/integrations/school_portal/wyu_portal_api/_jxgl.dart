// 本科生教务系统 (jxgl.wyu.edu.cn) 接口转发与 SSO 建立。
part of '../wyu_portal_api.dart';

extension WyuPortalJxgl on WyuPortalApi {
  Future<Result<dynamic>> fetchJxglData(
    AppSession session, {
    required String path,
    Map<String, dynamic>? formFields,
  }) async {
    _logger.info(
      '[JXGL] 准备请求教务接口 path=$path form=${_encodeForLog(formFields)}',
    );
    final state = _stateForSession(session);

    final sessionResult = await _ensureJxglSession(session, state);
    if (sessionResult case FailureResult<void>(failure: final failure)) {
      return FailureResult(failure);
    }

    final firstAttempt = await _requestJxgl(
      state: state,
      path: path,
      formFields: formFields,
    );
    if (firstAttempt.isSuccess) {
      _logger.debug('[JXGL] 教务接口首次请求成功 path=$path');
      return firstAttempt;
    }

    _logger.warn('[JXGL] 教务接口首次请求失败，尝试刷新 session path=$path');
    state.jxglPcAccessUrl = null;
    final refreshedSession = await _ensureJxglSession(session, state);
    if (refreshedSession case FailureResult<void>(failure: final failure)) {
      _logger.warn('[JXGL] 教务 session 刷新失败 reason=${failure.message}');
      return FailureResult(failure);
    }

    return _requestJxgl(state: state, path: path, formFields: formFields);
  }

  Future<String?> _fetchJxglPcAccessUrl(_CookieStore cookieStore) async {
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
        _logger.warn('[JXGL] 获取教务系统入口 URL 失败 status=${response.statusCode}');
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
        if (appName == '教务系统') {
          final pcUrl = _stringValue(svc['pcAccessUrl']);
          if (pcUrl != null) {
            _logger.info('[JXGL] 从 ehall 获取到 pcAccessUrl: $pcUrl');
            return pcUrl;
          }
        }
      }
      _logger.warn('[JXGL] 未在 ehall 服务列表中找到教务系统');
      return null;
    } catch (error, stackTrace) {
      _logger.error(
        '[JXGL] 获取教务系统入口 URL 失败',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  Future<Result<void>> _ensureJxglSession(
    AppSession session,
    _RuntimeState state,
  ) async {
    if (state.jxglPcAccessUrl != null) {
      _logger.debug('[JXGL] 复用已缓存的 jxgl session');
      return const Success(null);
    }

    try {
      final pcAccessUrl = await _fetchJxglPcAccessUrl(state.cookieStore);
      if (pcAccessUrl == null) {
        return const FailureResult(SessionExpiredFailure('未能获取教务系统入口地址。'));
      }

      _logger.info('[JXGL] 建立教务系统应用态 pcAccessUrl=$pcAccessUrl');
      final uri = Uri.parse(pcAccessUrl);
      var response = await _get(uri, state.cookieStore);

      if (response.statusCode == 302 && response.location != null) {
        response = await _followGetRedirects(
          response.uri.resolve(response.location!),
          state.cookieStore,
        );
      }

      if (response.statusCode != 200) {
        _logger.warn('[JXGL] 访问教务系统入口失败 status=${response.statusCode}');
        return FailureResult(
          BusinessFailure('教务系统访问失败，状态码 ${response.statusCode}。'),
        );
      }

      state.jxglPcAccessUrl = pcAccessUrl;
      _logger.info('[JXGL] 教务系统应用态建立成功');
      return const Success(null);
    } on DioException catch (error, stackTrace) {
      _logger.error('[JXGL] 建立教务系统会话失败', error: error, stackTrace: stackTrace);
      return FailureResult(
        NetworkFailure('建立教务系统会话失败。', cause: error, stackTrace: stackTrace),
      );
    }
  }

  Future<Result<dynamic>> _requestJxgl({
    required _RuntimeState state,
    required String path,
    Map<String, dynamic>? formFields,
  }) async {
    try {
      final uri = Uri.parse('https://jxgl.wyu.edu.cn$path');
      final extraHeaders = <String, String>{
        'Referer': state.jxglPcAccessUrl ?? 'https://ehall.wyu.edu.cn/',
        'X-Requested-With': 'XMLHttpRequest',
      };

      _logger.debug(
        '[JXGL] 发起教务请求 uri=$uri form=${_encodeForLog(formFields)}',
      );
      final response = await _postFormWithHeaders(
        uri,
        formFields ?? const {},
        state.cookieStore,
        extraHeaders,
      );

      if (response.statusCode != 200) {
        _logger.warn(
          '[JXGL] 教务响应失败 status=${response.statusCode} '
          'body=${_summarizeBody(response.body)}',
        );
        return FailureResult(
          BusinessFailure('教务系统请求失败，状态码 ${response.statusCode}。'),
        );
      }

      final raw = response.body.trim();
      if (raw.isEmpty) {
        _logger.debug('[JXGL] 教务响应为空 path=$path');
        return const Success(null);
      }
      if (_looksLikeHtml(raw) || _looksLikeLoginPage(raw)) {
        _logger.warn(
          '[JXGL] 教务响应疑似失效 status=${response.statusCode} '
          'body=${_summarizeBody(raw)}',
        );
        return const FailureResult(SessionExpiredFailure('教务系统会话已失效。'));
      }

      try {
        final decoded = jsonDecode(raw);
        if (_looksLikeJxglSessionExpiredPayload(decoded)) {
          _logger.warn(
            '[JXGL] 教务响应提示尚未登录 path=$path '
            'parsed=${_encodeForLog(decoded)}',
          );
          return const FailureResult(SessionExpiredFailure('教务系统会话已失效。'));
        }
        _logger.debug(
          '[JXGL] 教务响应解析成功 path=$path parsed=${_encodeForLog(decoded)}',
        );
        return Success(decoded);
      } catch (error, stackTrace) {
        _logger.error(
          '[JXGL] 教务响应解析失败 path=$path raw=${_summarizeBody(raw)}',
          error: error,
          stackTrace: stackTrace,
        );
        return FailureResult(
          ParsingFailure('教务系统响应解析失败。', cause: error, stackTrace: stackTrace),
        );
      }
    } on DioException catch (error, stackTrace) {
      _logger.error(
        '[JXGL] 访问教务系统失败 path=$path',
        error: error,
        stackTrace: stackTrace,
      );
      return FailureResult(
        NetworkFailure('访问教务系统失败。', cause: error, stackTrace: stackTrace),
      );
    }
  }
}
