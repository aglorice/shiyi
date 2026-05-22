import 'dart:async';

/// 一次接口往返的结构化记录。
///
/// 设计目标：
/// - 列表里能直接看到「方法 + URL + 状态 + 耗时」一眼就懂；
/// - 详情页能完整看到 URL / 请求体 / 响应体（带 JSON 格式化）。
class ApiLogEntry {
  ApiLogEntry({
    required this.id,
    required this.method,
    required this.url,
    required this.startedAt,
    this.label,
    this.requestHeaders,
    this.requestBody,
    this.endedAt,
    this.statusCode,
    this.responseBody,
    this.failureMessage,
  });

  /// 自增 id，按时间倒序时用。
  final int id;

  /// 业务侧用的简短标签，例如「Gym.checkCanApply」。可空。
  final String? label;

  /// HTTP 方法。
  final String method;

  /// 完整 URL（含 query）。
  final String url;

  /// 请求开始时间。
  final DateTime startedAt;

  /// 请求结束时间。完成后才有值。
  DateTime? endedAt;

  /// HTTP 状态码。完成后才有值。
  int? statusCode;

  /// 请求头（敏感字段已掩码）。
  Map<String, String>? requestHeaders;

  /// 请求体——可能是 form fields 或 JSON。统一存成「key/value 字符串映射」
  /// 或 [String]，UI 自己判断渲染成 JSON 还是 form 表格。
  Object? requestBody;

  /// 响应体。文本或 JSON-decoded 对象。
  Object? responseBody;

  /// 网络/业务失败信息。响应体能解析时通常没有这一项。
  String? failureMessage;

  Duration? get duration {
    final ended = endedAt;
    if (ended == null) return null;
    return ended.difference(startedAt);
  }

  bool get inFlight => endedAt == null;

  bool get isSuccess {
    if (failureMessage != null) return false;
    final code = statusCode;
    if (code == null) return false;
    return code >= 200 && code < 400;
  }
}

/// 进程内环形缓冲，最多保存 [capacity] 条 [ApiLogEntry]。
/// 设置 → 请求日志页从这里读取数据。
class ApiLogBuffer {
  ApiLogBuffer({this.capacity = 200});

  final int capacity;
  final List<ApiLogEntry> _entries = <ApiLogEntry>[];
  final StreamController<ApiLogEntry> _controller =
      StreamController<ApiLogEntry>.broadcast();
  int _nextId = 1;

  List<ApiLogEntry> get entries => List.unmodifiable(_entries);
  Stream<ApiLogEntry> get onChanged => _controller.stream;

  /// 创建一条新记录并立即推送（in-flight 状态）。
  /// 调用方拿到返回值后，等响应回来再调用 [complete] 把状态填上。
  ApiLogEntry begin({
    required String method,
    required String url,
    Map<String, String>? requestHeaders,
    Object? requestBody,
    String? label,
  }) {
    final entry = ApiLogEntry(
      id: _nextId++,
      method: method.toUpperCase(),
      url: url,
      startedAt: DateTime.now(),
      label: label,
      requestHeaders: requestHeaders,
      requestBody: requestBody,
    );
    _entries.add(entry);
    if (_entries.length > capacity) {
      _entries.removeRange(0, _entries.length - capacity);
    }
    if (!_controller.isClosed) {
      _controller.add(entry);
    }
    return entry;
  }

  void complete(
    ApiLogEntry entry, {
    int? statusCode,
    Object? responseBody,
    String? failureMessage,
  }) {
    entry
      ..endedAt = DateTime.now()
      ..statusCode = statusCode
      ..responseBody = responseBody
      ..failureMessage = failureMessage;
    if (!_controller.isClosed) {
      _controller.add(entry);
    }
  }

  void clear() {
    _entries.clear();
  }
}

/// 全局单例。logger / portal api / 日志页共用。
final ApiLogBuffer apiLogBuffer = ApiLogBuffer();
