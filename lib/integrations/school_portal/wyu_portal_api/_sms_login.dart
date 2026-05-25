// 手机号 + 验证码登录全流程：startSmsLogin / openSliderCaptcha /
// verifySliderCaptcha / sendDynamicCode / submitSmsLogin。
// 与 _auth.dart 共享 SSO 表单解析、用户信息读取等基础设施。
part of '../wyu_portal_api.dart';

extension WyuPortalSmsLogin on WyuPortalApi {
  /// 打开短信登录页，拿到 lt / execution / pwdEncryptSalt 与初始 cookies。
  /// 后续滑块、发短信、提交登录都会基于这同一份 cookies 继续累加。
  Future<Result<SmsLoginSession>> startSmsLogin() async {
    final cookieStore = _CookieStore();
    try {
      _logger.info('[SMS] 打开短信登录页');
      final loginPage = await _get(
        _buildLoginUri(service: _portalServiceUrl).replace(queryParameters: {
          'service': _portalServiceUrl,
          'type': 'dynamicLogin',
        }),
        cookieStore,
      );
      if (loginPage.statusCode != 200) {
        return FailureResult(
          AuthenticationFailure('登录页访问失败，状态码 ${loginPage.statusCode}。'),
        );
      }
      final formData = _parseLoginForm(loginPage.body, formId: 'phoneFromId');

      // 触发服务端往 session 里放滑块需要的标记。
      await _get(
        Uri.parse(
          'https://authserver.wyu.edu.cn/authserver/common/toSliderCaptcha.htl',
        ),
        cookieStore,
      );

      return Success(
        SmsLoginSession(
          pwdEncryptSalt: formData.pwdEncryptSalt,
          lt: formData.lt,
          execution: formData.execution,
          cookies: cookieStore.snapshot(),
        ),
      );
    } on DioException catch (error, stackTrace) {
      _logger.error('[SMS] 启动短信登录失败', error: error, stackTrace: stackTrace);
      return FailureResult(
        NetworkFailure('访问学校登录页失败。', cause: error, stackTrace: stackTrace),
      );
    } catch (error, stackTrace) {
      _logger.error('[SMS] 启动短信登录异常', error: error, stackTrace: stackTrace);
      return FailureResult(
        AuthenticationFailure(
          '短信登录初始化失败。',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// 拉一张滑块挑战。每次失败后可以重复调用以换图。
  Future<Result<SliderCaptchaChallenge>> openSliderCaptcha(
    SmsLoginSession smsSession,
  ) async {
    final cookieStore = _CookieStore(smsSession.cookies);
    try {
      final ts = DateTime.now().millisecondsSinceEpoch;
      final response = await _get(
        Uri.parse(
          'https://authserver.wyu.edu.cn/authserver/common/openSliderCaptcha.htl',
        ),
        cookieStore,
        queryParameters: {'_': '$ts'},
      );
      smsSession.cookies = cookieStore.snapshot();
      if (response.statusCode != 200) {
        return FailureResult(
          AuthenticationFailure('拉取滑块图片失败，状态码 ${response.statusCode}。'),
        );
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final challenge = SliderCaptchaChallenge.fromJson(json);
      _logger.debug(
        '[SMS] 滑块图片就绪 tagWidth=${challenge.tagWidth} '
        'safeSecure=${_maskShort(challenge.safeSecure)}',
      );
      return Success(challenge);
    } on DioException catch (error, stackTrace) {
      _logger.error('[SMS] 拉取滑块失败', error: error, stackTrace: stackTrace);
      return FailureResult(
        NetworkFailure('拉取滑块图片失败。', cause: error, stackTrace: stackTrace),
      );
    } on FormatException catch (error, stackTrace) {
      return FailureResult(
        AuthenticationFailure(
          '滑块响应解析失败：${error.message}',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    } catch (error, stackTrace) {
      _logger.error('[SMS] 拉取滑块异常', error: error, stackTrace: stackTrace);
      return FailureResult(
        AuthenticationFailure(
          '拉取滑块图片失败。',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// 提交滑动轨迹。会重用 [smsSession] 的 cookies，验证通过后服务端在
  /// session 里盖通过标记，后续 dynamicCode / login 直接走 cookie 即可。
  Future<Result<SliderVerifyResult>> verifySliderCaptcha(
    SmsLoginSession smsSession, {
    required SliderTrackPayload payload,
    required String safeSecure,
  }) async {
    final cookieStore = _CookieStore(smsSession.cookies);
    try {
      final body = jsonEncode(payload.toJson());
      final sign = _transformer.encryptPassword(body, safeSecure);
      _logger.debug(
        '[SMS] 提交滑块校验 moveLength=${payload.moveLength} '
        'tracks=${payload.tracks.length} sign=${_maskShort(sign)}',
      );
      final response = await _postForm(
        Uri.parse(
          'https://authserver.wyu.edu.cn/authserver/common/verifySliderCaptcha.htl',
        ),
        {'sign': sign},
        cookieStore,
      );
      smsSession.cookies = cookieStore.snapshot();
      if (response.statusCode != 200) {
        return FailureResult(
          AuthenticationFailure('滑块校验失败，状态码 ${response.statusCode}。'),
        );
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final result = SliderVerifyResult.fromJson(json);
      _logger.info(
        '[SMS] 滑块校验返回 passed=${result.passed} msg=${result.message ?? ''}',
      );
      return Success(result);
    } on DioException catch (error, stackTrace) {
      _logger.error('[SMS] 滑块校验失败', error: error, stackTrace: stackTrace);
      return FailureResult(
        NetworkFailure('滑块校验失败。', cause: error, stackTrace: stackTrace),
      );
    } catch (error, stackTrace) {
      _logger.error('[SMS] 滑块校验异常', error: error, stackTrace: stackTrace);
      return FailureResult(
        AuthenticationFailure(
          '滑块校验失败。',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// 调 `/authserver/dynamicCode/getDynamicCode.htl` 发短信。
  ///
  /// 必须在 [verifySliderCaptcha] 通过之后立即调用，服务端靠 cookies 携带
  /// 通过标记（例如 `JSESSIONID` 上挂的滑块通过状态）。
  Future<Result<String>> sendDynamicCode(
    SmsLoginSession smsSession, {
    required String mobile,
  }) async {
    final cookieStore = _CookieStore(smsSession.cookies);
    try {
      final encryptedMobile =
          _transformer.encryptPassword(mobile, _smsMobileSalt);
      _logger.info(
        '[SMS] 发送动态验证码 mobile=${_maskShort(mobile, keepStart: 3, keepEnd: 2)} '
        'encMobile=${_maskShort(encryptedMobile)}',
      );
      final response = await _postForm(
        Uri.parse(
          'https://authserver.wyu.edu.cn/authserver/dynamicCode/getDynamicCode.htl',
        ),
        {'mobile': encryptedMobile, 'captcha': ''},
        cookieStore,
      );
      smsSession.cookies = cookieStore.snapshot();
      if (response.statusCode != 200) {
        return FailureResult(
          AuthenticationFailure('短信发送失败，状态码 ${response.statusCode}。'),
        );
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final code = json['code']?.toString() ?? '';
      final message =
          json['message']?.toString() ?? json['msg']?.toString() ?? '';
      _logger.info('[SMS] 动态验证码返回 code=$code message=$message');
      if (code == 'success' || code == '0' || code == 'ok') {
        return Success(message.isEmpty ? '验证码已发送' : message);
      }
      return FailureResult(
        AuthenticationFailure(message.isEmpty ? '短信发送失败。' : message),
      );
    } on DioException catch (error, stackTrace) {
      _logger.error('[SMS] 短信发送失败', error: error, stackTrace: stackTrace);
      return FailureResult(
        NetworkFailure('短信发送失败。', cause: error, stackTrace: stackTrace),
      );
    } catch (error, stackTrace) {
      _logger.error('[SMS] 短信发送异常', error: error, stackTrace: stackTrace);
      return FailureResult(
        AuthenticationFailure(
          '短信发送失败。',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// 用滑块通过 + 短信收到的 6 位验证码完成登录。
  /// body 与密码登录类似，区别：
  /// - `username` 是 **明文** 手机号；
  /// - 多了 `dynamicCode` 字段；
  /// - `cllt=dynamicLogin`（指明走短信通道）；
  /// - 没有 password 字段。
  Future<Result<AppSession>> submitSmsLogin(
    SmsLoginSession smsSession, {
    required String mobile,
    required String dynamicCode,
  }) async {
    final cookieStore = _CookieStore(smsSession.cookies);
    try {
      final payload = {
        'username': mobile,
        'captcha': '',
        'dynamicCode': dynamicCode,
        '_eventId': 'submit',
        'cllt': 'dynamicLogin',
        'dllt': 'generalLogin',
        'lt': smsSession.lt,
        'execution': smsSession.execution,
      };
      _logger.info(
        '[SMS] 提交短信登录 mobile=${_maskShort(mobile, keepStart: 3, keepEnd: 2)}',
      );

      var response = await _postForm(
        _buildLoginUri(service: _portalServiceUrl),
        payload,
        cookieStore,
      );

      if (response.statusCode == 200 && _looksLikeKickOutPage(response.body)) {
        response = await _handleKickOut(response.body, cookieStore);
      }

      if (response.statusCode != 302) {
        _logger.warn('[SMS] 登录提交未返回 302，准备解析失败原因。');
        return FailureResult(_mapLoginFailure(response.body));
      }

      final location = response.location;
      if (location != null && location.contains('needCaptcha')) {
        // 理论上短信流不会走到这里，因为滑块已通过；保留这条以防服务端临时
        // 改策略。
        return const FailureResult(AuthenticationFailure('登录被服务端要求重新验证。'));
      }

      if (location != null && location.isNotEmpty) {
        await _followGetRedirects(response.uri.resolve(location), cookieStore);
      }

      smsSession.cookies = cookieStore.snapshot();

      final profileResult = await _fetchUserProfileFromStore(cookieStore);
      if (profileResult
          case FailureResult<PortalUserProfile>(failure: final f)) {
        return FailureResult(f);
      }
      final profile = profileResult.dataOrNull!;

      // 学号：profile.userAccount 是统一身份认证的"账号"，本科生/研究生
      // 都会落进来；fallback 用手机号。
      final userId = profile.userAccount.trim().isNotEmpty
          ? profile.userAccount.trim()
          : mobile;

      final services = await _fetchServiceLinksFromStore(cookieStore);
      final yjsSessionId =
          (await _initYjsSession(userId, cookieStore)).dataOrNull;

      final session = AppSession(
        userId: userId,
        displayName: profile.userName.isEmpty ? userId : profile.userName,
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
        '[SMS] 短信登录成功 userId=$userId displayName=${session.displayName} '
        'cookies=${_cookieSnapshotSummary(session.cookies)} '
        'serviceCount=${session.serviceLinks.length} '
        'yjsSessionId=${_maskShort(session.yjsSessionId)}',
      );
      return Success(session);
    } on DioException catch (error, stackTrace) {
      _logger.error('[SMS] 提交登录失败', error: error, stackTrace: stackTrace);
      return FailureResult(
        NetworkFailure(
          '提交登录失败，请检查网络连接。',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    } catch (error, stackTrace) {
      _logger.error('[SMS] 短信登录异常', error: error, stackTrace: stackTrace);
      return FailureResult(
        AuthenticationFailure(
          '短信登录失败。',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }
}
