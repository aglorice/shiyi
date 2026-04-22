import '../../../../core/models/data_origin.dart';

enum NoticeBoardSource { campus, graduate }

extension NoticeBoardSourceX on NoticeBoardSource {
  String get cacheKey => switch (this) {
    NoticeBoardSource.campus => 'campus',
    NoticeBoardSource.graduate => 'graduate',
  };

  String get label => switch (this) {
    NoticeBoardSource.campus => '校级通知',
    NoticeBoardSource.graduate => '研究生通知',
  };
}

enum CampusNoticeCategory {
  campusNotice,
  campusNewsletter,
  publicAnnouncement,
  lectureReport,
  weeklySchedule,
  graduateNoticeAnnouncement,
  graduateDepartmentNews,
  graduateAdmissions,
  graduateTheoryStudy,
  graduateEducationBriefing,
}

extension CampusNoticeCategoryX on CampusNoticeCategory {
  String get cacheKey => switch (this) {
    CampusNoticeCategory.campusNotice => 'campus_notice',
    CampusNoticeCategory.campusNewsletter => 'campus_newsletter',
    CampusNoticeCategory.publicAnnouncement => 'public_announcement',
    CampusNoticeCategory.lectureReport => 'lecture_report',
    CampusNoticeCategory.weeklySchedule => 'weekly_schedule',
    CampusNoticeCategory.graduateNoticeAnnouncement =>
      'graduate_notice_announcement',
    CampusNoticeCategory.graduateDepartmentNews => 'graduate_department_news',
    CampusNoticeCategory.graduateAdmissions => 'graduate_admissions',
    CampusNoticeCategory.graduateTheoryStudy => 'graduate_theory_study',
    CampusNoticeCategory.graduateEducationBriefing =>
      'graduate_education_briefing',
  };

  NoticeBoardSource get board => switch (this) {
    CampusNoticeCategory.campusNotice ||
    CampusNoticeCategory.campusNewsletter ||
    CampusNoticeCategory.publicAnnouncement ||
    CampusNoticeCategory.lectureReport ||
    CampusNoticeCategory.weeklySchedule => NoticeBoardSource.campus,
    CampusNoticeCategory.graduateNoticeAnnouncement ||
    CampusNoticeCategory.graduateDepartmentNews ||
    CampusNoticeCategory.graduateAdmissions ||
    CampusNoticeCategory.graduateTheoryStudy ||
    CampusNoticeCategory.graduateEducationBriefing =>
      NoticeBoardSource.graduate,
  };

  String get defaultLabel => switch (this) {
    CampusNoticeCategory.campusNotice => '校内通知',
    CampusNoticeCategory.campusNewsletter => '校园快讯',
    CampusNoticeCategory.publicAnnouncement => '公示公告',
    CampusNoticeCategory.lectureReport => '讲座报告',
    CampusNoticeCategory.weeklySchedule => '校历周程',
    CampusNoticeCategory.graduateNoticeAnnouncement => '通知公告',
    CampusNoticeCategory.graduateDepartmentNews => '部门新闻',
    CampusNoticeCategory.graduateAdmissions => '研究生招生信息',
    CampusNoticeCategory.graduateTheoryStudy => '理论学习',
    CampusNoticeCategory.graduateEducationBriefing => '研究生教育工作简报',
  };

  static CampusNoticeCategory fromName(String value) {
    return CampusNoticeCategory.values.firstWhere(
      (item) => item.name == value,
      orElse: () => CampusNoticeCategory.campusNotice,
    );
  }

  static List<CampusNoticeCategory> forBoard(NoticeBoardSource board) {
    return CampusNoticeCategory.values
        .where((item) => item.board == board)
        .toList(growable: false);
  }
}

class CampusNoticeItem {
  const CampusNoticeItem({
    required this.category,
    required this.newsId,
    required this.treeId,
    required this.title,
    this.categoryLabel,
    this.summary,
    required this.publishedAt,
    required this.detailUrl,
  });

  final CampusNoticeCategory category;
  final String newsId;
  final String treeId;
  final String title;
  final String? categoryLabel;
  final String? summary;
  final DateTime publishedAt;
  final String detailUrl;

  Uri get detailUri => Uri.parse(detailUrl);

  String get cacheKey => '${category.cacheKey}.$treeId.$newsId';

  Map<String, dynamic> toJson() => {
    'category': category.name,
    'newsId': newsId,
    'treeId': treeId,
    'title': title,
    'categoryLabel': categoryLabel,
    'summary': summary,
    'publishedAt': publishedAt.toIso8601String(),
    'detailUrl': detailUrl,
  };

  factory CampusNoticeItem.fromJson(Map<String, dynamic> json) {
    return CampusNoticeItem(
      category: CampusNoticeCategoryX.fromName(
        json['category'] as String? ?? CampusNoticeCategory.campusNotice.name,
      ),
      newsId: json['newsId'] as String? ?? '',
      treeId: json['treeId'] as String? ?? '',
      title: json['title'] as String? ?? '',
      categoryLabel: json['categoryLabel'] as String?,
      summary: json['summary'] as String?,
      publishedAt: DateTime.parse(json['publishedAt'] as String),
      detailUrl: json['detailUrl'] as String? ?? '',
    );
  }

  @override
  bool operator ==(Object other) {
    return other is CampusNoticeItem &&
        other.category == category &&
        other.newsId == newsId &&
        other.treeId == treeId;
  }

  @override
  int get hashCode => Object.hash(category, newsId, treeId);
}

class CampusNoticeSection {
  const CampusNoticeSection({
    required this.category,
    required this.items,
    this.displayLabel,
    this.listPageUrl,
  });

  final CampusNoticeCategory category;
  final List<CampusNoticeItem> items;
  final String? displayLabel;
  final String? listPageUrl;

  Uri? get listPageUri => switch (listPageUrl) {
    final String value when value.isNotEmpty => Uri.parse(value),
    _ => null,
  };

  Map<String, dynamic> toJson() => {
    'category': category.name,
    'items': items.map((item) => item.toJson()).toList(),
    'displayLabel': displayLabel,
    'listPageUrl': listPageUrl,
  };

  factory CampusNoticeSection.fromJson(Map<String, dynamic> json) {
    return CampusNoticeSection(
      category: CampusNoticeCategoryX.fromName(
        json['category'] as String? ?? CampusNoticeCategory.campusNotice.name,
      ),
      items: (json['items'] as List<dynamic>? ?? const [])
          .map(
            (item) => CampusNoticeItem.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      displayLabel: json['displayLabel'] as String?,
      listPageUrl: json['listPageUrl'] as String?,
    );
  }
}

class CampusNoticeSnapshot {
  const CampusNoticeSnapshot({
    required this.sections,
    required this.fetchedAt,
    required this.origin,
  });

  final List<CampusNoticeSection> sections;
  final DateTime fetchedAt;
  final DataOrigin origin;

  int get totalCount =>
      sections.fold(0, (total, section) => total + section.items.length);

  CampusNoticeSection sectionFor(CampusNoticeCategory category) {
    return sections.firstWhere(
      (item) => item.category == category,
      orElse: () => CampusNoticeSection(category: category, items: const []),
    );
  }

  String labelFor(CampusNoticeCategory category) {
    final label = sectionFor(category).displayLabel?.trim();
    if (label != null && label.isNotEmpty) {
      return label;
    }
    return category.defaultLabel;
  }

  CampusNoticeSnapshot copyWith({
    List<CampusNoticeSection>? sections,
    DateTime? fetchedAt,
    DataOrigin? origin,
  }) {
    return CampusNoticeSnapshot(
      sections: sections ?? this.sections,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      origin: origin ?? this.origin,
    );
  }

  Map<String, dynamic> toJson() => {
    'sections': sections.map((item) => item.toJson()).toList(),
    'fetchedAt': fetchedAt.toIso8601String(),
    'origin': origin.name,
  };

  factory CampusNoticeSnapshot.fromJson(Map<String, dynamic> json) {
    return CampusNoticeSnapshot(
      sections: (json['sections'] as List<dynamic>? ?? const [])
          .map(
            (item) =>
                CampusNoticeSection.fromJson(item as Map<String, dynamic>),
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

class CampusNoticeCategoryPage {
  const CampusNoticeCategoryPage({
    required this.category,
    required this.pageUrl,
    this.categoryLabel,
    required this.currentPage,
    required this.totalPages,
    required this.items,
    this.prevPageUrl,
    this.nextPageUrl,
    required this.fetchedAt,
    required this.origin,
  });

  final CampusNoticeCategory category;
  final String pageUrl;
  final String? categoryLabel;
  final int currentPage;
  final int totalPages;
  final List<CampusNoticeItem> items;
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

  CampusNoticeCategoryPage copyWith({
    CampusNoticeCategory? category,
    String? pageUrl,
    String? categoryLabel,
    int? currentPage,
    int? totalPages,
    List<CampusNoticeItem>? items,
    String? prevPageUrl,
    String? nextPageUrl,
    DateTime? fetchedAt,
    DataOrigin? origin,
  }) {
    return CampusNoticeCategoryPage(
      category: category ?? this.category,
      pageUrl: pageUrl ?? this.pageUrl,
      categoryLabel: categoryLabel ?? this.categoryLabel,
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
    'category': category.name,
    'pageUrl': pageUrl,
    'categoryLabel': categoryLabel,
    'currentPage': currentPage,
    'totalPages': totalPages,
    'items': items.map((item) => item.toJson()).toList(),
    'prevPageUrl': prevPageUrl,
    'nextPageUrl': nextPageUrl,
    'fetchedAt': fetchedAt.toIso8601String(),
    'origin': origin.name,
  };

  factory CampusNoticeCategoryPage.fromJson(Map<String, dynamic> json) {
    return CampusNoticeCategoryPage(
      category: CampusNoticeCategoryX.fromName(
        json['category'] as String? ?? CampusNoticeCategory.campusNotice.name,
      ),
      pageUrl: json['pageUrl'] as String? ?? '',
      categoryLabel: json['categoryLabel'] as String?,
      currentPage: json['currentPage'] as int? ?? 1,
      totalPages: json['totalPages'] as int? ?? 1,
      items: (json['items'] as List<dynamic>? ?? const [])
          .map(
            (item) => CampusNoticeItem.fromJson(item as Map<String, dynamic>),
          )
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

class CampusNoticeAttachment {
  const CampusNoticeAttachment({required this.title, required this.url});

  final String title;
  final String url;

  Map<String, dynamic> toJson() => {'title': title, 'url': url};

  factory CampusNoticeAttachment.fromJson(Map<String, dynamic> json) {
    return CampusNoticeAttachment(
      title: json['title'] as String? ?? '',
      url: json['url'] as String? ?? '',
    );
  }
}

/// A content block in a notice detail page — either a text paragraph or an image.
sealed class NoticeContentBlock {
  const NoticeContentBlock();
}

class NoticeTextBlock extends NoticeContentBlock {
  const NoticeTextBlock(this.text);
  final String text;
}

class NoticeImageBlock extends NoticeContentBlock {
  const NoticeImageBlock(this.url);
  final String url;
}

class CampusNoticeDetail {
  const CampusNoticeDetail({
    required this.item,
    required this.title,
    required this.contentBlocks,
    required this.attachments,
    required this.metaLines,
    required this.fetchedAt,
    required this.origin,
    this.source,
  });

  final CampusNoticeItem item;
  final String title;
  final List<NoticeContentBlock> contentBlocks;
  final List<CampusNoticeAttachment> attachments;
  final List<String> metaLines;
  final String? source;
  final DateTime fetchedAt;
  final DataOrigin origin;

  CampusNoticeDetail copyWith({
    CampusNoticeItem? item,
    String? title,
    List<NoticeContentBlock>? contentBlocks,
    List<CampusNoticeAttachment>? attachments,
    List<String>? metaLines,
    String? source,
    DateTime? fetchedAt,
    DataOrigin? origin,
  }) {
    return CampusNoticeDetail(
      item: item ?? this.item,
      title: title ?? this.title,
      contentBlocks: contentBlocks ?? this.contentBlocks,
      attachments: attachments ?? this.attachments,
      metaLines: metaLines ?? this.metaLines,
      source: source ?? this.source,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      origin: origin ?? this.origin,
    );
  }

  Map<String, dynamic> toJson() => {
    'item': item.toJson(),
    'title': title,
    'contentBlocks': contentBlocks
        .map(
          (b) => switch (b) {
            NoticeTextBlock(:final text) => {'type': 'text', 'text': text},
            NoticeImageBlock(:final url) => {'type': 'image', 'url': url},
          },
        )
        .toList(),
    'attachments': attachments.map((item) => item.toJson()).toList(),
    'metaLines': metaLines,
    'source': source,
    'fetchedAt': fetchedAt.toIso8601String(),
    'origin': origin.name,
  };

  factory CampusNoticeDetail.fromJson(Map<String, dynamic> json) {
    return CampusNoticeDetail(
      item: CampusNoticeItem.fromJson(json['item'] as Map<String, dynamic>),
      title: json['title'] as String? ?? '',
      contentBlocks: (json['contentBlocks'] as List<dynamic>? ?? const []).map((
        item,
      ) {
        final map = item as Map<String, dynamic>;
        return switch (map['type']) {
          'image' => NoticeImageBlock(map['url'] as String),
          _ => NoticeTextBlock(map['text'] as String),
        };
      }).toList(),
      attachments: (json['attachments'] as List<dynamic>? ?? const [])
          .map(
            (item) =>
                CampusNoticeAttachment.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      metaLines: (json['metaLines'] as List<dynamic>? ?? const [])
          .map((item) => '$item')
          .toList(),
      source: json['source'] as String?,
      fetchedAt: DateTime.parse(json['fetchedAt'] as String),
      origin: switch (json['origin']) {
        'cache' => DataOrigin.cache,
        _ => DataOrigin.remote,
      },
    );
  }
}
