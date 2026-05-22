import 'package:dio/dio.dart';

import '../../core/error/failure.dart';
import '../../core/logging/api_log_interceptor.dart';
import '../../core/logging/app_logger.dart';
import '../../core/result/result.dart';
import '../../modules/electricity/domain/entities/electricity_dashboard.dart';
import 'wyu_electricity_parser.dart';

class WyuElectricityApi {
  WyuElectricityApi({
    required WyuElectricityParser parser,
    required AppLogger logger,
    required String userAgent,
  }) : _parser = parser,
       _logger = logger,
       _dio = Dio(
         BaseOptions(
           baseUrl: 'http://202.192.240.231/scp-api/electricity-recharge',
           connectTimeout: const Duration(seconds: 20),
           receiveTimeout: const Duration(seconds: 20),
           responseType: ResponseType.plain,
           validateStatus: (_) => true,
           headers: {'User-Agent': userAgent},
         ),
       )..interceptors.add(ApiLogInterceptor(label: 'Electricity'));

  final WyuElectricityParser _parser;
  final AppLogger _logger;
  final Dio _dio;

  Future<Result<WyuElectricityBalancePayload>> fetchCurrentRemaining(
    ElectricityRoomBinding binding,
  ) async {
    _logger.info(
      '[Electricity] 开始查询剩余电量 '
      'building=${binding.requestBuilding} room=${binding.requestRoomNumber} '
      'userTypeId=${binding.userTypeId} '
      'url=${_dio.options.baseUrl}/getCurrentRemaining_v2',
    );
    try {
      final formData = {
        'userTypeID': binding.userTypeId,
        'building': binding.requestBuilding,
        'room': binding.requestRoomNumber,
      };
      _logger.debug(
        '[Electricity] POST form data: $formData',
      );
      final response = await _dio.post(
        '/getCurrentRemaining_v2',
        data: formData,
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      _logger.info(
        '[Electricity] 电量接口响应 status=${response.statusCode} '
        'bodyLen=${(response.data?.toString().length ?? 0)}',
      );
      if (response.statusCode != 200) {
        return FailureResult(
          NetworkFailure('电量接口请求失败，状态码 ${response.statusCode}。'),
        );
      }

      final result = _parser.parseBalance(response.data.toString());
      if (result case FailureResult<WyuElectricityBalancePayload>(
        failure: final failure,
      )) {
        _logger.warn('[Electricity] 电量解析失败 reason=${failure.message}');
      }
      return result;
    } on DioException catch (error, stackTrace) {
      _logger.error(
        '[Electricity] 电量查询失败 building=${binding.requestBuilding} room=${binding.requestRoomNumber}',
        error: error,
        stackTrace: stackTrace,
      );
      return FailureResult(
        NetworkFailure('查询剩余电量失败。', cause: error, stackTrace: stackTrace),
      );
    }
  }

  Future<Result<WyuElectricityRechargePagePayload>> fetchRechargeHistory(
    ElectricityRoomBinding binding, {
    required ElectricityChargePeriod period,
    int pageSize = 50,
  }) async {
    try {
      final records = <WyuElectricityRechargeRecordPayload>[];
      var total = 0;
      var page = 1;

      while (true) {
        final response = await _dio.post(
          '/orderQueryWithPage',
          data: {
            'building': binding.requestBuilding,
            'room': binding.requestRoomNumber,
            'payResult': 1,
            'page': page,
            'pageSize': pageSize,
            'userTypeID': binding.userTypeId,
            'period': period.code,
          },
          options: Options(contentType: Headers.formUrlEncodedContentType),
        );
        if (response.statusCode != 200) {
          return FailureResult(
            NetworkFailure('充值记录请求失败，状态码 ${response.statusCode}。'),
          );
        }

        final parsed = _parser.parseRechargePage(response.data.toString());
        if (parsed case FailureResult<WyuElectricityRechargePagePayload>(
          failure: final failure,
        )) {
          return FailureResult(failure);
        }

        final payload = parsed.requireValue();
        total = payload.total;
        records.addAll(payload.records);

        final pageCount = payload.pageSize == 0
            ? 1
            : (payload.total / payload.pageSize).ceil();
        if (payload.records.isEmpty || page >= pageCount || page >= 10) {
          return Success(
            WyuElectricityRechargePagePayload(
              pageSize: payload.pageSize,
              total: total,
              page: 1,
              records: records,
            ),
          );
        }

        page += 1;
      }
    } on DioException catch (error, stackTrace) {
      _logger.error(
        '[Electricity] 充值记录查询失败 building=${binding.requestBuilding} room=${binding.requestRoomNumber} period=${period.code}',
        error: error,
        stackTrace: stackTrace,
      );
      return FailureResult(
        NetworkFailure('查询充值记录失败。', cause: error, stackTrace: stackTrace),
      );
    }
  }
}
