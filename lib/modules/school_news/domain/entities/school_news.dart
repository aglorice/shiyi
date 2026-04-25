import '../../../../core/models/data_origin.dart';

class SchoolNewsItem {
  const SchoolNewsItem({
    required this.id,
    required this.title,
    this.summary,
    required this.publishedAt,
    required this.detailUrl,
  });

  final String id;
  final String title;
  final String? summary;
  final DateTime publishedAt;
  final String detailUrl;

  Uri get detailUri => Uri.parse(detailUrl);

  String get cacheKey => id.isNotEmpty ? id : detailUrl;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'summary': summary,
    'publishedAt': publishedAt.toIso8601String(),
    'detailUrl': detailUrl,
  };

  factory SchoolNewsItem.fromJson(Map<String, dynamic> json) {
    return SchoolNewsItem(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      summary: json['summary'] as String?,
      publishedAt: DateTime.parse(json['publishedAt'] as String),
      detailUrl: json['detailUrl'] as String? ?? '',
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SchoolNewsItem &&
        other.id == id &&
        other.detailUrl == detailUrl;
  }

  @override
  int get hashCode => Object.hash(id, detailUrl);
}

class SchoolNewsPageData {
  const SchoolNewsPageData({
    required this.pageUrl,
    required this.currentPage,
    required this.totalPages,
    required this.items,
    this.prevPageUrl,
    this.nextPageUrl,
    required this.fetchedAt,
    required this.origin,
  });

  final String pageUrl;
  final int currentPage;
  final int totalPages;
  final List<SchoolNewsItem> items;
  final String? prevPageUrl;
  final String? nextPageUrl;
  final DateTime fetchedAt;
  final DataOrigin origin;

  bool get hasPrevious =>
      prevPageUrl != null && prevPageUrl!.isNotEmpty && currentPage > 1;

  bool get hasMore =>
      nextPageUrl != null &&
      nextPageUrl!.isNotEmpty &&
      currentPage < totalPages;

  SchoolNewsPageData copyWith({
    String? pageUrl,
    int? currentPage,
    int? totalPages,
    List<SchoolNewsItem>? items,
    String? prevPageUrl,
    String? nextPageUrl,
    DateTime? fetchedAt,
    DataOrigin? origin,
  }) {
    return SchoolNewsPageData(
      pageUrl: pageUrl ?? this.pageUrl,
      currentPage: currentPage ?? this.currentPage,
      totalPages: totalPages ?? this.totalPages,
      items: items ?? this.items,
      prevPageUrl: prevPageUrl ?? this.prevPageUrl,
      nextPageUrl: nextPageUrl ?? this.nextPageUrl,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      origin: origin ?? this.origin,
    );
  }

  Map<String, dynamic> toJson() => {
    'pageUrl': pageUrl,
    'currentPage': currentPage,
    'totalPages': totalPages,
    'items': items.map((item) => item.toJson()).toList(),
    'prevPageUrl': prevPageUrl,
    'nextPageUrl': nextPageUrl,
    'fetchedAt': fetchedAt.toIso8601String(),
    'origin': origin.name,
  };

  factory SchoolNewsPageData.fromJson(Map<String, dynamic> json) {
    return SchoolNewsPageData(
      pageUrl: json['pageUrl'] as String? ?? '',
      currentPage: json['currentPage'] as int? ?? 1,
      totalPages: json['totalPages'] as int? ?? 1,
      items: (json['items'] as List<dynamic>? ?? const [])
          .map((item) => SchoolNewsItem.fromJson(item as Map<String, dynamic>))
          .toList(),
      prevPageUrl: json['prevPageUrl'] as String?,
      nextPageUrl: json['nextPageUrl'] as String?,
      fetchedAt: DateTime.parse(json['fetchedAt'] as String),
      origin: switch (json['origin']) {
        'cache' => DataOrigin.cache,
        _ => DataOrigin.remote,
      },
    );
  }
}

sealed class SchoolNewsContentBlock {
  const SchoolNewsContentBlock();

  Map<String, dynamic> toJson();

  factory SchoolNewsContentBlock.fromJson(Map<String, dynamic> json) {
    return switch (json['type']) {
      'image' => SchoolNewsImageBlock.fromJson(json),
      _ => SchoolNewsTextBlock.fromJson(json),
    };
  }
}

class SchoolNewsTextBlock extends SchoolNewsContentBlock {
  const SchoolNewsTextBlock({required this.text});

  final String text;

  @override
  Map<String, dynamic> toJson() => {'type': 'text', 'text': text};

  factory SchoolNewsTextBlock.fromJson(Map<String, dynamic> json) {
    return SchoolNewsTextBlock(text: json['text'] as String? ?? '');
  }
}

class SchoolNewsImageBlock extends SchoolNewsContentBlock {
  const SchoolNewsImageBlock({required this.url, this.alt});

  final String url;
  final String? alt;

  @override
  Map<String, dynamic> toJson() => {'type': 'image', 'url': url, 'alt': alt};

  factory SchoolNewsImageBlock.fromJson(Map<String, dynamic> json) {
    return SchoolNewsImageBlock(
      url: json['url'] as String? ?? '',
      alt: json['alt'] as String?,
    );
  }
}

class SchoolNewsDetail {
  const SchoolNewsDetail({
    required this.item,
    required this.title,
    required this.metaLines,
    this.source,
    required this.contentBlocks,
    required this.fetchedAt,
    required this.origin,
  });

  final SchoolNewsItem item;
  final String title;
  final List<String> metaLines;
  final String? source;
  final List<SchoolNewsContentBlock> contentBlocks;
  final DateTime fetchedAt;
  final DataOrigin origin;

  SchoolNewsDetail copyWith({
    SchoolNewsItem? item,
    String? title,
    List<String>? metaLines,
    String? source,
    List<SchoolNewsContentBlock>? contentBlocks,
    DateTime? fetchedAt,
    DataOrigin? origin,
  }) {
    return SchoolNewsDetail(
      item: item ?? this.item,
      title: title ?? this.title,
      metaLines: metaLines ?? this.metaLines,
      source: source ?? this.source,
      contentBlocks: contentBlocks ?? this.contentBlocks,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      origin: origin ?? this.origin,
    );
  }

  Map<String, dynamic> toJson() => {
    'item': item.toJson(),
    'title': title,
    'metaLines': metaLines,
    'source': source,
    'contentBlocks': contentBlocks.map((block) => block.toJson()).toList(),
    'fetchedAt': fetchedAt.toIso8601String(),
    'origin': origin.name,
  };

  factory SchoolNewsDetail.fromJson(Map<String, dynamic> json) {
    return SchoolNewsDetail(
      item: SchoolNewsItem.fromJson(json['item'] as Map<String, dynamic>),
      title: json['title'] as String? ?? '',
      metaLines: (json['metaLines'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList(),
      source: json['source'] as String?,
      contentBlocks: (json['contentBlocks'] as List<dynamic>? ?? const [])
          .map(
            (item) =>
                SchoolNewsContentBlock.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      fetchedAt: DateTime.parse(json['fetchedAt'] as String),
      origin: switch (json['origin']) {
        'cache' => DataOrigin.cache,
        _ => DataOrigin.remote,
      },
    );
  }
}
