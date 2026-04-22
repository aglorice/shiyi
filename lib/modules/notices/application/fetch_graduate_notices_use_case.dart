import '../../../../core/result/result.dart';
import '../domain/entities/campus_notice.dart';
import '../domain/repositories/graduate_notices_repository.dart';

class FetchGraduateNoticesUseCase {
  const FetchGraduateNoticesUseCase(this._repository);

  final GraduateNoticesRepository _repository;

  Future<Result<CampusNoticeSnapshot>> call({bool forceRefresh = false}) {
    return _repository.fetchSnapshot(forceRefresh: forceRefresh);
  }
}
