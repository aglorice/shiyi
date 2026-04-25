import '../../../core/logging/app_logger.dart';
import '../../../core/models/data_origin.dart';
import '../../../core/result/result.dart';
import '../../../core/storage/json_cache_store.dart';
import '../../../integrations/school_news/wyu_school_news_api.dart';
import '../domain/entities/school_news.dart';
import '../domain/repositories/school_news_repository.dart';

class SchoolNewsRepositoryImpl implements SchoolNewsRepository {
  const SchoolNewsRepositoryImpl({
    required WyuSchoolNewsApi api,
    required JsonCacheStore cacheStore,
    required AppLogger logger,
  }) : _api = api,
       _cacheStore = cacheStore,
       _logger = logger;

  static const _pageCacheKeyPrefix = 'school_news.page.v1.';
  static const _detailCacheKeyPrefix = 'school_news.detail.v1.';

  final WyuSchoolNewsApi _api;
  final JsonCacheStore _cacheStore;
  final AppLogger _logger;

  @override
  Future<Result<SchoolNewsPageData>> fetchPage({
    Uri? pageUri,
    bool forceRefresh = false,
  }) async {
    final effectiveUri = pageUri ?? WyuSchoolNewsApi.firstPageUri;
    final cacheKey = _cacheKey(effectiveUri);

    if (!forceRefresh) {
      final cached = await _cacheStore.readMap(cacheKey);
      if (cached != null) {
        return Success(
          SchoolNewsPageData.fromJson(
            cached,
          ).copyWith(origin: DataOrigin.cache),
        );
      }
    }

    final remote = await _api.fetchPage(pageUri: effectiveUri);
    if (remote case Success<SchoolNewsPageData>(data: final page)) {
      if (forceRefresh && effectiveUri == WyuSchoolNewsApi.firstPageUri) {
        await _cacheStore.removeByPrefix(_pageCacheKeyPrefix);
      }
      await _cacheStore.writeMap(cacheKey, page.toJson());
      return Success(page);
    }

    final cached = await _cacheStore.readMap(cacheKey);
    if (cached != null) {
      _logger.warn('Falling back to cached school news page: $effectiveUri');
      return Success(
        SchoolNewsPageData.fromJson(cached).copyWith(origin: DataOrigin.cache),
      );
    }

    return FailureResult(remote.failureOrNull!);
  }

  @override
  Future<Result<SchoolNewsDetail>> fetchDetail({
    required SchoolNewsItem item,
    bool forceRefresh = false,
  }) async {
    final cacheKey = '$_detailCacheKeyPrefix${item.cacheKey}';
    if (!forceRefresh) {
      final cached = await _cacheStore.readMap(cacheKey);
      if (cached != null) {
        return Success(
          SchoolNewsDetail.fromJson(cached).copyWith(origin: DataOrigin.cache),
        );
      }
    }

    final remote = await _api.fetchDetail(item: item);
    if (remote case Success<SchoolNewsDetail>(data: final detail)) {
      await _cacheStore.writeMap(cacheKey, detail.toJson());
      return Success(detail);
    }

    final cached = await _cacheStore.readMap(cacheKey);
    if (cached != null) {
      _logger.warn(
        'Falling back to cached school news detail: ${item.cacheKey}',
      );
      return Success(
        SchoolNewsDetail.fromJson(cached).copyWith(origin: DataOrigin.cache),
      );
    }

    return FailureResult(remote.failureOrNull!);
  }

  String _cacheKey(Uri uri) => '$_pageCacheKeyPrefix$uri';
}
