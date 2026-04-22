import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../core/error/failure.dart';
import '../../core/logging/app_logger.dart';
import '../../core/result/result.dart';
import '../../modules/notices/domain/entities/campus_notice.dart';
import 'wyu_graduate_notice_parser.dart';

class WyuGraduateNoticeApi {
  WyuGraduateNoticeApi({
    required AppLogger logger,
    required String userAgent,
    WyuGraduateNoticeParser parser = const WyuGraduateNoticeParser(),
    Dio? dio,
  }) : _logger = logger,
       _parser = parser,
       _dio = dio ?? _createDio(userAgent);

  static final _snapshotUri = Uri.parse('https://www.wyu.edu.cn/yjscx/');

  final AppLogger _logger;
  final WyuGraduateNoticeParser _parser;
  final Dio _dio;

  static Dio _createDio(String userAgent) {
    return Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 20),
        responseType: ResponseType.bytes,
        validateStatus: (_) => true,
        headers: {'User-Agent': userAgent, 'Accept-Language': 'zh-CN,zh;q=0.9'},
      ),
    );
  }

  Future<Result<CampusNoticeSnapshot>> fetchSnapshot() async {
    try {
      final response = await _get(_snapshotUri);
      if (response.statusCode != 200) {
        return FailureResult(
          NetworkFailure('研究生通知首页访问失败，状态码 ${response.statusCode}。'),
        );
      }

      return Success(
        _parser.parseSnapshot(
          response.body,
          baseUri: _snapshotUri,
          logger: _logger,
        ),
      );
    } on DioException catch (error, stackTrace) {
      _logger.error('研究生通知首页抓取失败', error: error, stackTrace: stackTrace);
      return FailureResult(
        NetworkFailure(
          '研究生通知首页访问失败，请检查网络连接。',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    } on Failure catch (failure) {
      return FailureResult(failure);
    } catch (error, stackTrace) {
      _logger.error('研究生通知首页解析失败', error: error, stackTrace: stackTrace);
      return FailureResult(
        ParsingFailure('研究生通知首页解析失败。', cause: error, stackTrace: stackTrace),
      );
    }
  }

  Future<Result<CampusNoticeCategoryPage>> fetchCategoryPage({
    required CampusNoticeCategory category,
    required Uri pageUri,
  }) async {
    try {
      final response = await _get(pageUri);
      if (response.statusCode != 200) {
        return FailureResult(
          NetworkFailure('研究生通知列表访问失败，状态码 ${response.statusCode}。'),
        );
      }

      return Success(
        _parser.parseCategoryPage(
          response.body,
          pageUri: pageUri,
          category: category,
          logger: _logger,
        ),
      );
    } on DioException catch (error, stackTrace) {
      _logger.error('研究生通知列表抓取失败', error: error, stackTrace: stackTrace);
      return FailureResult(
        NetworkFailure(
          '研究生通知列表访问失败，请稍后重试。',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    } on Failure catch (failure) {
      return FailureResult(failure);
    } catch (error, stackTrace) {
      _logger.error('研究生通知列表解析失败', error: error, stackTrace: stackTrace);
      return FailureResult(
        ParsingFailure('研究生通知列表解析失败。', cause: error, stackTrace: stackTrace),
      );
    }
  }

  Future<Result<CampusNoticeDetail>> fetchDetail({
    required CampusNoticeItem item,
  }) async {
    try {
      final response = await _get(item.detailUri);
      if (response.statusCode != 200) {
        return FailureResult(
          NetworkFailure('研究生通知详情访问失败，状态码 ${response.statusCode}。'),
        );
      }

      return Success(
        _parser.parseDetail(
          html: response.body,
          pageUri: item.detailUri,
          item: item,
          logger: _logger,
        ),
      );
    } on DioException catch (error, stackTrace) {
      _logger.error('研究生通知详情抓取失败', error: error, stackTrace: stackTrace);
      return FailureResult(
        NetworkFailure(
          '研究生通知详情访问失败，请稍后重试。',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    } on Failure catch (failure) {
      return FailureResult(failure);
    } catch (error, stackTrace) {
      _logger.error('研究生通知详情解析失败', error: error, stackTrace: stackTrace);
      return FailureResult(
        ParsingFailure('研究生通知详情解析失败。', cause: error, stackTrace: stackTrace),
      );
    }
  }

  Future<Result<Uint8List>> fetchPublicBytes({
    required Uri resourceUri,
    Uri? referer,
  }) async {
    try {
      final response = await _get(
        resourceUri,
        extraHeaders: {if (referer != null) 'Referer': referer.toString()},
      );
      if (response.statusCode != 200) {
        return FailureResult(
          NetworkFailure('研究生通知资源访问失败，状态码 ${response.statusCode}。'),
        );
      }
      if (response.bytes.isEmpty) {
        return const FailureResult(BusinessFailure('研究生通知资源内容为空。'));
      }
      if (_looksLikeHtmlPayload(response)) {
        return const FailureResult(BusinessFailure('研究生通知资源响应异常。'));
      }

      return Success(response.bytes);
    } on DioException catch (error, stackTrace) {
      _logger.error('研究生通知资源抓取失败', error: error, stackTrace: stackTrace);
      return FailureResult(
        NetworkFailure(
          '研究生通知资源访问失败，请稍后重试。',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    } on Failure catch (failure) {
      return FailureResult(failure);
    } catch (error, stackTrace) {
      _logger.error('研究生通知资源解析失败', error: error, stackTrace: stackTrace);
      return FailureResult(
        ParsingFailure('研究生通知资源解析失败。', cause: error, stackTrace: stackTrace),
      );
    }
  }

  Future<_TransportResponse> _get(
    Uri uri, {
    Map<String, String> extraHeaders = const {},
  }) async {
    final response = await _dio.getUri<List<int>>(
      uri,
      options: Options(headers: extraHeaders),
    );
    final bytes = Uint8List.fromList(response.data ?? const <int>[]);

    return _TransportResponse(
      statusCode: response.statusCode ?? 0,
      bytes: bytes,
      body: utf8.decode(bytes, allowMalformed: true),
      contentType: response.headers.value(Headers.contentTypeHeader),
    );
  }

  bool _looksLikeHtmlPayload(_TransportResponse response) {
    final contentType = response.contentType?.toLowerCase() ?? '';
    if (contentType.contains('text/html') ||
        contentType.contains('text/plain')) {
      return true;
    }

    final body = response.body.trimLeft().toLowerCase();
    return body.startsWith('<!doctype html') ||
        body.startsWith('<html') ||
        body.contains('<body');
  }
}

class _TransportResponse {
  const _TransportResponse({
    required this.statusCode,
    required this.bytes,
    required this.body,
    required this.contentType,
  });

  final int statusCode;
  final Uint8List bytes;
  final String body;
  final String? contentType;
}
