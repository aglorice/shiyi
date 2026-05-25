// 门户服务列表 / 服务卡片数据 / 单点登录跳转。
part of '../wyu_portal_api.dart';

extension WyuPortalServices on WyuPortalApi {
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
}
