import 'dart:async';

import 'package:flutter/foundation.dart';

/// 一条日志记录。日志页会渲染这种数据。
class AppLogEntry {
  AppLogEntry({
    required this.level,
    required this.message,
    DateTime? timestamp,
    this.title,
    this.body,
    this.cause,
    this.stackTrace,
  }) : timestamp = timestamp ?? DateTime.now();

  final AppLogLevel level;
  final DateTime timestamp;
  final String message;

  /// 块状日志的标题（如 `[Gym][Submit][abc] formData`）。
  final String? title;

  /// 块状日志的正文（一般是 JSON 字符串）。
  final String? body;

  /// `error` 级别附带的异常对象。
  final Object? cause;
  final StackTrace? stackTrace;

  bool get hasBlock => (title != null && (body?.isNotEmpty ?? false));
}

enum AppLogLevel { debug, info, warn, error }

extension AppLogLevelX on AppLogLevel {
  String get label => switch (this) {
    AppLogLevel.debug => 'DEBUG',
    AppLogLevel.info => 'INFO',
    AppLogLevel.warn => 'WARN',
    AppLogLevel.error => 'ERROR',
  };
}

/// 进程内的环形日志缓冲。
/// 业务层往 [AppLogger] 打日志时，会同步推一份到这里，
/// 设置页里的「日志」可以从这里读取最近 N 条。
class AppLogBuffer {
  AppLogBuffer({this.capacity = 500});

  final int capacity;
  final List<AppLogEntry> _entries = <AppLogEntry>[];
  final StreamController<AppLogEntry> _controller =
      StreamController<AppLogEntry>.broadcast();

  List<AppLogEntry> get entries => List.unmodifiable(_entries);

  Stream<AppLogEntry> get onAppend => _controller.stream;

  void append(AppLogEntry entry) {
    _entries.add(entry);
    if (_entries.length > capacity) {
      _entries.removeRange(0, _entries.length - capacity);
    }
    if (!_controller.isClosed) {
      _controller.add(entry);
    }
  }

  void clear() {
    _entries.clear();
  }
}

/// 全局唯一的日志缓冲实例。logger 和日志页共用它。
final AppLogBuffer appLogBuffer = AppLogBuffer();

class AppLogger {
  const AppLogger({this.buffer});

  /// 默认走全局缓冲，可在测试里替换为别的实例。
  final AppLogBuffer? buffer;

  AppLogBuffer get _buffer => buffer ?? appLogBuffer;

  static const _chunkSize = 900;

  void debug(String message) {
    debugPrint('[DEBUG] $message');
    _buffer.append(
      AppLogEntry(level: AppLogLevel.debug, message: message),
    );
  }

  void info(String message) {
    debugPrint('[INFO] $message');
    _buffer.append(
      AppLogEntry(level: AppLogLevel.info, message: message),
    );
  }

  void warn(String message) {
    debugPrint('[WARN] $message');
    _buffer.append(
      AppLogEntry(level: AppLogLevel.warn, message: message),
    );
  }

  void error(String message, {Object? error, StackTrace? stackTrace}) {
    debugPrint('[ERROR] $message');
    if (error != null) {
      debugPrint('  cause: $error');
    }
    if (stackTrace != null) {
      debugPrint('  stackTrace: $stackTrace');
    }
    _buffer.append(
      AppLogEntry(
        level: AppLogLevel.error,
        message: message,
        cause: error,
        stackTrace: stackTrace,
      ),
    );
  }

  void debugBlock(String title, String content) {
    _printBlock(level: AppLogLevel.debug, title: title, content: content);
  }

  void infoBlock(String title, String content) {
    _printBlock(level: AppLogLevel.info, title: title, content: content);
  }

  void warnBlock(String title, String content) {
    _printBlock(level: AppLogLevel.warn, title: title, content: content);
  }

  void _printBlock({
    required AppLogLevel level,
    required String title,
    required String content,
  }) {
    final levelLabel = level.label;
    debugPrint('[$levelLabel] $title BEGIN');
    if (content.isEmpty) {
      debugPrint('[$levelLabel] <empty>');
      debugPrint('[$levelLabel] $title END');
    } else {
      for (final line in content.split('\n')) {
        if (line.isEmpty) {
          debugPrint('[$levelLabel] ');
          continue;
        }
        for (var start = 0; start < line.length; start += _chunkSize) {
          final end = start + _chunkSize > line.length
              ? line.length
              : start + _chunkSize;
          debugPrint('[$levelLabel] ${line.substring(start, end)}');
        }
      }
      debugPrint('[$levelLabel] $title END');
    }

    _buffer.append(
      AppLogEntry(
        level: level,
        message: title,
        title: title,
        body: content,
      ),
    );
  }
}
