import 'package:dio/dio.dart';

import '../../core/error/failure.dart';
import '../../core/logging/app_logger.dart';
import '../../core/result/result.dart';
import '../../modules/home/domain/entities/hitokoto_quote.dart';

class HitokotoApi {
  HitokotoApi({required AppLogger logger, required String userAgent, Dio? dio})
    : _logger = logger,
      _dio = dio ?? _createDio(userAgent);

  final AppLogger _logger;
  final Dio _dio;

  static Dio _createDio(String userAgent) {
    return Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 4),
        receiveTimeout: const Duration(seconds: 4),
        responseType: ResponseType.json,
        headers: {'User-Agent': userAgent},
      ),
    );
  }

  Future<Result<HitokotoQuote>> fetchQuote() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        'https://v1.hitokoto.cn/',
        queryParameters: const {'encode': 'json', 'max_length': '30'},
      );
      final data = response.data;
      final text = data?['hitokoto']?.toString().trim();
      if (text == null || text.isEmpty) {
        return const FailureResult(ParsingFailure('一言内容为空。'));
      }

      return Success(
        HitokotoQuote(
          text: text,
          source: data?['from']?.toString(),
          author: data?['from_who']?.toString(),
          uuid: data?['uuid']?.toString(),
        ),
      );
    } on DioException catch (error, stackTrace) {
      _logger.warn(
        '一言获取失败 status=${error.response?.statusCode} message=${error.message}',
      );
      return FailureResult(
        NetworkFailure('一言获取失败，请稍后再试。', cause: error, stackTrace: stackTrace),
      );
    } catch (error, stackTrace) {
      _logger.warn('一言解析失败: $error');
      return FailureResult(
        ParsingFailure('一言解析失败。', cause: error, stackTrace: stackTrace),
      );
    }
  }
}
