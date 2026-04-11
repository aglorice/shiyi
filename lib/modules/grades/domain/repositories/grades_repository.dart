import '../../../../core/result/result.dart';
import '../../../auth/domain/entities/app_session.dart';
import '../entities/grades_snapshot.dart';

abstract class GradesRepository {
  Future<Result<GradesSnapshot>> fetchGrades({
    required AppSession session,
    String? termId,
    bool forceRefresh = false,
  });
}
