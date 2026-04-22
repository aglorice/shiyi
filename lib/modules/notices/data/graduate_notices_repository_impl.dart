import '../../../core/logging/app_logger.dart';
import '../../../core/models/data_origin.dart';
import '../../../core/result/result.dart';
import '../../../core/storage/json_cache_store.dart';
import '../../../integrations/graduate_notices/wyu_graduate_notice_api.dart';
import '../domain/entities/campus_notice.dart';
import '../domain/repositories/graduate_notices_repository.dart';

class GraduateNoticesRepositoryImpl implements GraduateNoticesRepository {
  const GraduateNoticesRepositoryImpl({
    required WyuGraduateNoticeApi api,
    required JsonCacheStore cacheStore,
    required AppLogger logger,
  }) : _api = api,
       _cacheStore = cacheStore,
       _logger = logger;

  static const _snapshotCacheKey = 'graduate_notices.snapshot.v1';
  static const _categoryPageCacheKeyPrefix = 'graduate_notice.page.v1.';

  final WyuGraduateNoticeApi _api;
  final JsonCacheStore _cacheStore;
  final AppLogger _logger;

  @override
  Future<Result<CampusNoticeSnapshot>> fetchSnapshot({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = await _cacheStore.readMap(_snapshotCacheKey);
      if (cached != null) {
        return Success(
          CampusNoticeSnapshot.fromJson(
            cached,
          ).copyWith(origin: DataOrigin.cache),
        );
      }
    }

    final remote = await _api.fetchSnapshot();
    if (remote case Success<CampusNoticeSnapshot>(data: final snapshot)) {
      await _cacheStore.writeMap(_snapshotCacheKey, snapshot.toJson());
      if (forceRefresh) {
        await _cacheStore.removeByPrefix(_categoryPageCacheKeyPrefix);
      }
      return Success(snapshot);
    }

    final cached = await _cacheStore.readMap(_snapshotCacheKey);
    if (cached != null) {
      _logger.warn('Falling back to cached graduate notices snapshot.');
      return Success(
        CampusNoticeSnapshot.fromJson(
          cached,
        ).copyWith(origin: DataOrigin.cache),
      );
    }

    return FailureResult(remote.failureOrNull!);
  }

  @override
  Future<Result<CampusNoticeCategoryPage>> fetchCategoryPage({
    required CampusNoticeCategory category,
    required Uri pageUri,
    bool forceRefresh = false,
  }) async {
    final pageNumber =
        int.tryParse(
          RegExp(r'(\d+)\.htm$').firstMatch(pageUri.path)?.group(1) ?? '',
        ) ??
        int.tryParse(pageUri.queryParameters['PAGENUM'] ?? '') ??
        1;
    final cacheKey = 'graduate_notice.page.v1.${category.cacheKey}.$pageNumber';

    if (!forceRefresh) {
      final cached = await _cacheStore.readMap(cacheKey);
      if (cached != null) {
        return Success(
          CampusNoticeCategoryPage.fromJson(
            cached,
          ).copyWith(origin: DataOrigin.cache),
        );
      }
    }

    final remote = await _api.fetchCategoryPage(
      category: category,
      pageUri: pageUri,
    );
    if (remote case Success<CampusNoticeCategoryPage>(data: final page)) {
      await _cacheStore.writeMap(cacheKey, page.toJson());
      return Success(page);
    }

    final cached = await _cacheStore.readMap(cacheKey);
    if (cached != null) {
      _logger.warn(
        'Falling back to cached graduate category page: ${category.cacheKey} page=$pageNumber',
      );
      return Success(
        CampusNoticeCategoryPage.fromJson(
          cached,
        ).copyWith(origin: DataOrigin.cache),
      );
    }

    return FailureResult(remote.failureOrNull!);
  }

  @override
  Future<Result<CampusNoticeDetail>> fetchDetail({
    required CampusNoticeItem item,
    bool forceRefresh = false,
  }) async {
    final cacheKey = 'graduate_notice.detail.${item.cacheKey}';
    if (!forceRefresh) {
      final cached = await _cacheStore.readMap(cacheKey);
      if (cached != null) {
        return Success(
          CampusNoticeDetail.fromJson(
            cached,
          ).copyWith(origin: DataOrigin.cache),
        );
      }
    }

    final remote = await _api.fetchDetail(item: item);
    if (remote case Success<CampusNoticeDetail>(data: final detail)) {
      await _cacheStore.writeMap(cacheKey, detail.toJson());
      return Success(detail);
    }

    final cached = await _cacheStore.readMap(cacheKey);
    if (cached != null) {
      _logger.warn(
        'Falling back to cached graduate notice detail: ${item.cacheKey}',
      );
      return Success(
        CampusNoticeDetail.fromJson(cached).copyWith(origin: DataOrigin.cache),
      );
    }

    return FailureResult(remote.failureOrNull!);
  }
}
