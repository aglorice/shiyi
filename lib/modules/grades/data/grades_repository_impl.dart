import '../../../core/logging/app_logger.dart';
import '../../../core/models/data_origin.dart';
import '../../../core/result/result.dart';
import '../../../core/storage/json_cache_store.dart';
import '../../../integrations/school_portal/school_portal_gateway.dart';
import '../../auth/domain/entities/app_session.dart';
import '../domain/entities/grades_snapshot.dart';
import '../domain/repositories/grades_repository.dart';

class GradesRepositoryImpl implements GradesRepository {
  const GradesRepositoryImpl({
    required SchoolPortalGateway gateway,
    required JsonCacheStore cacheStore,
    required AppLogger logger,
  }) : _gateway = gateway,
       _cacheStore = cacheStore,
       _logger = logger;

  static const _cacheKey = 'grades.snapshot.current';

  final SchoolPortalGateway _gateway;
  final JsonCacheStore _cacheStore;
  final AppLogger _logger;

  @override
  Future<Result<GradesSnapshot>> fetchGrades({
    required AppSession session,
    String? termId,
    bool forceRefresh = false,
  }) async {
    final cacheKey = switch (termId) {
      null => _cacheKey,
      '' => '$_cacheKey.all',
      _ => '$_cacheKey.$termId',
    };
    final remote = await _gateway.fetchGrades(session, termId: termId);
    if (remote case Success<GradesSnapshot>(data: final snapshot)) {
      await _cacheStore.writeMap(cacheKey, snapshot.toJson());
      if (termId == null && snapshot.selectedTerm != null) {
        await _cacheStore.writeMap(
          '$_cacheKey.${snapshot.selectedTerm!.id}',
          snapshot.toJson(),
        );
      }
      return Success(snapshot);
    }

    final cached = await _cacheStore.readMap(cacheKey);
    if (cached != null) {
      _logger.warn('Falling back to cached grades data.');
      return Success(
        GradesSnapshot.fromJson(cached).copyWith(origin: DataOrigin.cache),
      );
    }

    return FailureResult(remote.failureOrNull!);
  }
}
