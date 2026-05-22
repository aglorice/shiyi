import 'package:dio/dio.dart';

import 'api_log_buffer.dart';

/// 把 Dio 走的每一次请求都登记到 [apiLogBuffer]，
/// 设置 → 请求日志 页面就能看到完整的 URL / 请求体 / 响应体。
///
/// 这样不论是 portal、电费、通知、新闻、Hitokoto、GitHub release，
/// 任何用 Dio 发的请求都会被自动捕捉，不需要在每个 api 类里手写记录。
class ApiLogInterceptor extends Interceptor {
  ApiLogInterceptor({this.label});

  /// 业务侧的简短标签，例如 "Gym"、"YJS"、"Electricity"。可选。
  final String? label;

  static const _entryKey = 'uniYi.apiLogEntry';

  /// 隐藏掉一些常见敏感头，避免在日志里泄露。
  static const _redactedHeaders = <String>{
    'authorization',
    'cookie',
    'set-cookie',
    'x-csrf-token',
  };

  Map<String, String>? _normalizeHeaders(Map<String, dynamic>? raw) {
    if (raw == null || raw.isEmpty) return null;
    final result = <String, String>{};
    raw.forEach((key, value) {
      final keyLower = key.toLowerCase();
      if (_redactedHeaders.contains(keyLower)) {
        result[key] = '<redacted>';
        return;
      }
      if (value is List) {
        result[key] = value.join(', ');
      } else {
        result[key] = '$value';
      }
    });
    return result;
  }

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) {
    final uri = options.uri;
    final entry = apiLogBuffer.begin(
      method: options.method,
      url: uri.toString(),
      label: label == null ? null : '$label.${_endpointHint(uri.path)}',
      requestHeaders: _normalizeHeaders(
        options.headers.cast<String, dynamic>(),
      ),
      requestBody: options.data,
    );
    options.extra[_entryKey] = entry;
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    final entry = response.requestOptions.extra[_entryKey];
    if (entry is ApiLogEntry) {
      apiLogBuffer.complete(
        entry,
        statusCode: response.statusCode,
        responseBody: response.data,
      );
    }
    handler.next(response);
  }

  @override
  void onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) {
    final entry = err.requestOptions.extra[_entryKey];
    if (entry is ApiLogEntry) {
      apiLogBuffer.complete(
        entry,
        statusCode: err.response?.statusCode,
        responseBody: err.response?.data,
        failureMessage: err.message ?? '$err',
      );
    }
    handler.next(err);
  }

  String _endpointHint(String path) {
    final segments = path
        .split('/')
        .where((seg) => seg.isNotEmpty && seg != 'do')
        .toList();
    if (segments.isEmpty) return path;
    return segments.last.replaceAll('.do', '');
  }
}
