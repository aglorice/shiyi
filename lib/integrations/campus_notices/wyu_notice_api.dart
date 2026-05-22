import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;

import '../../core/error/failure.dart';
import '../../core/logging/api_log_interceptor.dart';
import '../../core/logging/app_logger.dart';
import '../../core/result/result.dart';
import '../../modules/auth/domain/entities/app_session.dart';
import '../../modules/notices/domain/entities/campus_notice.dart';
import 'wyu_notice_parser.dart';

class WyuNoticeApi {
  WyuNoticeApi({
    required AppLogger logger,
    required String userAgent,
    WyuNoticeParser parser = const WyuNoticeParser(),
    Dio? dio,
  }) : _logger = logger,
       _parser = parser,
       _dio = dio ?? _createDio(userAgent);

  static final _snapshotUri = Uri.parse('https://www.wyu.edu.cn/xnzx/sy.htm');
  static const _logRawHtml = true;

  final AppLogger _logger;
  final WyuNoticeParser _parser;
  final Dio _dio;

  static Dio _createDio(String userAgent) {
    return Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 20),
        followRedirects: false,
        maxRedirects: 0,
        responseType: ResponseType.bytes,
        validateStatus: (_) => true,
        headers: {'User-Agent': userAgent, 'Accept-Language': 'zh-CN,zh;q=0.9'},
      ),
    )..interceptors.add(ApiLogInterceptor(label: 'Notice'));
  }

  Future<Result<CampusNoticeSnapshot>> fetchSnapshot({
    required AppSession session,
  }) async {
    try {
      _logger.info(
        '[NOTICE] 通知首页开始抓取 uri=$_snapshotUri '
        'cookieCount=${session.cookies.length}',
      );
      final cookieStore = _CookieStore(session.cookies);
      final response = await _get(_snapshotUri, cookieStore);
      _logger.info(
        '[NOTICE] 通知首页响应 status=${response.statusCode} '
        'bodyLen=${response.body.length}',
      );
      _logHtmlIfEnabled(
        title:
            '[NOTICE][HTML][SNAPSHOT] uri=${response.uri} status=${response.statusCode}',
        body: response.body,
      );
      if (response.statusCode != 200) {
        return FailureResult(
          NetworkFailure('通知首页访问失败，状态码 ${response.statusCode}。'),
        );
      }

      final snapshot = _parser.parseSnapshot(
        response.body,
        baseUri: _snapshotUri,
        logger: _logger,
      );
      return Success(snapshot);
    } on DioException catch (error, stackTrace) {
      _logger.error('通知首页抓取失败', error: error, stackTrace: stackTrace);
      return FailureResult(
        NetworkFailure(
          '通知首页访问失败，请检查网络连接。',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    } on Failure catch (failure) {
      return FailureResult(failure);
    } catch (error, stackTrace) {
      _logger.error('通知首页解析失败', error: error, stackTrace: stackTrace);
      return FailureResult(
        ParsingFailure('通知首页解析失败。', cause: error, stackTrace: stackTrace),
      );
    }
  }

  Future<Result<CampusNoticeCategoryPage>> fetchCategoryPage({
    required AppSession session,
    required CampusNoticeCategory category,
    required Uri pageUri,
  }) async {
    final cookieStore = _CookieStore(session.cookies);

    try {
      _logger.info(
        '[NOTICE] 分类列表开始抓取 category=${category.name} uri=$pageUri '
        'cookieCount=${session.cookies.length}',
      );
      final resolved = await _resolveResponse(pageUri, cookieStore);
      final response = resolved.response;
      final redirectCount = resolved.hopCount;

      _logger.info(
        '[NOTICE] 分类列表响应 category=${category.name} '
        'status=${response.statusCode} redirects=$redirectCount '
        'uri=${response.uri} bodyLen=${response.body.length}',
      );
      _logHtmlIfEnabled(
        title:
            '[NOTICE][HTML][CATEGORY] category=${category.name} uri=${response.uri} '
            'status=${response.statusCode} redirects=$redirectCount',
        body: response.body,
      );

      if (_looksLikeLoginPage(response.body)) {
        _logger.warn('[NOTICE] 分类列表响应疑似登录页');
        return const FailureResult(SessionExpiredFailure('通知系统登录态已失效，请重新登录。'));
      }

      if (_looksLikeMissingPage(response.body)) {
        _logger.warn('[NOTICE] 分类列表响应疑似 404');
        return const FailureResult(BusinessFailure('通知列表暂时无法访问。'));
      }

      if (response.statusCode != 200) {
        return FailureResult(
          NetworkFailure('通知列表访问失败，状态码 ${response.statusCode}。'),
        );
      }

      final page = _parser.parseCategoryPage(
        response.body,
        pageUri: pageUri,
        category: category,
        logger: _logger,
      );
      return Success(page);
    } on DioException catch (error, stackTrace) {
      _logger.error('通知分类列表抓取失败', error: error, stackTrace: stackTrace);
      return FailureResult(
        NetworkFailure('通知列表访问失败，请稍后重试。', cause: error, stackTrace: stackTrace),
      );
    } on Failure catch (failure) {
      return FailureResult(failure);
    } catch (error, stackTrace) {
      _logger.error('通知分类列表解析失败', error: error, stackTrace: stackTrace);
      return FailureResult(
        ParsingFailure('通知列表解析失败。', cause: error, stackTrace: stackTrace),
      );
    }
  }

  Future<Result<CampusNoticeDetail>> fetchDetail({
    required AppSession session,
    required CampusNoticeItem item,
  }) async {
    final cookieStore = _CookieStore(session.cookies);

    try {
      _logger.info(
        '[NOTICE] 通知详情开始抓取 title=${item.title} '
        'uri=${item.detailUri} cookieCount=${session.cookies.length}',
      );
      final resolved = await _resolveResponse(item.detailUri, cookieStore);
      final response = resolved.response;
      final redirectCount = resolved.hopCount;

      _logger.info(
        '[NOTICE] 通知详情响应 status=${response.statusCode} '
        'redirects=$redirectCount uri=${response.uri} '
        'bodyLen=${response.body.length}',
      );
      _logHtmlIfEnabled(
        title:
            '[NOTICE][HTML][DETAIL] title=${item.title} uri=${response.uri} '
            'status=${response.statusCode} redirects=$redirectCount',
        body: response.body,
      );

      if (_looksLikeLoginPage(response.body)) {
        _logger.warn('[NOTICE] 通知详情响应疑似登录页');
        return const FailureResult(SessionExpiredFailure('通知系统登录态已失效，请重新登录。'));
      }

      if (_looksLikeMissingPage(response.body)) {
        _logger.warn('[NOTICE] 通知详情响应疑似 404');
        return const FailureResult(BusinessFailure('该通知暂时无法访问。'));
      }

      final detail = _parser.parseDetail(
        html: response.body,
        pageUri: response.uri,
        item: item,
        logger: _logger,
      );
      return Success(detail);
    } on DioException catch (error, stackTrace) {
      _logger.error('通知详情抓取失败', error: error, stackTrace: stackTrace);
      return FailureResult(
        NetworkFailure('通知详情访问失败，请稍后重试。', cause: error, stackTrace: stackTrace),
      );
    } on Failure catch (failure) {
      return FailureResult(failure);
    } catch (error, stackTrace) {
      _logger.error('通知详情解析失败', error: error, stackTrace: stackTrace);
      return FailureResult(
        ParsingFailure('通知详情解析失败。', cause: error, stackTrace: stackTrace),
      );
    }
  }

  Future<Result<Uint8List>> fetchImageBytes({
    required AppSession session,
    required Uri imageUri,
    Uri? referer,
  }) {
    return _fetchProtectedBytes(
      session: session,
      resourceUri: imageUri,
      referer: referer,
      resourceLabel: '图片',
    );
  }

  Future<Result<Uint8List>> fetchAttachmentBytes({
    required AppSession session,
    required Uri attachmentUri,
    Uri? referer,
  }) {
    return _fetchProtectedBytes(
      session: session,
      resourceUri: attachmentUri,
      referer: referer,
      resourceLabel: '附件',
    );
  }

  Future<Result<Uint8List>> _fetchProtectedBytes({
    required AppSession session,
    required Uri resourceUri,
    required String resourceLabel,
    Uri? referer,
  }) async {
    final cookieStore = _CookieStore(session.cookies);
    final extraHeaders = <String, String>{
      if (referer != null) 'Referer': referer.toString(),
    };

    try {
      _logger.info(
        '[NOTICE] $resourceLabel开始抓取 uri=$resourceUri '
        'referer=${referer ?? '-'} cookieCount=${session.cookies.length}',
      );
      final resolved = await _resolveResponse(
        resourceUri,
        cookieStore,
        extraHeaders: extraHeaders,
      );
      final response = resolved.response;

      _logger.info(
        '[NOTICE] $resourceLabel响应 status=${response.statusCode} '
        'redirects=${resolved.hopCount} uri=${response.uri} '
        'contentType=${response.contentType ?? '-'} bytes=${response.bytes.length}',
      );

      if (_looksLikeLoginPage(response.body)) {
        _logger.warn('[NOTICE] $resourceLabel响应疑似登录页');
        return const FailureResult(SessionExpiredFailure('通知系统登录态已失效，请重新登录。'));
      }

      if (_looksLikeMissingPage(response.body)) {
        _logger.warn('[NOTICE] $resourceLabel响应疑似 404');
        return FailureResult(BusinessFailure('通知$resourceLabel暂时无法访问。'));
      }

      if (response.statusCode != 200) {
        return FailureResult(
          NetworkFailure('通知$resourceLabel访问失败，状态码 ${response.statusCode}。'),
        );
      }

      if (_looksLikeHtmlPayload(response)) {
        return FailureResult(BusinessFailure('通知$resourceLabel响应异常。'));
      }

      if (response.bytes.isEmpty) {
        return FailureResult(BusinessFailure('通知$resourceLabel内容为空。'));
      }

      return Success(response.bytes);
    } on DioException catch (error, stackTrace) {
      _logger.error(
        '通知$resourceLabel抓取失败',
        error: error,
        stackTrace: stackTrace,
      );
      return FailureResult(
        NetworkFailure(
          '通知$resourceLabel访问失败，请稍后重试。',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    } on Failure catch (failure) {
      return FailureResult(failure);
    } catch (error, stackTrace) {
      _logger.error(
        '通知$resourceLabel解析失败',
        error: error,
        stackTrace: stackTrace,
      );
      return FailureResult(
        ParsingFailure(
          '通知$resourceLabel解析失败。',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  Future<_TransportResponse> _get(
    Uri uri,
    _CookieStore cookieStore, {
    Map<String, String> extraHeaders = const {},
  }) async {
    final headers = <String, String>{...extraHeaders};
    final cookieHeader = cookieStore.cookieHeaderFor(uri);
    if (cookieHeader.isNotEmpty) {
      headers['Cookie'] = cookieHeader;
    }

    _logger.debug(
      '[NOTICE] GET $uri cookieCount=${cookieStore._cookies.length} '
      'hasCookieHeader=${cookieHeader.isNotEmpty} '
      'extraHeaders=${extraHeaders.keys.join(",")}',
    );
    final response = await _dio.getUri<List<int>>(
      uri,
      options: Options(headers: headers),
    );
    final setCookies = response.headers['set-cookie'] ?? const [];
    cookieStore.absorb(uri, setCookies);

    _logger.debug(
      '[NOTICE] GET response status=${response.statusCode} '
      'bodyLen=${response.data?.length ?? 0} '
      'location=${response.headers.value('location') ?? '-'} '
      'setCookies=${setCookies.length}',
    );

    final bytes = Uint8List.fromList(response.data ?? const <int>[]);
    return _TransportResponse(
      uri: uri,
      statusCode: response.statusCode ?? 0,
      bytes: bytes,
      body: _decodeBody(bytes),
      location: response.headers.value('location'),
      contentType: response.headers.value(Headers.contentTypeHeader),
    );
  }

  Future<_ResolvedResponse> _resolveResponse(
    Uri requestUri,
    _CookieStore cookieStore, {
    Map<String, String> extraHeaders = const {},
  }) async {
    var response = await _get(
      requestUri,
      cookieStore,
      extraHeaders: extraHeaders,
    );
    var hopCount = 0;
    var retriedOriginalUri = false;

    while (hopCount < 12) {
      final nextUri = _nextHopUri(response);
      if (nextUri != null) {
        response = await _get(nextUri, cookieStore, extraHeaders: extraHeaders);
        hopCount += 1;
        continue;
      }

      if (!retriedOriginalUri && _looksLikeAuthBridgePage(response)) {
        retriedOriginalUri = true;
        hopCount += 1;
        _logger.info(
          '[NOTICE] 命中认证桥接页 bridge=${response.uri}，重试原始地址 original=$requestUri',
        );
        response = await _get(
          requestUri,
          cookieStore,
          extraHeaders: extraHeaders,
        );
        continue;
      }

      break;
    }

    return _ResolvedResponse(response: response, hopCount: hopCount);
  }

  Uri? _nextHopUri(_TransportResponse response) {
    final location = response.location;
    if (location != null && location.isNotEmpty) {
      return response.uri.resolve(location);
    }

    if (!_looksLikeHtmlPayload(response)) {
      return null;
    }

    return _extractHtmlRedirectUri(response.uri, response.body);
  }

  Uri? _extractHtmlRedirectUri(Uri baseUri, String body) {
    if (body.trim().isEmpty) {
      return null;
    }

    final document = html_parser.parse(body);
    for (final meta in document.querySelectorAll('meta[http-equiv]')) {
      final httpEquiv = meta.attributes['http-equiv']?.trim().toLowerCase();
      if (httpEquiv != 'refresh') {
        continue;
      }

      final content = meta.attributes['content'] ?? '';
      final match = RegExp(
        r'url\s*=\s*([^;]+)$',
        caseSensitive: false,
      ).firstMatch(content);
      final resolved = _resolveRedirectCandidate(baseUri, match?.group(1));
      if (resolved != null) {
        return resolved;
      }
    }

    final normalizedBody = body.replaceAll('&amp;', '&');
    const patterns = [
      r'''(?:window\.|self\.|top\.)?location(?:\.href)?\s*=\s*['"]([^'"]+)['"]''',
      r'''(?:window\.|self\.|top\.)?location\.replace\(\s*['"]([^'"]+)['"]\s*\)''',
    ];

    for (final source in patterns) {
      final match = RegExp(
        source,
        caseSensitive: false,
      ).firstMatch(normalizedBody);
      final resolved = _resolveRedirectCandidate(baseUri, match?.group(1));
      if (resolved != null) {
        return resolved;
      }
    }

    return null;
  }

  Uri? _resolveRedirectCandidate(Uri baseUri, String? rawValue) {
    final value = rawValue?.trim().replaceAll('&amp;', '&') ?? '';
    if (value.isEmpty) {
      return null;
    }

    final lower = value.toLowerCase();
    if (lower.startsWith('javascript:') || lower.startsWith('about:')) {
      return null;
    }

    return baseUri.resolve(value);
  }

  String _decodeBody(List<int>? bytes) {
    if (bytes == null || bytes.isEmpty) {
      return '';
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  bool _looksLikeLoginPage(String body) {
    return body.contains('统一身份认证平台') ||
        body.contains('/authserver/login') ||
        body.contains('账号登录');
  }

  bool _looksLikeHtmlPayload(_TransportResponse response) {
    final contentType = response.contentType?.toLowerCase() ?? '';
    if (contentType.contains('text/html') ||
        contentType.contains('text/plain')) {
      return true;
    }

    final value = response.body.trimLeft().toLowerCase();
    return value.startsWith('<!doctype html') ||
        value.startsWith('<html') ||
        value.contains('<body') ||
        value.contains('统一身份认证平台');
  }

  bool _looksLikeAuthBridgePage(_TransportResponse response) {
    return response.uri.path.toLowerCase().endsWith('/code/auth/clogin.jsp') ||
        response.uri.path.toLowerCase().endsWith('clogin.jsp');
  }

  bool _looksLikeMissingPage(String body) {
    return body.contains('您访问的页面未找到');
  }

  void _logHtmlIfEnabled({required String title, required String body}) {
    if (!_logRawHtml) {
      return;
    }
    _logger.infoBlock(title, body);
  }
}

class _CookieStore {
  _CookieStore([Iterable<PortalCookie> cookies = const []])
    : _cookies = List<PortalCookie>.from(cookies);

  final List<PortalCookie> _cookies;

  String cookieHeaderFor(Uri uri) {
    return _cookies
        .where((cookie) => cookie.matches(uri))
        .map((cookie) => '${cookie.name}=${cookie.value}')
        .join('; ');
  }

  void absorb(Uri uri, List<String> setCookieHeaders) {
    for (final header in setCookieHeaders) {
      final parsed = _parseSetCookie(uri, header);
      if (parsed == null) {
        continue;
      }

      _cookies.removeWhere(
        (item) =>
            item.name == parsed.name &&
            item.domain == parsed.domain &&
            item.path == parsed.path,
      );
      _cookies.add(parsed);
    }
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
      name: nameValue.first.trim(),
      value: nameValue.sublist(1).join('=').trim(),
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
    required this.bytes,
    required this.body,
    required this.location,
    required this.contentType,
  });

  final Uri uri;
  final int statusCode;
  final Uint8List bytes;
  final String body;
  final String? location;
  final String? contentType;
}

class _ResolvedResponse {
  const _ResolvedResponse({required this.response, required this.hopCount});

  final _TransportResponse response;
  final int hopCount;
}
