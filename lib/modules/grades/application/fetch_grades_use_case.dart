import '../../../core/result/result.dart';
import '../../auth/domain/entities/app_session.dart';
import '../domain/entities/grades_snapshot.dart';
import '../domain/repositories/grades_repository.dart';

class FetchGradesUseCase {
  const FetchGradesUseCase(this._repository);

  final GradesRepository _repository;

  Future<Result<GradesSnapshot>> call({
    required AppSession session,
    String? termId,
    bool forceRefresh = false,
  }) {
    return _repository.fetchGrades(
      session: session,
      termId: termId,
      forceRefresh: forceRefresh,
    );
  }
}
