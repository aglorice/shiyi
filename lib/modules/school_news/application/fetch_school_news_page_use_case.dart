import '../../../../core/result/result.dart';
import '../domain/entities/school_news.dart';
import '../domain/repositories/school_news_repository.dart';

class FetchSchoolNewsPageUseCase {
  const FetchSchoolNewsPageUseCase(this._repository);

  final SchoolNewsRepository _repository;

  Future<Result<SchoolNewsPageData>> call({
    Uri? pageUri,
    bool forceRefresh = false,
  }) {
    return _repository.fetchPage(pageUri: pageUri, forceRefresh: forceRefresh);
  }
}
