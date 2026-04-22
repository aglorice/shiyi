import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di/app_providers.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/campus_notice.dart';
import '../models/notices_view_state.dart';

final graduateNoticesControllerProvider =
    AsyncNotifierProvider<GraduateNoticesController, NoticesState>(
      GraduateNoticesController.new,
    );

class GraduateNoticesController extends AsyncNotifier<NoticesState> {
  @override
  Future<NoticesState> build() async {
    return _load(forceRefresh: false);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _load(forceRefresh: true));
  }

  Future<void> ensureCategoryLoaded(CampusNoticeCategory category) async {
    final currentState = state.asData?.value;
    if (currentState == null) {
      return;
    }

    final currentFeed = currentState.feedFor(category);
    if (currentFeed.isHydrated ||
        currentFeed.isInitialLoading ||
        currentFeed.listPageUrl == null ||
        currentFeed.listPageUrl!.isEmpty) {
      return;
    }

    _updateFeed(
      category,
      currentFeed.copyWith(isInitialLoading: true, clearErrorMessage: true),
    );

    final result = await ref.read(
      fetchGraduateNoticeCategoryPageUseCaseProvider,
    )(category: category, pageUri: Uri.parse(currentFeed.listPageUrl!));

    if (result case FailureResult<CampusNoticeCategoryPage>(
      failure: final failure,
    )) {
      final latestFeed = state.asData?.value.feedFor(category) ?? currentFeed;
      _updateFeed(
        category,
        latestFeed.copyWith(
          isHydrated: true,
          isInitialLoading: false,
          errorMessage: failure.message,
        ),
      );
      return;
    }

    final page = result.requireValue();
    final latestFeed = state.asData?.value.feedFor(category) ?? currentFeed;
    _updateFeed(
      category,
      latestFeed.copyWith(
        items: page.items,
        displayLabel: page.categoryLabel ?? latestFeed.displayLabel,
        prevPageUrl: page.prevPageUrl,
        currentPage: page.currentPage,
        totalPages: page.totalPages,
        nextPageUrl: page.nextPageUrl,
        clearNextPageUrl: page.nextPageUrl == null,
        isHydrated: true,
        isInitialLoading: false,
        clearErrorMessage: true,
        clearLoadMoreErrorMessage: true,
      ),
    );
  }

  Future<void> loadNextPage(CampusNoticeCategory category) async {
    final currentState = state.asData?.value;
    if (currentState == null) {
      return;
    }

    final currentFeed = currentState.feedFor(category);
    if (!currentFeed.hasMore ||
        currentFeed.isLoadingMore ||
        currentFeed.nextPageUrl == null ||
        currentFeed.nextPageUrl!.isEmpty) {
      return;
    }

    await _loadCategoryPage(
      category,
      pageUrl: currentFeed.nextPageUrl!,
      currentFeed: currentFeed,
    );
  }

  Future<void> _loadCategoryPage(
    CampusNoticeCategory category, {
    required String pageUrl,
    required NoticeFeedState currentFeed,
  }) async {
    _updateFeed(
      category,
      currentFeed.copyWith(
        isLoadingMore: true,
        clearLoadMoreErrorMessage: true,
      ),
    );

    final result = await ref.read(
      fetchGraduateNoticeCategoryPageUseCaseProvider,
    )(category: category, pageUri: Uri.parse(pageUrl));

    if (result case FailureResult<CampusNoticeCategoryPage>(
      failure: final failure,
    )) {
      final latestFeed = state.asData?.value.feedFor(category) ?? currentFeed;
      _updateFeed(
        category,
        latestFeed.copyWith(
          isLoadingMore: false,
          loadMoreErrorMessage: failure.message,
        ),
      );
      return;
    }

    final page = result.requireValue();
    final latestFeed = state.asData?.value.feedFor(category) ?? currentFeed;
    _updateFeed(
      category,
      latestFeed.copyWith(
        items: [...latestFeed.items, ...page.items],
        displayLabel: page.categoryLabel ?? latestFeed.displayLabel,
        prevPageUrl: page.prevPageUrl,
        currentPage: page.currentPage,
        totalPages: page.totalPages,
        nextPageUrl: page.nextPageUrl,
        clearNextPageUrl: page.nextPageUrl == null,
        isHydrated: true,
        isLoadingMore: false,
        clearLoadMoreErrorMessage: true,
      ),
    );
  }

  Future<NoticesState> _load({required bool forceRefresh}) async {
    final result = await ref.read(fetchGraduateNoticesUseCaseProvider)(
      forceRefresh: forceRefresh,
    );
    final snapshot = result.requireValue();
    return NoticesState(snapshot: snapshot, feeds: _seedFeeds(snapshot));
  }

  Map<CampusNoticeCategory, NoticeFeedState> _seedFeeds(
    CampusNoticeSnapshot snapshot,
  ) {
    final feeds = <CampusNoticeCategory, NoticeFeedState>{};
    for (final category in CampusNoticeCategoryX.forBoard(
      NoticeBoardSource.graduate,
    )) {
      final section = snapshot.sectionFor(category);
      feeds[category] = NoticeFeedState(
        category: category,
        items: section.items,
        displayLabel: section.displayLabel,
        listPageUrl: section.listPageUrl,
      );
    }
    return feeds;
  }

  void _updateFeed(CampusNoticeCategory category, NoticeFeedState nextFeed) {
    final currentState = state.asData?.value;
    if (currentState == null) {
      return;
    }

    state = AsyncData(
      currentState.copyWith(feeds: {...currentState.feeds, category: nextFeed}),
    );
  }
}
