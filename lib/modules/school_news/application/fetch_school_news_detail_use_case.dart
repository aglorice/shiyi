import '../../../../core/result/result.dart';
import '../domain/entities/school_news.dart';
import '../domain/repositories/school_news_repository.dart';

class FetchSchoolNewsDetailUseCase {
  const FetchSchoolNewsDetailUseCase(this._repository);

  final SchoolNewsRepository _repository;

  Future<Result<SchoolNewsDetail>> call({
    required SchoolNewsItem item,
    bool forceRefresh = false,
  }) {
    return _repository.fetchDetail(item: item, forceRefresh: forceRefresh);
  }
}
