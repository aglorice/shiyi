import '../../domain/entities/school_news.dart';

class SchoolNewsFeedState {
  const SchoolNewsFeedState({
    required this.page,
    required this.items,
    this.isLoadingMore = false,
    this.loadMoreErrorMessage,
  });

  final SchoolNewsPageData page;
  final List<SchoolNewsItem> items;
  final bool isLoadingMore;
  final String? loadMoreErrorMessage;

  int get currentPage => page.currentPage;
  int get totalPages => page.totalPages;
  bool get hasMore => page.hasMore;
  String? get nextPageUrl => page.nextPageUrl;

  SchoolNewsFeedState copyWith({
    SchoolNewsPageData? page,
    List<SchoolNewsItem>? items,
    bool? isLoadingMore,
    String? loadMoreErrorMessage,
    bool clearLoadMoreErrorMessage = false,
  }) {
    return SchoolNewsFeedState(
      page: page ?? this.page,
      items: items ?? this.items,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      loadMoreErrorMessage: clearLoadMoreErrorMessage
          ? null
          : loadMoreErrorMessage ?? this.loadMoreErrorMessage,
    );
  }
}
