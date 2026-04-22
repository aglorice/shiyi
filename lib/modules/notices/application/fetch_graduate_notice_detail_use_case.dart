import '../../../../core/result/result.dart';
import '../domain/entities/campus_notice.dart';
import '../domain/repositories/graduate_notices_repository.dart';

class FetchGraduateNoticeDetailUseCase {
  const FetchGraduateNoticeDetailUseCase(this._repository);

  final GraduateNoticesRepository _repository;

  Future<Result<CampusNoticeDetail>> call({
    required CampusNoticeItem item,
    bool forceRefresh = false,
  }) {
    return _repository.fetchDetail(item: item, forceRefresh: forceRefresh);
  }
}
