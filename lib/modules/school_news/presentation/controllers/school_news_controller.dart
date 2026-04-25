import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di/app_providers.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/school_news.dart';
import '../models/school_news_feed_state.dart';

final schoolNewsControllerProvider =
    AsyncNotifierProvider<SchoolNewsController, SchoolNewsFeedState>(
      SchoolNewsController.new,
      retry: (_, __) => null,
    );

class SchoolNewsController extends AsyncNotifier<SchoolNewsFeedState> {
  @override
  Future<SchoolNewsFeedState> build() async {
    return _loadFirstPage(forceRefresh: false);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _loadFirstPage(forceRefresh: true));
  }

  Future<void> loadNextPage() async {
    final currentState = state.asData?.value;
    if (currentState == null ||
        !currentState.hasMore ||
        currentState.isLoadingMore ||
        currentState.nextPageUrl == null ||
        currentState.nextPageUrl!.isEmpty) {
      return;
    }

    state = AsyncData(
      currentState.copyWith(
        isLoadingMore: true,
        clearLoadMoreErrorMessage: true,
      ),
    );

    final result = await ref.read(fetchSchoolNewsPageUseCaseProvider)(
      pageUri: Uri.parse(currentState.nextPageUrl!),
    );

    if (result case FailureResult<SchoolNewsPageData>(failure: final failure)) {
      final latest = state.asData?.value ?? currentState;
      state = AsyncData(
        latest.copyWith(
          isLoadingMore: false,
          loadMoreErrorMessage: failure.message,
        ),
      );
      return;
    }

    final page = result.requireValue();
    final latest = state.asData?.value ?? currentState;
    state = AsyncData(
      latest.copyWith(
        page: page,
        items: _mergeItems(latest.items, page.items),
        isLoadingMore: false,
        clearLoadMoreErrorMessage: true,
      ),
    );
  }

  Future<SchoolNewsFeedState> _loadFirstPage({
    required bool forceRefresh,
  }) async {
    final result = await ref.read(fetchSchoolNewsPageUseCaseProvider)(
      forceRefresh: forceRefresh,
    );
    final page = result.requireValue();
    return SchoolNewsFeedState(page: page, items: page.items);
  }

  List<SchoolNewsItem> _mergeItems(
    List<SchoolNewsItem> current,
    List<SchoolNewsItem> next,
  ) {
    final seen = current.map((item) => item.cacheKey).toSet();
    final merged = [...current];
    for (final item in next) {
      if (seen.add(item.cacheKey)) {
        merged.add(item);
      }
    }
    return merged;
  }
}
