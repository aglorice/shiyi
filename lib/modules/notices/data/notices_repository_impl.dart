import '../../../core/logging/app_logger.dart';
import '../../../core/models/data_origin.dart';
import '../../../core/result/result.dart';
import '../../../core/storage/json_cache_store.dart';
import '../../../integrations/campus_notices/wyu_notice_api.dart';
import '../../auth/domain/entities/app_session.dart';
import '../domain/entities/campus_notice.dart';
import '../domain/repositories/notices_repository.dart';

class NoticesRepositoryImpl implements NoticesRepository {
  const NoticesRepositoryImpl({
    required WyuNoticeApi api,
    required JsonCacheStore cacheStore,
    required AppLogger logger,
  }) : _api = api,
       _cacheStore = cacheStore,
       _logger = logger;

  static const _snapshotCacheKey = 'campus_notices.snapshot.v4';
  static const _categoryPageCacheKeyPrefix = 'campus_notice.page.v4.';

  final WyuNoticeApi _api;
  final JsonCacheStore _cacheStore;
  final AppLogger _logger;

  @override
  Future<Result<CampusNoticeSnapshot>> fetchSnapshot({
    required AppSession session,
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

    final remote = await _api.fetchSnapshot(session: session);
    if (remote case Success<CampusNoticeSnapshot>(data: final snapshot)) {
      await _cacheStore.writeMap(_snapshotCacheKey, snapshot.toJson());
      if (forceRefresh) {
        await _cacheStore.removeByPrefix(_categoryPageCacheKeyPrefix);
      }
      return Success(snapshot);
    }

    final cached = await _cacheStore.readMap(_snapshotCacheKey);
    if (cached != null) {
      _logger.warn('Falling back to cached campus notices snapshot.');
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
    required AppSession session,
    required CampusNoticeCategory category,
    required Uri pageUri,
    bool forceRefresh = false,
  }) async {
    final pageNumber =
        int.tryParse(pageUri.queryParameters['PAGENUM'] ?? '') ?? 1;
    final cacheKey = 'campus_notice.page.v4.${category.cacheKey}.$pageNumber';
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
      session: session,
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
        'Falling back to cached category page: ${category.cacheKey} page=$pageNumber',
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
    required AppSession session,
    required CampusNoticeItem item,
    bool forceRefresh = false,
  }) async {
    final cacheKey = 'campus_notice.detail.${item.cacheKey}';
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

    final remote = await _api.fetchDetail(session: session, item: item);
    if (remote case Success<CampusNoticeDetail>(data: final detail)) {
      await _cacheStore.writeMap(cacheKey, detail.toJson());
      return Success(detail);
    }

    final cached = await _cacheStore.readMap(cacheKey);
    if (cached != null) {
      _logger.warn(
        'Falling back to cached campus notice detail: ${item.cacheKey}',
      );
      return Success(
        CampusNoticeDetail.fromJson(cached).copyWith(origin: DataOrigin.cache),
      );
    }

    return FailureResult(remote.failureOrNull!);
  }
}
