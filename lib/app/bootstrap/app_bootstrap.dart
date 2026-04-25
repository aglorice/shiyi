import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/data_origin.dart';
import '../../core/result/result.dart';
import '../../integrations/school_portal/school_portal_gateway.dart';
import '../../modules/auth/data/credential_vault.dart';
import '../../modules/school_news/domain/entities/school_news.dart';
import '../../modules/school_news/domain/repositories/school_news_repository.dart';
import '../di/app_providers.dart';

class AppBootstrap {
  const AppBootstrap._(this.overrides);

  final List<Object> overrides;

  static Future<AppBootstrap> initialize() async {
    await initializeDateFormatting('zh_CN');
    final preferences = await SharedPreferences.getInstance();

    return AppBootstrap._([
      sharedPreferencesProvider.overrideWithValue(preferences),
    ]);
  }

  static Future<AppBootstrap> testing() async {
    await initializeDateFormatting('zh_CN');
    final preferences = await SharedPreferences.getInstance();

    return AppBootstrap._([
      sharedPreferencesProvider.overrideWithValue(preferences),
      credentialVaultProvider.overrideWithValue(InMemoryCredentialVault()),
      schoolPortalGatewayProvider.overrideWithValue(
        TestingSchoolPortalGateway(),
      ),
      schoolNewsRepositoryProvider.overrideWithValue(
        TestingSchoolNewsRepository(),
      ),
    ]);
  }
}

class TestingSchoolNewsRepository implements SchoolNewsRepository {
  @override
  Future<Result<SchoolNewsPageData>> fetchPage({
    Uri? pageUri,
    bool forceRefresh = false,
  }) async {
    return Success(
      SchoolNewsPageData(
        pageUrl: 'https://www.wyu.edu.cn/index/xxyw.htm',
        currentPage: 1,
        totalPages: 1,
        items: [
          SchoolNewsItem(
            id: 'testing-school-news',
            title: '测试学校要闻',
            summary: '用于测试环境的稳定学校要闻数据。',
            publishedAt: DateTime(2026, 1, 1),
            detailUrl: 'https://www.wyu.edu.cn/index/xxyw.htm',
          ),
        ],
        fetchedAt: DateTime(2026, 1, 1),
        origin: DataOrigin.cache,
      ),
    );
  }

  @override
  Future<Result<SchoolNewsDetail>> fetchDetail({
    required SchoolNewsItem item,
    bool forceRefresh = false,
  }) async {
    return Success(
      SchoolNewsDetail(
        item: item,
        title: item.title,
        metaLines: const ['发布时间：2026-01-01', '发布单位：测试环境'],
        source: '测试环境',
        contentBlocks: const [SchoolNewsTextBlock(text: '用于测试环境的稳定学校要闻正文。')],
        fetchedAt: DateTime(2026, 1, 1),
        origin: DataOrigin.cache,
      ),
    );
  }
}
