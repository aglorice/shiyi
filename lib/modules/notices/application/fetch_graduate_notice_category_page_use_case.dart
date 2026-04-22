import '../../../../core/result/result.dart';
import '../domain/entities/campus_notice.dart';
import '../domain/repositories/graduate_notices_repository.dart';

class FetchGraduateNoticeCategoryPageUseCase {
  const FetchGraduateNoticeCategoryPageUseCase(this._repository);

  final GraduateNoticesRepository _repository;

  Future<Result<CampusNoticeCategoryPage>> call({
    required CampusNoticeCategory category,
    required Uri pageUri,
    bool forceRefresh = false,
  }) {
    return _repository.fetchCategoryPage(
      category: category,
      pageUri: pageUri,
      forceRefresh: forceRefresh,
    );
  }
}
