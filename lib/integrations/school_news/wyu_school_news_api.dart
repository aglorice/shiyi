import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../core/error/failure.dart';
import '../../core/logging/app_logger.dart';
import '../../core/result/result.dart';
import '../../modules/school_news/domain/entities/school_news.dart';
import 'wyu_school_news_parser.dart';

class WyuSchoolNewsApi {
  WyuSchoolNewsApi({
    required AppLogger logger,
    required String userAgent,
    WyuSchoolNewsParser parser = const WyuSchoolNewsParser(),
    Dio? dio,
  }) : _logger = logger,
       _parser = parser,
       _dio = dio ?? _createDio(userAgent);

  static final firstPageUri = Uri.parse(
    'https://www.wyu.edu.cn/index/xxyw.htm',
  );

  final AppLogger _logger;
  final WyuSchoolNewsParser _parser;
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

  Future<Result<SchoolNewsPageData>> fetchPage({Uri? pageUri}) async {
    final uri = pageUri ?? firstPageUri;
    try {
      _logger.info('[SCHOOL_NEWS] 列表开始抓取 uri=$uri');
      final response = await _dio.getUri<List<int>>(uri);
      final statusCode = response.statusCode ?? 0;
      final bytes = Uint8List.fromList(response.data ?? const <int>[]);
      final body = utf8.decode(bytes, allowMalformed: true);

      _logger.info(
        '[SCHOOL_NEWS] 列表响应 status=$statusCode uri=$uri bodyLen=${body.length}',
      );

      if (statusCode != 200) {
        return FailureResult(NetworkFailure('学校要闻访问失败，状态码 $statusCode。'));
      }

      final page = _parser.parsePage(body, pageUri: uri, logger: _logger);
      return Success(page);
    } on DioException catch (error, stackTrace) {
      _logger.error('学校要闻抓取失败', error: error, stackTrace: stackTrace);
      return FailureResult(
        NetworkFailure(
          '学校要闻访问失败，请检查网络连接。',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    } on Failure catch (failure) {
      return FailureResult(failure);
    } catch (error, stackTrace) {
      _logger.error('学校要闻解析失败', error: error, stackTrace: stackTrace);
      return FailureResult(
        ParsingFailure('学校要闻解析失败。', cause: error, stackTrace: stackTrace),
      );
    }
  }

  Future<Result<SchoolNewsDetail>> fetchDetail({
    required SchoolNewsItem item,
  }) async {
    final uri = item.detailUri;
    try {
      _logger.info('[SCHOOL_NEWS] 详情开始抓取 title=${item.title} uri=$uri');
      final response = await _dio.getUri<List<int>>(uri);
      final statusCode = response.statusCode ?? 0;
      final bytes = Uint8List.fromList(response.data ?? const <int>[]);
      final body = utf8.decode(bytes, allowMalformed: true);

      _logger.info(
        '[SCHOOL_NEWS] 详情响应 status=$statusCode uri=$uri bodyLen=${body.length}',
      );

      if (statusCode != 200) {
        return FailureResult(NetworkFailure('学校要闻正文访问失败，状态码 $statusCode。'));
      }

      final detail = _parser.parseDetail(
        html: body,
        pageUri: uri,
        item: item,
        logger: _logger,
      );
      return Success(detail);
    } on DioException catch (error, stackTrace) {
      _logger.error('学校要闻正文抓取失败', error: error, stackTrace: stackTrace);
      return FailureResult(
        NetworkFailure(
          '学校要闻正文访问失败，请稍后重试。',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    } on Failure catch (failure) {
      return FailureResult(failure);
    } catch (error, stackTrace) {
      _logger.error('学校要闻正文解析失败', error: error, stackTrace: stackTrace);
      return FailureResult(
        ParsingFailure('学校要闻正文解析失败。', cause: error, stackTrace: stackTrace),
      );
    }
  }

  Future<Result<Uint8List>> fetchPublicBytes({
    required Uri resourceUri,
    Uri? referer,
  }) async {
    try {
      final response = await _dio.getUri<List<int>>(
        resourceUri,
        options: Options(
          headers: {if (referer != null) 'Referer': referer.toString()},
        ),
      );
      final statusCode = response.statusCode ?? 0;
      final bytes = Uint8List.fromList(response.data ?? const <int>[]);
      final contentType = response.headers.value(Headers.contentTypeHeader);

      _logger.info(
        '[SCHOOL_NEWS] 公开资源响应 status=$statusCode uri=$resourceUri '
        'contentType=${contentType ?? '-'} bytes=${bytes.length}',
      );

      if (statusCode != 200) {
        return FailureResult(NetworkFailure('学校要闻资源访问失败，状态码 $statusCode。'));
      }
      if (bytes.isEmpty) {
        return const FailureResult(BusinessFailure('学校要闻资源内容为空。'));
      }
      if (_looksLikeHtmlPayload(contentType: contentType, bytes: bytes)) {
        return const FailureResult(BusinessFailure('学校要闻资源响应异常。'));
      }

      return Success(bytes);
    } on DioException catch (error, stackTrace) {
      _logger.error('学校要闻资源抓取失败', error: error, stackTrace: stackTrace);
      return FailureResult(
        NetworkFailure(
          '学校要闻资源访问失败，请稍后重试。',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    } on Failure catch (failure) {
      return FailureResult(failure);
    } catch (error, stackTrace) {
      _logger.error('学校要闻资源解析失败', error: error, stackTrace: stackTrace);
      return FailureResult(
        ParsingFailure('学校要闻资源解析失败。', cause: error, stackTrace: stackTrace),
      );
    }
  }

  bool _looksLikeHtmlPayload({
    required String? contentType,
    required Uint8List bytes,
  }) {
    final normalizedType = contentType?.toLowerCase() ?? '';
    if (normalizedType.contains('text/html') ||
        normalizedType.contains('text/plain')) {
      return true;
    }

    final body = utf8
        .decode(bytes, allowMalformed: true)
        .trimLeft()
        .toLowerCase();
    return body.startsWith('<!doctype html') ||
        body.startsWith('<html') ||
        body.contains('<body');
  }
}
