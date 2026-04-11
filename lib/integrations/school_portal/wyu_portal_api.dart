import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:encrypt/encrypt.dart' as encrypt;

import '../../core/error/failure.dart';
import '../../core/logging/app_logger.dart';
import '../../core/result/result.dart';
import '../../modules/auth/domain/entities/app_session.dart';
import '../../modules/auth/domain/entities/school_credential.dart';
import '../../modules/services/domain/entities/service_card_data.dart';
import '../../modules/services/domain/entities/service_launch_data.dart';
import 'sso/credential_transformer.dart';

class WyuPortalApi {
  WyuPortalApi({
    required CredentialTransformer transformer,
    required AppLogger logger,
    required String userAgent,
  }) : _transformer = transformer,
       _logger = logger,
       _dio = Dio(
         BaseOptions(
           connectTimeout: const Duration(seconds: 20),
           receiveTimeout: const Duration(seconds: 20),
           followRedirects: false,
           maxRedirects: 0,
           responseType: ResponseType.plain,
           validateStatus: (_) => true,
           headers: {'User-Agent': userAgent},
         ),
       );

  static const _portalServiceUrl = 'https://ehall.wyu.edu.cn/login';
  static const _serviceCardWid = '8558486040491173';
  static const _yjsServiceCardWid = '017434820995445355';
  static const _defaultYjsServiceWid = '1268168848874270720';
  static final _loginUri = Uri.parse(
    'https://authserver.wyu.edu.cn/authserver/login',
  );
  static final _yjsAesKey = encrypt.Key.fromUtf8('southsoft12345!#');

  final CredentialTransformer _transformer;
  final AppLogger _logger;
  final Dio _dio;
  final Random _random = Random();
  final Map<String, _RuntimeState> _runtimeStates = {};

  Future<Result<AppSession>> login(SchoolCredential credential) async {
    if (credential.username.trim().isEmpty || credential.password.isEmpty) {
      return const FailureResult(AuthenticationFailure('学号和密码不能为空。'));
    }

    final cookieStore = _CookieStore();
    _logger.info(
      '[SSO] 开始统一认证登录 username=${credential.maskedUsername} service=$_portalServiceUrl',
    );

    try {
      final loginPage = await _get(
        _buildLoginUri(service: _portalServiceUrl),
        cookieStore,
      );
      if (loginPage.statusCode != 200) {
        return FailureResult(
          AuthenticationFailure('登录页访问失败，状态码 ${loginPage.statusCode}。'),
        );
      }

      final formData = _parseLoginForm(loginPage.body);
      _logger.debug(
        '[SSO] 登录页字段 '
        'pwdEncryptSalt=${_maskShort(formData.pwdEncryptSalt)} '
        'lt=${_maskShort(formData.lt)} '
        'execution=${_maskShort(formData.execution, keepStart: 10, keepEnd: 10)}',
      );
      final payload = {
        'username': credential.username.trim(),
        'password': _transformer.encryptPassword(
          credential.password,
          formData.pwdEncryptSalt,
        ),
        '_eventId': 'submit',
        'cllt': 'userNameLogin',
        'dllt': 'generalLogin',
        'lt': formData.lt,
        'execution': formData.execution,
      };

      var response = await _postForm(
        _buildLoginUri(service: _portalServiceUrl),
        payload,
        cookieStore,
      );

      if (response.statusCode == 200 && _looksLikeKickOutPage(response.body)) {
        response = await _handleKickOut(response.body, cookieStore);
      }

      if (response.statusCode != 302) {
        _logger.warn('[SSO] 登录提交未返回 302，准备解析失败原因。');
        return FailureResult(_mapLoginFailure(response.body));
      }

      final location = response.location;
      if (location != null && location.contains('needCaptcha')) {
        return const FailureResult(AuthenticationFailure('当前账号需要验证码登录。'));
      }

      if (location != null && location.isNotEmpty) {
        await _followGetRedirects(response.uri.resolve(location), cookieStore);
      }

      final profileResult = await _fetchUserProfileFromStore(cookieStore);
      if (profileResult case FailureResult<PortalUserProfile>(
        failure: final f,
      )) {
        return FailureResult(f);
      }

      final profile = profileResult.dataOrNull!;
      final services = await _fetchServiceLinksFromStore(cookieStore);
      final yjsSessionId = (await _initYjsSession(
        credential.username.trim(),
        cookieStore,
      )).dataOrNull;

      final session = AppSession(
        userId: credential.username.trim(),
        displayName: profile.userName.isEmpty
            ? credential.username.trim()
            : profile.userName,
        cookies: cookieStore.snapshot(),
        issuedAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(hours: 8)),
        profile: profile,
        serviceLinks: services.dataOrNull ?? const [],
        yjsSessionId: yjsSessionId,
      );

      _runtimeStates[session.userId] = _RuntimeState(
        cookieStore: _CookieStore(session.cookies),
        yjsSessionId: session.yjsSessionId,
      );
      _logger.info(
        '[SSO] 登录成功 username=${credential.maskedUsername} '
        'displayName=${session.displayName} '
        'cookies=${_cookieSnapshotSummary(session.cookies)} '
        'serviceCount=${session.serviceLinks.length} '
        'yjsSessionId=${_maskShort(session.yjsSessionId)}',
      );
      return Success(session);
    } on DioException catch (error, stackTrace) {
      _logger.error('[SSO] 访问学校门户失败', error: error, stackTrace: stackTrace);
      return FailureResult(
        NetworkFailure(
          '访问学校门户失败，请检查网络连接。',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    } catch (error, stackTrace) {
      _logger.error('[SSO] 学校统一认证登录失败', error: error, stackTrace: stackTrace);
      return FailureResult(
        AuthenticationFailure(
          '学校统一认证登录失败。',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  Future<Result<void>> validateSession(AppSession session) async {
    if (session.cookies.isEmpty) {
      return const FailureResult(SessionExpiredFailure('登录态缺失，无法继续访问学校门户。'));
    }

    if (session.isExpired) {
      return const FailureResult(SessionExpiredFailure('登录态已过期，需要重新认证。'));
    }

    _logger.info(
      '[SESSION] 开始校验 session userId=${session.userId} expiresAt=${session.expiresAt.toIso8601String()} '
      'cookieCount=${session.cookies.length}',
    );
    final state = _stateForSession(session);
    final profile = await _fetchUserProfileFromStore(state.cookieStore);
    if (profile case FailureResult<PortalUserProfile>(failure: final failure)) {
      _logger.warn('[SESSION] session 校验失败 reason=${failure.message}');
      return FailureResult(
        SessionExpiredFailure(
          failure.message,
          cause: failure.cause,
          stackTrace: failure.stackTrace,
        ),
      );
    }

    _logger.info(
      '[SESSION] session 校验成功 userId=${session.userId} userAccount=${profile.dataOrNull?.userAccount}',
    );
    return const Success(null);
  }

  Future<Result<List<PortalServiceLink>>> fetchServiceLinks(
    AppSession session,
  ) async {
    final state = _stateForSession(session);
    return _fetchServiceLinksFromStore(state.cookieStore);
  }

  Future<Result<ServiceLaunchData>> prepareServiceLaunch(
    AppSession session, {
    required ServiceItem item,
  }) async {
    final state = _stateForSession(session);
    if (_isYjsServiceItem(item)) {
      final yjsLaunch = await _prepareYjsServiceLaunch(
        session: session,
        state: state,
      );
      if (yjsLaunch != null) {
        return yjsLaunch;
      }
    }

    final candidates = item.launchCandidates;
    if (candidates.isEmpty) {
      return const FailureResult(BusinessFailure('该服务暂无可用入口。'));
    }

    Failure? lastFailure;
    for (final candidate in candidates) {
      final normalized = _normalizeServiceUrl(candidate);
      final launch = await _resolveServiceLaunch(
        cookieStore: state.cookieStore,
        serviceUrl: normalized,
      );
      if (launch case Success<String>(data: final resolvedUrl)) {
        final resolvedUri = Uri.parse(resolvedUrl);
        return Success(
          ServiceLaunchData(
            initialUrl: normalized,
            resolvedUrl: resolvedUrl,
            cookies: _cookiesForLaunchUri(
              state.cookieStore.snapshot(),
              resolvedUri,
            ),
          ),
        );
      }
      lastFailure = launch.failureOrNull;
    }

    return FailureResult(
      lastFailure ?? const BusinessFailure('该服务当前无法完成单点登录。'),
    );
  }

  Future<Result<ServiceLaunchData>?> _prepareYjsServiceLaunch({
    required AppSession session,
    required _RuntimeState state,
  }) async {
    final sidResult = await _initYjsSession(session.userId, state.cookieStore);
    if (sidResult case FailureResult<String>(failure: final failure)) {
      return FailureResult(failure);
    }

    final sessionId = sidResult.requireValue();
    final resolvedUri = Uri.parse(
      'https://yjsc.wyu.edu.cn/(S($sessionId))/student/default/index',
    );
    _logger.info('[YJS] 使用专用入口打开研究生系统 uri=$resolvedUri');
    return Success(
      ServiceLaunchData(
        initialUrl: resolvedUri.toString(),
        resolvedUrl: resolvedUri.toString(),
        cookies: _cookiesForLaunchUri(
          state.cookieStore.snapshot(),
          resolvedUri,
        ),
      ),
    );
  }

  Future<Result<Map<String, dynamic>>> fetchServiceCardData(
    AppSession session,
    String cardWid, {
    String? typeId,
  }) async {
    final state = _stateForSession(session);
    try {
      final uri = Uri.parse(
        'https://ehall.wyu.edu.cn/execCardMethod/$cardWid/SYS_CARD_SERVICEBUS?n=${_random.nextDouble()}',
      );
      final normalizedTypeId = typeId?.trim() ?? '';
      final param = <String, dynamic>{'lang': 'zh_CN'};
      if (normalizedTypeId.isNotEmpty) {
        param['typeId'] = normalizedTypeId;
      }

      final response = await _postJson(uri, {
        'cardId': 'SYS_CARD_SERVICEBUS',
        'cardWid': cardWid,
        'method': 'renderData',
        'param': param,
      }, state.cookieStore);
      if (response.statusCode != 200) {
        return FailureResult(
          BusinessFailure('服务卡片加载失败，状态码 ${response.statusCode}。'),
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return const FailureResult(ParsingFailure('服务卡片响应格式异常。'));
      }
      _logger.info(
        '[PORTAL] 服务卡片加载成功 cardWid=$cardWid typeId=${normalizedTypeId.isEmpty ? 'default' : normalizedTypeId}',
      );
      return Success(decoded);
    } on DioException catch (error, stackTrace) {
      _logger.error(
        '[PORTAL] 读取服务卡片失败 cardWid=$cardWid typeId=$typeId',
        error: error,
        stackTrace: stackTrace,
      );
      return FailureResult(
        NetworkFailure('读取服务卡片失败。', cause: error, stackTrace: stackTrace),
      );
    } catch (error, stackTrace) {
      _logger.error(
        '[PORTAL] 服务卡片解析失败 cardWid=$cardWid typeId=$typeId',
        error: error,
        stackTrace: stackTrace,
      );
      return FailureResult(
        ParsingFailure('服务卡片解析失败。', cause: error, stackTrace: stackTrace),
      );
    }
  }

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

      final decoded = jsonDecode(raw);
      _logger.debug('[GYM] 请求成功 path=$path response=${_encodeForLog(decoded)}');
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

      _logger.debug('[JXGL] 发起教务请求 uri=$uri form=${_encodeForLog(formFields)}');
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

  static const _gymServiceTypeId = '1296107574652694529'; // 生活服务

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

  Future<_TransportResponse> _postFormWithHeaders(
    Uri uri,
    Map<String, dynamic> data,
    _CookieStore cookieStore,
    Map<String, String> extraHeaders,
  ) async {
    final headers = _headersFor(uri, cookieStore);
    headers.addAll(extraHeaders);
    _logRequest(method: 'POST', uri: uri, headers: headers, body: data);
    final response = await _dio.postUri<String>(
      uri,
      data: data,
      options: Options(
        headers: headers,
        contentType: Headers.formUrlEncodedContentType,
      ),
    );
    final setCookies = response.headers['set-cookie'] ?? const [];
    cookieStore.absorb(uri, setCookies);
    final transport = _TransportResponse.fromDio(uri, response);
    _logResponse(transport, setCookies);
    return transport;
  }

  Future<Result<String>> _resolveServiceLaunch({
    required _CookieStore cookieStore,
    required String serviceUrl,
  }) async {
    try {
      final directUri = Uri.parse(serviceUrl);
      _logger.info('[SERVICE] 预认证服务入口 service=$serviceUrl');

      final directResponse = await _get(directUri, cookieStore);
      if (!_looksLikeLoginPage(directResponse.body) &&
          directResponse.statusCode == 200 &&
          !_looksLikeHtmlPrompt(directResponse.body)) {
        return Success(serviceUrl);
      }

      final casUri = _buildLoginUri(service: serviceUrl);
      final casResponse = await _get(casUri, cookieStore);
      if (casResponse.statusCode == 200 &&
          _looksLikeLoginPage(casResponse.body)) {
        return const FailureResult(SessionExpiredFailure('统一认证登录态已失效，请重新登录。'));
      }

      if (casResponse.statusCode != 302 ||
          casResponse.location == null ||
          casResponse.location!.isEmpty) {
        if (!_looksLikeLoginPage(casResponse.body) &&
            !_looksLikeHtmlPrompt(casResponse.body)) {
          return Success(serviceUrl);
        }
        return FailureResult(AuthenticationFailure('服务认证未返回有效跳转。'));
      }

      final finalResponse = await _followGetRedirects(
        casResponse.uri.resolve(casResponse.location!),
        cookieStore,
      );

      if (_looksLikeLoginPage(finalResponse.body)) {
        return const FailureResult(AuthenticationFailure('服务仍然跳回了登录页。'));
      }

      if (_looksLikeHtmlPrompt(finalResponse.body) &&
          finalResponse.uri.host.contains('wyu.edu.cn')) {
        return FailureResult(BusinessFailure('该服务当前返回异常提示页。'));
      }

      return Success(finalResponse.uri.toString());
    } on DioException catch (error, stackTrace) {
      _logger.error(
        '[SERVICE] 服务预认证失败 service=$serviceUrl',
        error: error,
        stackTrace: stackTrace,
      );
      return FailureResult(
        NetworkFailure('服务预认证失败。', cause: error, stackTrace: stackTrace),
      );
    }
  }

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

  _RuntimeState _stateForSession(AppSession session) {
    final state = _runtimeStates.putIfAbsent(
      session.userId,
      () => _RuntimeState(
        cookieStore: _CookieStore(session.cookies),
        yjsSessionId: session.yjsSessionId,
      ),
    );
    state.cookieStore.seed(session.cookies);
    state.yjsSessionId ??= session.yjsSessionId;
    return state;
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

  Future<Result<PortalUserProfile>> _fetchUserProfileFromStore(
    _CookieStore cookieStore,
  ) async {
    try {
      final uri = Uri.parse(
        'https://ehall.wyu.edu.cn/getLoginUserAndGuest?_t=${_random.nextDouble()}',
      );
      final response = await _get(uri, cookieStore);
      if (response.statusCode != 200) {
        return FailureResult(
          AuthenticationFailure('门户用户信息读取失败，状态码 ${response.statusCode}。'),
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return const FailureResult(ParsingFailure('门户用户信息格式异常。'));
      }

      final data = decoded['data'];
      if (data is! Map<String, dynamic>) {
        return const FailureResult(SessionExpiredFailure('门户登录态已失效，请重新登录。'));
      }

      final profile = PortalUserProfile(
        userName: _stringValue(data['userName']) ?? '',
        userAccount: _stringValue(data['userAccount']) ?? '',
        deptName: _stringValue(data['deptName']),
      );
      if (profile.userAccount.isEmpty) {
        return const FailureResult(SessionExpiredFailure('门户登录态已失效，请重新登录。'));
      }

      _logger.info(
        '[PORTAL] 用户信息 userName=${profile.userName} userAccount=${profile.userAccount} dept=${profile.deptName}',
      );
      return Success(profile);
    } on DioException catch (error, stackTrace) {
      _logger.error(
        '[PORTAL] 读取门户用户信息失败',
        error: error,
        stackTrace: stackTrace,
      );
      return FailureResult(
        NetworkFailure('读取门户用户信息失败。', cause: error, stackTrace: stackTrace),
      );
    } on FormatException catch (error, stackTrace) {
      _logger.error(
        '[PORTAL] 门户用户信息解析失败',
        error: error,
        stackTrace: stackTrace,
      );
      return FailureResult(
        ParsingFailure('门户用户信息解析失败。', cause: error, stackTrace: stackTrace),
      );
    }
  }

  Future<Result<List<PortalServiceLink>>> _fetchServiceLinksFromStore(
    _CookieStore cookieStore,
  ) async {
    try {
      final uri = Uri.parse(
        'https://ehall.wyu.edu.cn/execCardMethod/$_serviceCardWid/SYS_CARD_SERVICEBUS?n=${_random.nextDouble()}',
      );
      final response = await _postJson(uri, {
        'cardId': 'SYS_CARD_SERVICEBUS',
        'cardWid': _serviceCardWid,
        'method': 'renderData',
        'param': {'lang': 'zh_CN'},
      }, cookieStore);
      if (response.statusCode != 200) {
        return FailureResult(
          BusinessFailure('服务列表加载失败，状态码 ${response.statusCode}。'),
        );
      }

      final decoded = jsonDecode(response.body);
      final services = _extractServiceLinks(decoded);
      _logger.info(
        '[PORTAL] 服务列表加载成功 count=${services.length} '
        'titles=${services.take(8).map((item) => item.title).join(' | ')}',
      );
      return Success(services);
    } on DioException catch (error, stackTrace) {
      _logger.error(
        '[PORTAL] 读取门户服务列表失败',
        error: error,
        stackTrace: stackTrace,
      );
      return FailureResult(
        NetworkFailure('读取门户服务列表失败。', cause: error, stackTrace: stackTrace),
      );
    } catch (error, stackTrace) {
      _logger.error(
        '[PORTAL] 门户服务列表解析失败',
        error: error,
        stackTrace: stackTrace,
      );
      return FailureResult(
        ParsingFailure('门户服务列表解析失败。', cause: error, stackTrace: stackTrace),
      );
    }
  }

  List<PortalServiceLink> _extractServiceLinks(dynamic root) {
    final items = <PortalServiceLink>[];
    final seen = <String>{};

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
      final wid = _pickString(map, const [
        'wid',
        'WID',
        'appWid',
        'serviceWid',
      ]);
      final title = _pickString(map, const [
        'name',
        'title',
        'serviceName',
        'appName',
        'label',
        'mc',
        'APPNAME',
      ]);
      final rawUrl = _pickString(map, const [
        'url',
        'URL',
        'appUrl',
        'serviceUrl',
        'href',
        'link',
        'pcUrl',
      ]);
      final resolvedUrl = switch ((rawUrl, wid)) {
        (final String url?, _) when url.isNotEmpty => _normalizeServiceUrl(url),
        (_, final String serviceWid?) => _buildServiceShowUrl(serviceWid),
        _ => null,
      };

      if (title != null && resolvedUrl != null) {
        final id =
            _pickString(map, const ['id', 'ID', 'appId', 'serviceId']) ??
            wid ??
            title;
        if (seen.add(id)) {
          items.add(
            PortalServiceLink(
              id: id,
              title: title,
              url: resolvedUrl,
              description: _pickString(map, const [
                'description',
                'desc',
                'remark',
                'subTitle',
              ]),
              iconUrl: _pickString(map, const [
                'icon',
                'iconUrl',
                'img',
                'logo',
                'background',
              ]),
              wid: wid,
            ),
          );
        }
      }

      for (final value in map.values) {
        visit(value);
      }
    }

    visit(root);

    final hasYjs = items.any(
      (item) =>
          item.wid == _defaultYjsServiceWid ||
          item.url.contains('yjsc.wyu.edu.cn'),
    );
    if (!hasYjs) {
      items.insert(
        0,
        PortalServiceLink(
          id: _defaultYjsServiceWid,
          title: '研究生教务系统',
          url: _buildServiceShowUrl(_defaultYjsServiceWid),
          wid: _defaultYjsServiceWid,
        ),
      );
    }

    return items;
  }

  Failure _mapLoginFailure(String body) {
    if (body.contains('您提供的用户名或者密码有误')) {
      return const AuthenticationFailure('学号或密码错误。');
    }

    if (body.contains('验证码')) {
      return const AuthenticationFailure('当前账号需要验证码登录。');
    }

    final errorMatch = RegExp(
      r'<span\s+id="showErrorTip"[^>]*>([^<]*)</span>',
    ).firstMatch(body);
    final message = errorMatch?.group(1)?.trim();
    if (message != null && message.isNotEmpty) {
      return AuthenticationFailure(message);
    }

    return const AuthenticationFailure('统一认证登录失败，请稍后重试。');
  }

  bool _looksLikeKickOutPage(String body) {
    return body.contains('kick-out') || body.contains('踢出会话');
  }

  Future<_TransportResponse> _handleKickOut(
    String html,
    _CookieStore cookieStore,
  ) async {
    _logger.warn('[SSO] 检测到踢出会话页面，准备接管旧会话');
    final continueMatch = RegExp(
      r'<form[^>]*id="continue"[^>]*>.*?</form>',
      dotAll: true,
    ).firstMatch(html);
    if (continueMatch == null) {
      throw const AuthenticationFailure('检测到会话踢出页面，但无法继续接管旧会话。');
    }

    final formHtml = continueMatch.group(0)!;
    final execution = RegExp(
      r'name="execution"\s+value="([^"]+)"',
    ).firstMatch(formHtml)?.group(1);
    final eventId = RegExp(
      r'name="_eventId"\s+value="([^"]+)"',
    ).firstMatch(formHtml)?.group(1);
    if (execution == null || eventId == null) {
      throw const AuthenticationFailure('会话踢出表单字段解析失败。');
    }

    _logger.debug(
      '[SSO] 踢出会话表单 execution=${_maskShort(execution)} eventId=$eventId',
    );
    final response = await _postForm(
      _buildLoginUri(service: _portalServiceUrl),
      {'execution': execution, '_eventId': eventId},
      cookieStore,
    );
    if (response.statusCode != 302) {
      throw const AuthenticationFailure('接管旧会话失败，请稍后重试。');
    }
    return response;
  }

  _LoginFormData _parseLoginForm(String html) {
    final pwdEncryptSalt = RegExp(
      r'id="pwdEncryptSalt"\s+value="([^"]*)"',
    ).firstMatch(html)?.group(1);
    final executions = RegExp(
      r'name="execution"\s+value="([^"]*)"',
    ).allMatches(html);
    final execution = executions.isEmpty ? null : executions.last.group(1);
    final lt = RegExp(
      r'name="lt"\s+id="lt"\s+value="([^"]*)"',
    ).firstMatch(html)?.group(1);

    if (pwdEncryptSalt == null || execution == null) {
      throw const PortalContractChangedFailure('统一认证登录页结构已变化。');
    }

    _logger.debug(
      '[SSO] 解析登录页成功 htmlPreview=${_truncate(_collapseWhitespace(html), 220)}',
    );
    return _LoginFormData(
      pwdEncryptSalt: pwdEncryptSalt,
      execution: execution,
      lt: lt ?? '',
    );
  }

  Uri _buildLoginUri({required String service}) {
    return _loginUri.replace(queryParameters: {'service': service});
  }

  Future<_TransportResponse> _followGetRedirects(
    Uri initialUri,
    _CookieStore cookieStore,
  ) async {
    var currentUri = initialUri;
    _logger.info('[HTTP] 开始跟踪重定向 start=$initialUri');
    var response = await _get(currentUri, cookieStore);
    var redirectCount = 0;

    while (response.location != null &&
        response.location!.isNotEmpty &&
        redirectCount < 10) {
      currentUri = response.uri.resolve(response.location!);
      _logger.info('[HTTP] 跟踪重定向 hop=${redirectCount + 1} next=$currentUri');
      response = await _get(currentUri, cookieStore);
      redirectCount += 1;
    }

    _logger.info(
      '[HTTP] 重定向结束 hops=$redirectCount final=${response.uri} status=${response.statusCode}',
    );
    return response;
  }

  Future<_TransportResponse> _get(
    Uri uri,
    _CookieStore cookieStore, {
    Map<String, dynamic>? queryParameters,
  }) async {
    final requestUri = _mergeQuery(uri, queryParameters);
    final headers = _headersFor(requestUri, cookieStore);
    _logRequest(
      method: 'GET',
      uri: requestUri,
      headers: headers,
      queryParameters: requestUri.queryParameters,
    );
    final response = await _dio.getUri<String>(
      requestUri,
      options: Options(headers: headers),
    );
    final setCookies = response.headers['set-cookie'] ?? const [];
    cookieStore.absorb(requestUri, setCookies);
    final transport = _TransportResponse.fromDio(requestUri, response);
    _logResponse(transport, setCookies);
    return transport;
  }

  Future<_TransportResponse> _postForm(
    Uri uri,
    Map<String, dynamic> data,
    _CookieStore cookieStore,
  ) async {
    final headers = _headersFor(uri, cookieStore);
    _logRequest(method: 'POST', uri: uri, headers: headers, body: data);
    final response = await _dio.postUri<String>(
      uri,
      data: data,
      options: Options(
        headers: headers,
        contentType: Headers.formUrlEncodedContentType,
      ),
    );
    final setCookies = response.headers['set-cookie'] ?? const [];
    cookieStore.absorb(uri, setCookies);
    final transport = _TransportResponse.fromDio(uri, response);
    _logResponse(transport, setCookies);
    return transport;
  }

  Future<_TransportResponse> _postJson(
    Uri uri,
    Object data,
    _CookieStore cookieStore,
  ) async {
    final headers = _headersFor(uri, cookieStore);
    _logRequest(method: 'POST', uri: uri, headers: headers, body: data);
    final response = await _dio.postUri<String>(
      uri,
      data: data,
      options: Options(headers: headers, contentType: Headers.jsonContentType),
    );
    final setCookies = response.headers['set-cookie'] ?? const [];
    cookieStore.absorb(uri, setCookies);
    final transport = _TransportResponse.fromDio(uri, response);
    _logResponse(transport, setCookies);
    return transport;
  }

  Map<String, String> _headersFor(Uri uri, _CookieStore cookieStore) {
    final headers = <String, String>{};
    final cookieHeader = cookieStore.cookieHeaderFor(uri);
    if (cookieHeader.isNotEmpty) {
      headers['Cookie'] = cookieHeader;
    }
    return headers;
  }

  Uri _mergeQuery(Uri uri, Map<String, dynamic>? queryParameters) {
    if (queryParameters == null || queryParameters.isEmpty) {
      return uri;
    }

    final merged = <String, String>{...uri.queryParameters};
    for (final entry in queryParameters.entries) {
      merged[entry.key] = '${entry.value}';
    }
    return uri.replace(queryParameters: merged);
  }

  void _logRequest({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    Map<String, dynamic>? queryParameters,
    Object? body,
  }) {
    _logger.info('[HTTP] $method $uri');
    if (queryParameters != null && queryParameters.isNotEmpty) {
      _logger.debug('[HTTP] query=${_encodeForLog(queryParameters)}');
    }
    if (body != null) {
      _logger.debug('[HTTP] body=${_encodeForLog(body)}');
    }
    if (headers.isNotEmpty) {
      _logger.debug(
        '[HTTP] headers=${_encodeForLog(_sanitizeHeaders(headers))}',
      );
    }
  }

  void _logResponse(_TransportResponse response, List<String> setCookies) {
    _logger.info(
      '[HTTP] <- status=${response.statusCode} uri=${response.uri} location=${response.location ?? '-'} '
      'setCookies=${setCookies.isEmpty ? '-' : setCookies.map(_cookieNameFromSetCookie).join(', ')}',
    );
    _logger.debug('[HTTP] body=${_summarizeBody(response.body)}');
  }

  Map<String, String> _sanitizeHeaders(Map<String, String> headers) {
    final sanitized = <String, String>{};
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == 'cookie') {
        sanitized[entry.key] = _summarizeCookieHeader(entry.value);
      } else {
        sanitized[entry.key] = entry.value;
      }
    }
    return sanitized;
  }

  String _summarizeCookieHeader(String cookieHeader) {
    final parts = cookieHeader
        .split(';')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .map((item) {
          final pieces = item.split('=');
          final name = pieces.first.trim();
          final value = pieces.length > 1
              ? pieces.sublist(1).join('=').trim()
              : '';
          return '$name=${_maskShort(value)}';
        })
        .toList();
    return parts.join('; ');
  }

  String _cookieSnapshotSummary(List<PortalCookie> cookies) {
    if (cookies.isEmpty) {
      return '[]';
    }
    return cookies
        .map((cookie) => '${cookie.name}@${cookie.domain}${cookie.path}')
        .join(', ');
  }

  String _cookieNameFromSetCookie(String header) {
    final parts = header.split('=');
    return parts.isEmpty ? header : parts.first.trim();
  }

  String _encodeForLog(Object? value) {
    final sanitized = _sanitizeForLog(value);
    if (sanitized == null) {
      return 'null';
    }

    try {
      return _truncate(jsonEncode(sanitized), 1200);
    } catch (_) {
      return _truncate('$sanitized', 1200);
    }
  }

  dynamic _sanitizeForLog(Object? value, {String? key}) {
    if (value == null) {
      return null;
    }
    if (value is Map) {
      return {
        for (final entry in value.entries)
          '${entry.key}': _sanitizeForLog(entry.value, key: '${entry.key}'),
      };
    }
    if (value is Iterable) {
      return value.map((item) => _sanitizeForLog(item)).toList();
    }

    final text = '$value';
    final lowerKey = key?.toLowerCase() ?? '';
    if (lowerKey.contains('password')) {
      return '<redacted length=${text.length} preview=${_maskShort(text)}>';
    }
    if (lowerKey == 'cookie') {
      return _summarizeCookieHeader(text);
    }
    return _truncate(text, 240);
  }

  String _summarizeBody(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) {
      return '<empty>';
    }
    try {
      final decoded = jsonDecode(trimmed);
      return _encodeForLog(decoded);
    } catch (_) {
      return _truncate(_collapseWhitespace(trimmed), 600);
    }
  }

  String _collapseWhitespace(String input) {
    return input.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _truncate(String input, int maxLength) {
    if (input.length <= maxLength) {
      return input;
    }
    return '${input.substring(0, maxLength)}...(len=${input.length})';
  }

  String? _maskShort(String? value, {int keepStart = 4, int keepEnd = 4}) {
    if (value == null || value.isEmpty) {
      return value;
    }
    if (value.length <= keepStart + keepEnd) {
      return value;
    }
    return '${value.substring(0, keepStart)}...${value.substring(value.length - keepEnd)}';
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

  bool _isYjsServiceItem(ServiceItem item) {
    if ((item.wid?.trim().isNotEmpty ?? false) &&
        item.wid!.trim() == _defaultYjsServiceWid) {
      return true;
    }

    if (item.appName.contains('研究生')) {
      return true;
    }

    return item.launchCandidates.any((candidate) {
      return candidate.contains('yjsc.wyu.edu.cn');
    });
  }

  List<PortalCookie> _cookiesForLaunchUri(
    Iterable<PortalCookie> cookies,
    Uri uri,
  ) {
    return cookies.where((cookie) => cookie.matches(uri)).toList();
  }

  bool _looksLikeHtml(String body) {
    final value = body.trimLeft();
    return value.startsWith('<!DOCTYPE html') ||
        value.startsWith('<html') ||
        value.contains('统一身份认证');
  }

  bool _looksLikeLoginPage(String body) {
    return body.contains('统一身份认证') ||
        body.contains('/authserver/login') ||
        body.contains('账号登录') ||
        body.contains('验证码登录');
  }

  bool _looksLikeHtmlPrompt(String body) {
    return body.contains('系统提示') || body.contains('您访问的页面未找到');
  }

  bool _looksLikeJxglSessionExpiredPayload(dynamic value) {
    if (value is! Map) {
      return false;
    }

    final map = Map<String, dynamic>.from(value.cast<dynamic, dynamic>());
    final code = _pickString(map, const ['code', 'status']);
    final message = _pickString(map, const ['message', 'msg', 'error']);
    if (code == '-401' || code == '401') {
      return true;
    }
    if (message == null) {
      return false;
    }
    return message.contains('尚未登录') ||
        message.contains('请先登录') ||
        message.contains('登录失效') ||
        message.contains('已在别处登录') ||
        message.contains('被迫退出');
  }

  String? _pickString(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      final text = _stringValue(value);
      if (text != null && text.isNotEmpty) {
        return text;
      }
    }
    return null;
  }

  String? _stringValue(dynamic value) {
    if (value == null) {
      return null;
    }
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  String _normalizeServiceUrl(String rawUrl) {
    if (rawUrl.startsWith('http://') || rawUrl.startsWith('https://')) {
      return rawUrl;
    }
    if (rawUrl.startsWith('//')) {
      return 'https:$rawUrl';
    }
    if (rawUrl.startsWith('/')) {
      return 'https://ehall.wyu.edu.cn$rawUrl';
    }
    return 'https://ehall.wyu.edu.cn/$rawUrl';
  }

  String _buildServiceShowUrl(String wid) {
    return 'https://ehall.wyu.edu.cn/default/index.html#/ServiceShow?isMobile=0&wid=$wid';
  }
}

class _LoginFormData {
  const _LoginFormData({
    required this.pwdEncryptSalt,
    required this.execution,
    required this.lt,
  });

  final String pwdEncryptSalt;
  final String execution;
  final String lt;
}

class _RuntimeState {
  _RuntimeState({required this.cookieStore, required this.yjsSessionId});

  final _CookieStore cookieStore;
  String? yjsSessionId;
  String? gymPcAccessUrl;
  String? jxglPcAccessUrl;
}

class _CookieStore {
  _CookieStore([Iterable<PortalCookie> initial = const []]) {
    seed(initial);
  }

  final List<PortalCookie> _cookies = [];

  void seed(Iterable<PortalCookie> cookies) {
    for (final cookie in cookies) {
      _upsert(cookie);
    }
  }

  void absorb(Uri uri, List<String> setCookieHeaders) {
    for (final header in setCookieHeaders) {
      final parsed = _parseSetCookie(uri, header);
      if (parsed != null) {
        _upsert(parsed);
      }
    }
  }

  String cookieHeaderFor(Uri uri) {
    return _cookies
        .where((cookie) => cookie.matches(uri))
        .map((cookie) => '${cookie.name}=${cookie.value}')
        .join('; ');
  }

  List<PortalCookie> snapshot() => List.unmodifiable(_cookies);

  void _upsert(PortalCookie cookie) {
    _cookies.removeWhere(
      (item) =>
          item.name == cookie.name &&
          item.domain == cookie.domain &&
          item.path == cookie.path,
    );
    _cookies.add(cookie);
  }

  PortalCookie? _parseSetCookie(Uri uri, String value) {
    final segments = value.split(';');
    if (segments.isEmpty) {
      return null;
    }

    final nameValue = segments.first.split('=');
    if (nameValue.length < 2) {
      return null;
    }

    final name = nameValue.first.trim();
    final cookieValue = nameValue.sublist(1).join('=').trim();
    var domain = uri.host;
    var path = '/';
    var secure = false;
    var httpOnly = false;

    for (final rawSegment in segments.skip(1)) {
      final segment = rawSegment.trim();
      final lower = segment.toLowerCase();
      if (lower == 'secure') {
        secure = true;
        continue;
      }
      if (lower == 'httponly') {
        httpOnly = true;
        continue;
      }
      if (lower.startsWith('domain=')) {
        domain = segment.substring('domain='.length).trim();
        continue;
      }
      if (lower.startsWith('path=')) {
        path = segment.substring('path='.length).trim();
      }
    }

    return PortalCookie(
      name: name,
      value: cookieValue,
      domain: domain,
      path: path.isEmpty ? '/' : path,
      secure: secure,
      httpOnly: httpOnly,
    );
  }
}

class _TransportResponse {
  const _TransportResponse({
    required this.uri,
    required this.statusCode,
    required this.body,
    required this.location,
  });

  final Uri uri;
  final int statusCode;
  final String body;
  final String? location;

  factory _TransportResponse.fromDio(Uri uri, Response<String> response) {
    return _TransportResponse(
      uri: uri,
      statusCode: response.statusCode ?? 0,
      body: response.data ?? '',
      location: response.headers.value('location'),
    );
  }
}
