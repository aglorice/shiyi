// 学号密码登录、注销、session 校验，以及登录页字段解析、用户信息读取等
// 公用的 SSO 流程。短信验证码登录单独放在 _sms_login.dart。
part of '../wyu_portal_api.dart';

extension WyuPortalAuth on WyuPortalApi {
  /// 学号密码登录主入口。
  /// 流程：GET 登录页拿 execution → 可选滑块 → POST 登录 → 跟随 302 →
  /// 拉用户信息 / 服务列表 / 研究生 session ID → 组装 [AppSession]。
  Future<Result<AppSession>> login(
    SchoolCredential credential, {
    /// 当 checkNeedCaptcha 返回 true 时调用：把 cookies 共享出去让外部弹滑块 sheet。
    /// 返回 true 视为滑块通过，继续 POST 登录；返回 false 视为放弃。
    Future<bool> Function(SmsLoginSession session)? solveCaptcha,
  }) async {
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

      // 先探针：服务端是否要求滑块。
      final needCaptcha = await checkNeedCaptcha(credential.username.trim());
      if (needCaptcha) {
        _logger.info('[SSO] checkNeedCaptcha=true，准备滑块');
        if (solveCaptcha == null) {
          return const FailureResult(
            AuthenticationFailure('当前账号需要滑块验证，请用应用最新版本登录。'),
          );
        }
        // 触发服务端 session 上的滑块标记。
        await _get(
          Uri.parse(
            'https://authserver.wyu.edu.cn/authserver/common/toSliderCaptcha.htl',
          ),
          cookieStore,
        );
        final sharedSession = SmsLoginSession(
          pwdEncryptSalt: formData.pwdEncryptSalt,
          lt: formData.lt,
          execution: formData.execution,
          cookies: cookieStore.snapshot(),
        );
        final passed = await solveCaptcha(sharedSession);
        if (!passed) {
          return const FailureResult(AuthenticationFailure('滑块未通过，已取消登录。'));
        }
        // 把滑块流期间累计到的新 cookies 合并回来。
        cookieStore.seed(sharedSession.cookies);
      }

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

  /// 学号密码登录前的"是否需要图形/滑块验证"探针。
  /// 服务端在某些条件下（异常 IP、连续失败等）会强制要求滑块；
  /// 这个接口用于在 POST 登录之前先决定要不要走 captcha 流。
  ///
  /// 返回 true 即需要滑块；false 表示直接 POST 即可。
  Future<bool> checkNeedCaptcha(String username) async {
    try {
      final ts = DateTime.now().millisecondsSinceEpoch;
      final response = await _get(
        Uri.parse(
          'https://authserver.wyu.edu.cn/authserver/checkNeedCaptcha.htl',
        ),
        _CookieStore(),
        queryParameters: {'username': username, '_': '$ts'},
      );
      if (response.statusCode != 200) return false;
      final body = response.body.trim();
      if (body.isEmpty) return false;
      try {
        final json = jsonDecode(body);
        if (json is Map<String, dynamic>) {
          final isNeed = json['isNeed'];
          return isNeed == true || isNeed == 'true';
        }
      } catch (_) {
        // 不是 JSON 就当不需要。
      }
      return false;
    } on DioException catch (error) {
      _logger.warn('[SSO] checkNeedCaptcha 网络失败，默认按不需要处理：$error');
      return false;
    } catch (error) {
      _logger.warn('[SSO] checkNeedCaptcha 异常，默认按不需要处理：$error');
      return false;
    }
  }

  /// 主动注销服务端登录态。GET /authserver/logout?service=`<index>`。
  ///
  /// 服务端会返回 302，Set-Cookie 把 CASTGC/CASPRIVACY/iPlanetDirectoryPro
  /// 全部置过期，然后 Location 跳到指定 service。我们跟一次重定向即视为成功。
  /// 任何中间错误都按"成功"处理 —— 客户端始终需要清本地，不能因为远端不通就卡住。
  Future<Result<void>> logout(AppSession session) async {
    final cookieStore = _CookieStore(session.cookies);
    try {
      _logger.info('[SSO] 主动注销 userId=${session.userId}');
      const indexUrl = 'https://ehall.wyu.edu.cn/default/index.html';
      final logoutUri = Uri.parse(
        'https://authserver.wyu.edu.cn/authserver/logout',
      ).replace(queryParameters: {'service': indexUrl});

      final response = await _get(logoutUri, cookieStore);

      // 期望 302 → ehall index；如果是其它状态也不阻塞客户端注销流程。
      if (response.statusCode == 302) {
        final location = response.location;
        if (location != null && location.isNotEmpty) {
          // 跟一次重定向，让 ehall 端的 Cookie 也跟着失效。
          await _get(response.uri.resolve(location), cookieStore);
        }
      } else {
        _logger.warn(
          '[SSO] 注销返回 status=${response.statusCode}，已忽略并继续清本地 session',
        );
      }
    } catch (error, stackTrace) {
      _logger.warn('[SSO] 注销请求失败但仍然继续清本地：$error\n$stackTrace');
    }
    // 不管远端结果如何，移除运行时状态。
    final removed = _runtimeStates.remove(session.userId);
    if (removed != null) {
      _personalInfoReady.remove(removed.cookieStore);
    }
    return const Success(null);
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

  // -------- 登录页 / 用户信息解析 --------

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

  _LoginFormData _parseLoginForm(String html, {String? formId}) {
    final scope = formId == null ? html : _extractFormScope(html, formId);

    final pwdEncryptSalt = RegExp(
      r'id="pwdEncryptSalt"\s+value="([^"]*)"',
    ).firstMatch(scope)?.group(1);
    // execution 在表单尾部，可能用 name="execution" 或 id="execution" name="execution"
    // 任意顺序，所以两条正则任取其一。
    String? execution = RegExp(
      r'id="execution"[^>]*name="execution"\s+value="([^"]*)"',
    ).firstMatch(scope)?.group(1);
    execution ??= RegExp(
      r'name="execution"[^>]*value="([^"]*)"',
    ).firstMatch(scope)?.group(1);
    final lt = RegExp(
      r'name="lt"[^>]*value="([^"]*)"',
    ).firstMatch(scope)?.group(1);

    if (execution == null) {
      throw const PortalContractChangedFailure('统一认证登录页结构已变化。');
    }
    if (formId == null && pwdEncryptSalt == null) {
      // 旧的密码登录路径必须有 pwdEncryptSalt；短信登录走 formId 分支跳过此检查。
      throw const PortalContractChangedFailure('统一认证登录页结构已变化。');
    }

    _logger.debug(
      '[SSO] 解析登录页成功'
      '${formId == null ? '' : ' formId=$formId'} '
      'htmlPreview=${_truncate(_collapseWhitespace(scope), 220)}',
    );
    return _LoginFormData(
      pwdEncryptSalt: pwdEncryptSalt ?? '',
      execution: execution,
      lt: lt ?? '',
    );
  }

  /// 从完整 HTML 里把 `<form id="formId" ...> ... </form>` 这块切出来。
  /// 找不到时返回原 html，保留兜底；调用方仍可在全局空间跑正则。
  String _extractFormScope(String html, String formId) {
    final start = RegExp('<form[^>]*id="${RegExp.escape(formId)}"').firstMatch(html);
    if (start == null) return html;
    final from = start.start;
    final end = html.indexOf('</form>', from);
    if (end < 0) return html.substring(from);
    return html.substring(from, end + '</form>'.length);
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
}
