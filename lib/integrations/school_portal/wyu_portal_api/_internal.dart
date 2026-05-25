// 内部数据结构与底层 HTTP / 日志助手。
// 这里的 _CookieStore / _TransportResponse / _RuntimeState 全部是 part-private，
// 仅在 wyu_portal_api 这一 library 内被使用。
part of '../wyu_portal_api.dart';

// -------------------- 常量 --------------------

const String _portalServiceUrl = 'https://ehall.wyu.edu.cn/login';
const String _serviceCardWid = '8558486040491173';
const String _yjsServiceCardWid = '017434820995445355';
const String _defaultYjsServiceWid = '1268168848874270720';
final Uri _loginUri = Uri.parse(
  'https://authserver.wyu.edu.cn/authserver/login',
);
final encrypt.Key _yjsAesKey = encrypt.Key.fromUtf8('southsoft12345!#');

// 个人中心相关常量
const String _userLogsUrl =
    'https://authserver.wyu.edu.cn/personalInfo/UserLogs/user/queryUserLogs';
const String _userOnlineUrl =
    'https://authserver.wyu.edu.cn/personalInfo/UserOnline/user/queryUserOnline';
const String _personalInfoIndexUrl =
    'https://authserver.wyu.edu.cn/personalInfo/';
const Map<String, String> _personalInfoHeaders = {
  'Accept': 'application/json, text/plain, */*',
  'Origin': 'https://authserver.wyu.edu.cn',
  'Referer': _personalInfoIndexUrl,
  'X-Requested-With': 'XMLHttpRequest',
};

// 短信登录手机号字段加密盐
const String _smsMobileSalt = 'rjBFAaHsNkKAhpoi';

// 体育馆 / 生活服务分类
const String _gymServiceTypeId = '1296107574652694529';

// -------------------- 私有辅助类型 --------------------

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

// -------------------- HTTP / 日志 / 解析助手 --------------------

extension WyuPortalHttpInternal on WyuPortalApi {
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
    _CookieStore cookieStore, {
    Map<String, String>? extraHeaders,
  }) async {
    final headers = _headersFor(uri, cookieStore);
    if (extraHeaders != null) {
      headers.addAll(extraHeaders);
    }
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

  // -------- 通用判定 / 字段解析 --------

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

  List<PortalCookie> _cookiesForLaunchUri(
    Iterable<PortalCookie> cookies,
    Uri uri,
  ) {
    return cookies.where((cookie) => cookie.matches(uri)).toList();
  }
}
