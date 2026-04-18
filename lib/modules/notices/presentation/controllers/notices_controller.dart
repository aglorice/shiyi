import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di/app_providers.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../../auth/domain/entities/app_session.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../domain/entities/campus_notice.dart';

const _maxCategoryRetries = 1;

final noticesControllerProvider =
    AsyncNotifierProvider<NoticesController, NoticesState>(
      NoticesController.new,
    );

class NoticeFeedState {
  const NoticeFeedState({
    required this.category,
    required this.items,
    this.displayLabel,
    this.listPageUrl,
    this.prevPageUrl,
    this.currentPage = 0,
    this.totalPages = 1,
    this.nextPageUrl,
    this.isHydrated = false,
    this.isInitialLoading = false,
    this.isLoadingMore = false,
    this.errorMessage,
    this.loadMoreErrorMessage,
  });

  final CampusNoticeCategory category;
  final List<CampusNoticeItem> items;
  final String? displayLabel;
  final String? listPageUrl;
  final String? prevPageUrl;
  final int currentPage;
  final int totalPages;
  final String? nextPageUrl;
  final bool isHydrated;
  final bool isInitialLoading;
  final bool isLoadingMore;
  final String? errorMessage;
  final String? loadMoreErrorMessage;

  bool get hasPrevious =>
      prevPageUrl != null && prevPageUrl!.isNotEmpty && currentPage > 1;

  bool get hasMore =>
      nextPageUrl != null &&
      nextPageUrl!.isNotEmpty &&
      currentPage < totalPages;

  NoticeFeedState copyWith({
    List<CampusNoticeItem>? items,
    String? displayLabel,
    String? listPageUrl,
    String? prevPageUrl,
    int? currentPage,
    int? totalPages,
    String? nextPageUrl,
    bool clearNextPageUrl = false,
    bool? isHydrated,
    bool? isInitialLoading,
    bool? isLoadingMore,
    String? errorMessage,
    bool clearErrorMessage = false,
    String? loadMoreErrorMessage,
    bool clearLoadMoreErrorMessage = false,
  }) {
    return NoticeFeedState(
      category: category,
      items: items ?? this.items,
      displayLabel: displayLabel ?? this.displayLabel,
      listPageUrl: listPageUrl ?? this.listPageUrl,
      prevPageUrl: prevPageUrl ?? this.prevPageUrl,
      currentPage: currentPage ?? this.currentPage,
      totalPages: totalPages ?? this.totalPages,
      nextPageUrl: clearNextPageUrl ? null : nextPageUrl ?? this.nextPageUrl,
      isHydrated: isHydrated ?? this.isHydrated,
      isInitialLoading: isInitialLoading ?? this.isInitialLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      errorMessage: clearErrorMessage
          ? null
          : errorMessage ?? this.errorMessage,
      loadMoreErrorMessage: clearLoadMoreErrorMessage
          ? null
          : loadMoreErrorMessage ?? this.loadMoreErrorMessage,
    );
  }
}

class NoticesState {
  const NoticesState({required this.snapshot, required this.feeds});

  final CampusNoticeSnapshot snapshot;
  final Map<CampusNoticeCategory, NoticeFeedState> feeds;

  NoticeFeedState feedFor(CampusNoticeCategory category) {
    return feeds[category] ??
        NoticeFeedState(
          category: category,
          items: snapshot.sectionFor(category).items,
          displayLabel: snapshot.sectionFor(category).displayLabel,
          listPageUrl: snapshot.sectionFor(category).listPageUrl,
        );
  }

  String labelFor(CampusNoticeCategory category) {
    final label =
        feeds[category]?.displayLabel?.trim() ??
        snapshot.sectionFor(category).displayLabel?.trim();
    if (label != null && label.isNotEmpty) {
      return label;
    }
    return category.name;
  }

  NoticesState copyWith({
    CampusNoticeSnapshot? snapshot,
    Map<CampusNoticeCategory, NoticeFeedState>? feeds,
  }) {
    return NoticesState(
      snapshot: snapshot ?? this.snapshot,
      feeds: feeds ?? this.feeds,
    );
  }
}

class NoticesController extends AsyncNotifier<NoticesState> {
  @override
  Future<NoticesState> build() async {
    return _load(forceRefresh: false);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _load(forceRefresh: true));
  }

  Future<void> ensureCategoryLoaded(
    CampusNoticeCategory category, {
    int retryCount = 0,
  }) async {
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

    var session = await _readSession();
    final pageUri = Uri.parse(currentFeed.listPageUrl!);
    var result = await ref.read(fetchNoticeCategoryPageUseCaseProvider)(
      session: session,
      category: category,
      pageUri: pageUri,
    );

    if (result case FailureResult<CampusNoticeCategoryPage>(
      failure: final failure,
    )) {
      if (failure is SessionExpiredFailure &&
          retryCount < _maxCategoryRetries) {
        final refreshed = await ref
            .read(authControllerProvider.notifier)
            .relogin();
        if (refreshed) {
          session = await _readSession();
          result = await ref.read(fetchNoticeCategoryPageUseCaseProvider)(
            session: session,
            category: category,
            pageUri: pageUri,
          );
          if (result case Success<CampusNoticeCategoryPage>()) {
            final page = result.requireValue();
            final latestFeed =
                state.asData?.value.feedFor(category) ?? currentFeed;
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
            return;
          }
        }
      }

      final latestFeed = state.asData?.value.feedFor(category) ?? currentFeed;
      final effectiveFailure = result is FailureResult<CampusNoticeCategoryPage>
          ? result.failure
          : failure;
      _updateFeed(
        category,
        latestFeed.copyWith(
          isHydrated: true,
          isInitialLoading: false,
          errorMessage: effectiveFailure.message,
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

  Future<void> loadPreviousPage(CampusNoticeCategory category) async {
    final currentState = state.asData?.value;
    if (currentState == null) {
      return;
    }

    final currentFeed = currentState.feedFor(category);
    if (!currentFeed.hasPrevious ||
        currentFeed.isLoadingMore ||
        currentFeed.prevPageUrl == null ||
        currentFeed.prevPageUrl!.isEmpty) {
      return;
    }

    await _loadCategoryPage(
      category,
      pageUrl: currentFeed.prevPageUrl!,
      currentFeed: currentFeed,
    );
  }

  Future<void> _loadCategoryPage(
    CampusNoticeCategory category, {
    required String pageUrl,
    required NoticeFeedState currentFeed,
  }) async {
    final currentState = state.asData?.value;
    if (currentState == null) {
      return;
    }

    _updateFeed(
      category,
      currentFeed.copyWith(
        isLoadingMore: true,
        clearLoadMoreErrorMessage: true,
      ),
    );

    final session = await _readSession();
    final pageUri = Uri.parse(pageUrl);
    final result = await ref.read(fetchNoticeCategoryPageUseCaseProvider)(
      session: session,
      category: category,
      pageUri: pageUri,
    );

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
    final session = await _readSession();
    final result = await ref.read(fetchNoticesUseCaseProvider)(
      session: session,
      forceRefresh: forceRefresh,
    );
    final snapshot = result.requireValue();
    return NoticesState(snapshot: snapshot, feeds: _seedFeeds(snapshot));
  }

  Future<AppSession> _readSession() async {
    final authState = await ref.watch(authControllerProvider.future);
    final session = authState.session;
    if (session == null) {
      throw const AuthenticationFailure('当前未登录，无法加载通知。');
    }
    return session;
  }

  Map<CampusNoticeCategory, NoticeFeedState> _seedFeeds(
    CampusNoticeSnapshot snapshot,
  ) {
    final feeds = <CampusNoticeCategory, NoticeFeedState>{};
    for (final category in CampusNoticeCategory.values) {
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
    final nextFeeds = <CampusNoticeCategory, NoticeFeedState>{
      ...currentState.feeds,
      category: nextFeed,
    };
    state = AsyncData(currentState.copyWith(feeds: nextFeeds));
  }
}
