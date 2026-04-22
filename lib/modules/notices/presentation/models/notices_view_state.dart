import '../../domain/entities/campus_notice.dart';

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
    return category.defaultLabel;
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
