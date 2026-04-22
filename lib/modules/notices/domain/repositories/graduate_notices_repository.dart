import '../../../../core/result/result.dart';
import '../entities/campus_notice.dart';

abstract class GraduateNoticesRepository {
  Future<Result<CampusNoticeSnapshot>> fetchSnapshot({
    bool forceRefresh = false,
  });

  Future<Result<CampusNoticeCategoryPage>> fetchCategoryPage({
    required CampusNoticeCategory category,
    required Uri pageUri,
    bool forceRefresh = false,
  });

  Future<Result<CampusNoticeDetail>> fetchDetail({
    required CampusNoticeItem item,
    bool forceRefresh = false,
  });
}
