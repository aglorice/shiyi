import '../../../../core/result/result.dart';
import '../entities/school_news.dart';

abstract class SchoolNewsRepository {
  Future<Result<SchoolNewsPageData>> fetchPage({
    Uri? pageUri,
    bool forceRefresh = false,
  });

  Future<Result<SchoolNewsDetail>> fetchDetail({
    required SchoolNewsItem item,
    bool forceRefresh = false,
  });
}
