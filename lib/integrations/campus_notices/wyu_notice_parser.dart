import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import '../../core/error/failure.dart';
import '../../core/logging/app_logger.dart';
import '../../core/models/data_origin.dart';
import '../../modules/notices/domain/entities/campus_notice.dart';

class WyuNoticeParser {
  const WyuNoticeParser();

  CampusNoticeSnapshot parseSnapshot(
    String html, {
    required Uri baseUri,
    AppLogger? logger,
  }) {
    final document = html_parser.parse(html);
    final categoryNavEntries = _extractCategoryNavEntries(
      document,
      baseUri: baseUri,
    );
    final sections = <CampusNoticeSection>[
      _parseWeeklySchedule(
        document,
        baseUri: baseUri,
        displayLabel:
            categoryNavEntries[CampusNoticeCategory.weeklySchedule]?.label,
      ),
      ..._parseNoticeSections(
        document,
        baseUri: baseUri,
        categoryNavEntries: categoryNavEntries,
      ),
    ];

    final ordered = <CampusNoticeSection>[];
    for (final category in CampusNoticeCategoryX.forBoard(
      NoticeBoardSource.campus,
    )) {
      final section = sections.firstWhere(
        (item) => item.category == category,
        orElse: () => CampusNoticeSection(category: category, items: const []),
      );
      final navEntry = categoryNavEntries[category];
      ordered.add(
        CampusNoticeSection(
          category: section.category,
          items: section.items,
          displayLabel: navEntry?.label ?? section.displayLabel,
          listPageUrl: navEntry?.url ?? section.listPageUrl,
        ),
      );
    }

    final totalCount = ordered.fold<int>(0, (sum, s) => sum + s.items.length);
    logger?.info(
      '[NOTICE] 通知列表解析完成 totalItems=$totalCount '
      'sections=${ordered.map((s) => '${s.displayLabel ?? s.category.name}=${s.items.length}').join(' | ')}',
    );
    _logSnapshotDetails(ordered, logger);

    return CampusNoticeSnapshot(
      sections: ordered,
      fetchedAt: DateTime.now(),
      origin: DataOrigin.remote,
    );
  }

  CampusNoticeDetail parseDetail({
    required String html,
    required Uri pageUri,
    required CampusNoticeItem item,
    AppLogger? logger,
  }) {
    final document = html_parser.parse(html);
    final title = _extractTitle(document) ?? item.title;
    final source = _extractSource(document);
    final metaLines = _extractMetaLines(document);
    final contentRoot = _findContentRoot(document);
    final attachmentRoot = _findAttachmentRoot(document, contentRoot);
    final contentBlocks = _extractContentBlocks(contentRoot, pageUri);
    final attachments = _extractAttachments(attachmentRoot, pageUri);

    if (contentBlocks.isEmpty && attachments.isEmpty) {
      throw const ParsingFailure('通知正文解析失败，未找到有效内容。');
    }

    final textCount = contentBlocks.whereType<NoticeTextBlock>().length;
    final imageCount = contentBlocks.whereType<NoticeImageBlock>().length;
    logger?.info(
      '[NOTICE] 通知详情解析完成 title=$title '
      'source=$source texts=$textCount images=$imageCount '
      'attachments=${attachments.length} metaLines=${metaLines.length}',
    );
    _logDetailDetails(
      detailTitle: title,
      source: source,
      metaLines: metaLines,
      contentBlocks: contentBlocks,
      attachments: attachments,
      logger: logger,
    );

    return CampusNoticeDetail(
      item: item,
      title: title,
      contentBlocks: contentBlocks,
      attachments: attachments,
      metaLines: metaLines,
      source: source,
      fetchedAt: DateTime.now(),
      origin: DataOrigin.remote,
    );
  }

  CampusNoticeCategoryPage parseCategoryPage(
    String html, {
    required Uri pageUri,
    required CampusNoticeCategory category,
    AppLogger? logger,
  }) {
    final document = html_parser.parse(html);
    final categoryLabel =
        _extractCategoryPageLabel(document) ?? category.defaultLabel;
    final items = _parseCategoryPageItems(
      document,
      pageUri: pageUri,
      category: category,
      categoryLabel: categoryLabel,
    );
    final pagination = _parsePagination(document, pageUri: pageUri);

    logger?.info(
      '[NOTICE] 分类分页解析完成 category=$categoryLabel '
      'page=${pagination.currentPage}/${pagination.totalPages} '
      'items=${items.length} hasMore=${pagination.nextPageUrl != null}',
    );
    _logCategoryPageDetails(
      categoryLabel: categoryLabel,
      currentPage: pagination.currentPage,
      totalPages: pagination.totalPages,
      prevPageUrl: pagination.prevPageUrl,
      nextPageUrl: pagination.nextPageUrl,
      items: items,
      logger: logger,
    );

    return CampusNoticeCategoryPage(
      category: category,
      pageUrl: pageUri.toString(),
      categoryLabel: categoryLabel,
      currentPage: pagination.currentPage,
      totalPages: pagination.totalPages,
      items: items,
      prevPageUrl: pagination.prevPageUrl,
      nextPageUrl: pagination.nextPageUrl,
      fetchedAt: DateTime.now(),
      origin: DataOrigin.remote,
    );
  }

  // --- Snapshot parsing ---

  CampusNoticeSection _parseWeeklySchedule(
    Document document, {
    required Uri baseUri,
    String? displayLabel,
  }) {
    final items = document
        .querySelectorAll('.swiper-right .swiper-slide a.con')
        .map(
          (node) => _parseItem(
            node,
            baseUri: baseUri,
            fallbackCategory: CampusNoticeCategory.weeklySchedule,
            categoryLabel: displayLabel,
          ),
        )
        .whereType<CampusNoticeItem>()
        .toList();

    return CampusNoticeSection(
      category: CampusNoticeCategory.weeklySchedule,
      items: items,
      displayLabel: displayLabel,
    );
  }

  List<CampusNoticeSection> _parseNoticeSections(
    Document document, {
    required Uri baseUri,
    required Map<CampusNoticeCategory, _CategoryNavEntry> categoryNavEntries,
  }) {
    final sections = <CampusNoticeSection>[];
    for (final titleNode in document.querySelectorAll('.g-notice-tit1')) {
      final normalizedTitle = _normalizeCategoryText(titleNode.text);
      MapEntry<CampusNoticeCategory, _CategoryNavEntry>? matchedEntry;
      for (final entry in categoryNavEntries.entries) {
        if (_normalizeCategoryText(entry.value.label) == normalizedTitle) {
          matchedEntry = entry;
          break;
        }
      }
      final category = matchedEntry?.key;
      if (category == null) {
        continue;
      }

      final sectionRoot = titleNode.parent;
      final items =
          sectionRoot
              ?.querySelectorAll('ul.ul-normative-documents a.con')
              .map(
                (node) => _parseItem(
                  node,
                  baseUri: baseUri,
                  fallbackCategory: category,
                  categoryLabel: matchedEntry?.value.label,
                ),
              )
              .whereType<CampusNoticeItem>()
              .toList() ??
          const <CampusNoticeItem>[];

      sections.add(
        CampusNoticeSection(
          category: category,
          items: items,
          displayLabel: matchedEntry?.value.label ?? normalizedTitle,
          listPageUrl: _findSectionListPageUrl(titleNode, baseUri: baseUri),
        ),
      );
    }
    return sections;
  }

  CampusNoticeItem? _parseItem(
    Element node, {
    required Uri baseUri,
    required CampusNoticeCategory fallbackCategory,
    String? categoryLabel,
  }) {
    final href = node.attributes['href'];
    final title =
        node.querySelector('.tit')?.text.trim() ??
        node.attributes['title']?.trim() ??
        '';
    final dateText = node.querySelector('.date')?.text.trim() ?? '';
    final summary = _extractSummaryFromNode(
      node,
      title: title,
      dateText: dateText,
    );
    if (href == null || title.isEmpty || dateText.isEmpty) {
      return null;
    }

    final detailUri = baseUri.resolve(href);
    final publishedAt = _parseDate(dateText);
    final newsId = detailUri.queryParameters['wbnewsid'] ?? '';
    final treeId = detailUri.queryParameters['wbtreeid'] ?? '';

    return CampusNoticeItem(
      category: fallbackCategory,
      newsId: newsId,
      treeId: treeId,
      title: title,
      categoryLabel: categoryLabel,
      summary: summary,
      publishedAt: publishedAt,
      detailUrl: detailUri.toString(),
    );
  }

  DateTime _parseDate(String value) {
    final normalized = value.replaceAll('/', '-').trim();
    final parts = normalized.split('-');
    if (parts.length != 3) {
      throw ParsingFailure('通知日期格式异常: $value');
    }

    return DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }

  List<CampusNoticeItem> _parseCategoryPageItems(
    Document document, {
    required Uri pageUri,
    required CampusNoticeCategory category,
    required String categoryLabel,
  }) {
    final items = <CampusNoticeItem>[];
    final seen = <String>{};

    for (final node in document.querySelectorAll('li')) {
      final anchor = node.querySelector('a[href]');
      if (anchor == null) {
        continue;
      }

      final href = anchor.attributes['href'] ?? '';
      if (!_looksLikeDetailHref(href)) {
        continue;
      }

      final title = _normalizeText(anchor.text);
      final dateText = _extractDateText(node.text);
      if (title.isEmpty || dateText == null) {
        continue;
      }

      final item = _buildNoticeItem(
        href: href,
        title: title,
        categoryLabel: categoryLabel,
        summary: _extractSummaryFromNode(
          node,
          title: title,
          dateText: dateText,
        ),
        dateText: dateText,
        baseUri: pageUri,
        fallbackCategory: category,
      );
      if (item == null || !seen.add(item.cacheKey)) {
        continue;
      }
      items.add(item);
    }

    if (items.isNotEmpty) {
      return items;
    }

    for (final anchor in document.querySelectorAll('a[href]')) {
      final href = anchor.attributes['href'] ?? '';
      if (!_looksLikeDetailHref(href)) {
        continue;
      }

      final contextText = _normalizeText(anchor.parent?.text ?? anchor.text);
      final dateText = _extractDateText(contextText);
      final title = _normalizeText(anchor.text);
      if (title.isEmpty || dateText == null) {
        continue;
      }

      final item = _buildNoticeItem(
        href: href,
        title: title,
        categoryLabel: categoryLabel,
        summary: _extractSummaryFromNode(
          anchor.parent ?? anchor,
          title: title,
          dateText: dateText,
        ),
        dateText: dateText,
        baseUri: pageUri,
        fallbackCategory: category,
      );
      if (item == null || !seen.add(item.cacheKey)) {
        continue;
      }
      items.add(item);
    }

    return items;
  }

  _PaginationInfo _parsePagination(Document document, {required Uri pageUri}) {
    final paginationRoot = document.querySelector('.pb_sys_common');
    if (paginationRoot == null) {
      return const _PaginationInfo(currentPage: 1, totalPages: 1);
    }

    final currentPage =
        int.tryParse(
          paginationRoot.querySelector('.p_no_d')?.text.trim() ?? '',
        ) ??
        int.tryParse(pageUri.queryParameters['PAGENUM'] ?? '') ??
        1;

    var totalPages = 1;
    for (final anchor in paginationRoot.querySelectorAll('a[href]')) {
      final href = anchor.attributes['href'] ?? '';
      final candidateUri = pageUri.resolve(href);
      final totalPageCandidate =
          int.tryParse(candidateUri.queryParameters['totalpage'] ?? '') ??
          int.tryParse(anchor.text.trim());
      if (totalPageCandidate != null && totalPageCandidate > totalPages) {
        totalPages = totalPageCandidate;
      }
    }

    final prevHref = paginationRoot
        .querySelector('.p_prev a[href]')
        ?.attributes['href'];
    final prevPageUrl = switch (prevHref) {
      final String value when value.trim().isNotEmpty =>
        pageUri.resolve(value).toString(),
      _ => null,
    };

    final nextHref = paginationRoot
        .querySelector('.p_next a[href]')
        ?.attributes['href'];
    final nextPageUrl = switch (nextHref) {
      final String value when value.trim().isNotEmpty =>
        pageUri.resolve(value).toString(),
      _ => null,
    };

    return _PaginationInfo(
      currentPage: currentPage,
      totalPages: totalPages,
      prevPageUrl: prevPageUrl,
      nextPageUrl: nextPageUrl,
    );
  }

  bool _looksLikeDetailHref(String href) {
    final normalized = href.trim();
    if (normalized.isEmpty) {
      return false;
    }
    if (normalized.contains('urltype=news.NewsContentUrl')) {
      return true;
    }
    if (normalized.contains('xnzx_content.jsp')) {
      return true;
    }
    return false;
  }

  String? _extractDateText(String text) {
    final match = RegExp(r'(\d{4}[/-]\d{2}[/-]\d{2})').firstMatch(text);
    return match?.group(1);
  }

  CampusNoticeItem? _buildNoticeItem({
    required String href,
    required String title,
    required String categoryLabel,
    String? summary,
    required String dateText,
    required Uri baseUri,
    required CampusNoticeCategory fallbackCategory,
  }) {
    final detailUri = baseUri.resolve(href);
    final publishedAt = _parseDate(dateText);
    final newsId =
        detailUri.queryParameters['wbnewsid'] ??
        detailUri.pathSegments.lastOrNull?.replaceAll('.htm', '') ??
        '';
    final treeId = detailUri.queryParameters['wbtreeid'] ?? '';

    return CampusNoticeItem(
      category: fallbackCategory,
      newsId: newsId,
      treeId: treeId,
      title: title,
      categoryLabel: categoryLabel,
      summary: summary,
      publishedAt: publishedAt,
      detailUrl: detailUri.toString(),
    );
  }

  String? _extractSummaryFromNode(
    Element node, {
    required String title,
    String? dateText,
  }) {
    const selectors = [
      '.zy',
      '.summary',
      '.desc',
      '.abstract',
      '.content',
      '.text',
      '.introduce',
      'p',
    ];

    for (final selector in selectors) {
      for (final element in node.querySelectorAll(selector)) {
        final text = _normalizeText(element.text);
        final cleaned = _cleanSummaryText(
          text,
          title: title,
          dateText: dateText,
        );
        if (cleaned != null) {
          return cleaned;
        }
      }
    }

    return _cleanSummaryText(
      _normalizeText(node.text),
      title: title,
      dateText: dateText,
    );
  }

  String? _cleanSummaryText(
    String text, {
    required String title,
    String? dateText,
  }) {
    var value = text.trim();
    if (value.isEmpty) {
      return null;
    }

    final normalizedTitle = _normalizeText(title);
    final normalizedDateText = dateText == null
        ? null
        : _normalizeText(dateText);

    if (normalizedTitle.isNotEmpty) {
      value = value.replaceAll(normalizedTitle, ' ');
    }
    if (normalizedDateText != null && normalizedDateText.isNotEmpty) {
      value = value.replaceAll(normalizedDateText, ' ');
    }

    value = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (value.isEmpty || value == normalizedTitle) {
      return null;
    }

    return value;
  }

  String? _findSectionListPageUrl(Element titleNode, {required Uri baseUri}) {
    Element? current = titleNode.parent;
    var depth = 0;
    while (current != null && depth < 4) {
      for (final link in current.querySelectorAll('a[href]')) {
        final href = link.attributes['href'] ?? '';
        if (href.contains('list_wuzhaiyao.jsp') ||
            href.contains('urltype=tree.TreeTempUrl')) {
          return baseUri.resolve(href).toString();
        }
      }
      current = current.parent;
      depth += 1;
    }
    return null;
  }

  Map<CampusNoticeCategory, _CategoryNavEntry> _extractCategoryNavEntries(
    Document document, {
    required Uri baseUri,
  }) {
    final entries = <CampusNoticeCategory, _CategoryNavEntry>{};
    final categoryLinks =
        document.querySelectorAll('.m-nav-z .layui-menu a[href]').isNotEmpty
        ? document.querySelectorAll('.m-nav-z .layui-menu a[href]')
        : document.querySelectorAll('.layui-menu a[href]');
    final campusCategories = CampusNoticeCategoryX.forBoard(
      NoticeBoardSource.campus,
    );
    var index = 0;

    for (final link in categoryLinks) {
      final href = link.attributes['href'] ?? '';
      if (href.isEmpty ||
          (!href.contains('list_wuzhaiyao.jsp') &&
              !href.contains('urltype=tree.TreeTempUrl'))) {
        continue;
      }
      if (href.contains('xxgw.jsp')) {
        continue;
      }

      final label = _normalizeCategoryText(
        link.querySelector('span')?.text ??
            link.attributes['title'] ??
            link.text,
      );
      if (label.isEmpty || index >= campusCategories.length) {
        continue;
      }

      final category = campusCategories[index];
      entries[category] = _CategoryNavEntry(
        label: label,
        url: baseUri.resolve(href).toString(),
      );
      index += 1;
    }

    return entries;
  }

  String? _extractCategoryPageLabel(Document document) {
    const selectors = [
      '.g-title-z .tit',
      '.m-nav-z .layui-menu-body-title.on span',
      'title',
    ];

    for (final selector in selectors) {
      final text = _normalizeCategoryText(
        document.querySelector(selector)?.text ?? '',
      );
      if (text.isNotEmpty) {
        return text;
      }
    }

    return null;
  }

  // --- Detail parsing ---

  String? _extractTitle(Document document) {
    const selectors = [
      '.arti_title',
      '.article-title',
      '.news_title',
      '.show_t',
      '.content-title',
      'h1',
      'h2',
    ];

    for (final selector in selectors) {
      final text = document.querySelector(selector)?.text.trim();
      if (text != null && text.isNotEmpty) {
        return text;
      }
    }
    return null;
  }

  String? _extractSource(Document document) {
    // First, try extracting from the .info div directly — this is where
    // "发布单位：教务处" appears in the typical page layout.
    final infoDiv = document.querySelector('.info');
    if (infoDiv != null) {
      final infoText = _normalizeText(infoDiv.text);
      for (final pattern in [
        RegExp(r'发布单位[:：]\s*([^\s\n\r]+)'),
        RegExp(r'来源[:：]\s*([^\n\r]+)'),
      ]) {
        final match = pattern.firstMatch(infoText);
        if (match != null) {
          final value = match.group(1)?.trim();
          if (value != null && value.isNotEmpty) {
            return value.split(RegExp(r'\s{2,}')).first.trim();
          }
        }
      }
    }

    final candidates = <String>[
      ..._extractRawMetaLines(document),
      document.body?.text ?? '',
    ];

    for (final text in candidates) {
      for (final pattern in [
        RegExp(r'发布单位[:：]\s*([^\s\n\r]+)'),
        RegExp(r'来源[:：]\s*([^\n\r]+)'),
      ]) {
        final match = pattern.firstMatch(text);
        final value = match?.group(1)?.trim();
        if (value != null && value.isNotEmpty) {
          return value.split(RegExp(r'\s{2,}')).first.trim();
        }
      }
    }
    return null;
  }

  /// Extracts and cleans meta lines from the detail page.
  /// Filters out JS calls like showDynclicks, and unrelated items
  /// like "官方微信", "VR校园", "视频号", "点击数".
  List<String> _extractMetaLines(Document document) {
    final raw = _extractRawMetaLines(document);
    return raw
        .expand((text) => text.split(RegExp(r'\s{2,}')))
        .map((s) => s.trim())
        .where((line) => line.isNotEmpty && _isValidMetaLine(line))
        .toList();
  }

  List<String> _extractRawMetaLines(Document document) {
    const selectors = [
      '.arti_metas',
      '.article-info',
      '.show_time',
      '.show-info',
      '.content-info',
      '.ly',
      '.info',
    ];

    final values = <String>[];
    for (final selector in selectors) {
      for (final node in document.querySelectorAll(selector)) {
        final text = _normalizeText(node.text);
        if (text.isNotEmpty && !values.contains(text)) {
          values.add(text);
        }
      }
    }
    return values;
  }

  bool _isValidMetaLine(String line) {
    // Filter out JS click counter calls
    if (line.contains('showDynclicks')) return false;
    // Filter out common unrelated footer items
    if (line == '官方微信') return false;
    if (line == 'VR校园') return false;
    if (line == '视频号') return false;
    if (line == '系统提示') return false;
    // Filter out raw "点击数 ... 次" patterns with JS noise
    if (RegExp(r'^点击数').hasMatch(line)) return false;
    // Filter lines that are just numbers (from JS args)
    if (RegExp(r'^\d+$').hasMatch(line)) return false;
    return true;
  }

  Element _findContentRoot(Document document) {
    const selectors = [
      '.v_news_content',
      '#vsb_content',
      '.TRS_Editor',
      '.wp_articlecontent',
      '.article-content',
      '.article-con',
      '.content',
      '.show-con',
      '.news_content',
      '#content',
    ];

    for (final selector in selectors) {
      final node = document.querySelector(selector);
      if (node == null) {
        continue;
      }
      final text = _normalizeText(node.text);
      if (text.length >= 40) {
        return node;
      }
    }

    return document.body ?? document.documentElement!;
  }

  /// Extract content blocks (text paragraphs + inline images) in document order.
  List<NoticeContentBlock> _extractContentBlocks(Element root, Uri pageUri) {
    final blocks = <NoticeContentBlock>[];
    final seenTexts = <String>{};
    final seenImageUrls = <String>{};

    for (final script in root.querySelectorAll('script, style, noscript')) {
      script.remove();
    }

    for (final node in root.querySelectorAll('p, li, h2, h3, h4')) {
      // Check if this node contains images
      final images = node.querySelectorAll('img');
      for (final img in images) {
        final src = _pickImageSource(img);
        if (src == null || src.trim().isEmpty) continue;
        final resolved = pageUri.resolve(src).toString();
        if (seenImageUrls.add(resolved)) {
          blocks.add(NoticeImageBlock(resolved));
        }
      }

      // Extract text content
      final text = _normalizeText(node.text);
      if (_shouldKeepLine(text, seenTexts)) {
        blocks.add(NoticeTextBlock(text));
      }
    }

    if (blocks.isNotEmpty) {
      return blocks;
    }

    // Fallback: plain text extraction
    for (final line in root.text.split(RegExp(r'[\n\r]+'))) {
      final text = _normalizeText(line);
      if (_shouldKeepLine(text, seenTexts)) {
        blocks.add(NoticeTextBlock(text));
      }
    }
    return blocks;
  }

  String? _pickImageSource(Element image) {
    const candidates = [
      'zoomfile',
      'data-original',
      'data-src',
      'data-actualsrc',
      'data-layer-src',
      'orisrc',
      '_src',
      'src',
    ];

    for (final key in candidates) {
      final value = image.attributes[key]?.trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  Element _findAttachmentRoot(Document document, Element contentRoot) {
    if (_containsAttachmentLinks(contentRoot)) {
      return contentRoot;
    }

    for (final selector in const [
      '.desc',
      'form[name="_newscontent_fromname"]',
      '.m-txtbodydeatil',
      '.row-news-detail',
    ]) {
      final candidate = document.querySelector(selector);
      if (candidate != null && _containsAttachmentLinks(candidate)) {
        return candidate;
      }
    }

    Element? current = contentRoot.parent;
    var depth = 0;
    while (current != null && depth < 6) {
      if (_containsAttachmentLinks(current)) {
        return current;
      }
      current = current.parent;
      depth += 1;
    }

    return document.body ?? contentRoot;
  }

  bool _containsAttachmentLinks(Element root) {
    for (final link in root.querySelectorAll('a[href]')) {
      final href = link.attributes['href'] ?? '';
      final text = _normalizeText(link.text);
      if (_looksLikeAttachmentLink(href: href, text: text)) {
        return true;
      }
    }
    return false;
  }

  List<CampusNoticeAttachment> _extractAttachments(Element root, Uri pageUri) {
    final files = <CampusNoticeAttachment>[];
    final seen = <String>{};

    for (final link in root.querySelectorAll('a[href]')) {
      final href = link.attributes['href'];
      if (href == null || href.trim().isEmpty) {
        continue;
      }

      final resolved = pageUri.resolve(href).toString();
      final text = _normalizeText(link.text);
      final isAttachment = _looksLikeAttachmentLink(href: resolved, text: text);

      if (!isAttachment || !seen.add(resolved)) {
        continue;
      }

      files.add(
        CampusNoticeAttachment(
          title: text.isEmpty ? '附件' : text,
          url: resolved,
        ),
      );
    }

    return files;
  }

  bool _looksLikeAttachmentLink({required String href, required String text}) {
    final normalizedHref = href.trim().toLowerCase();
    if (normalizedHref.isEmpty) {
      return false;
    }

    return normalizedHref.contains('download.jsp') ||
        normalizedHref.contains('downloadattachurl') ||
        RegExp(
          r'\.(pdf|doc|docx|xls|xlsx|ppt|pptx|zip|rar|7z|jpg|jpeg|png)$',
          caseSensitive: false,
        ).hasMatch(normalizedHref) ||
        text.contains('附件');
  }

  bool _shouldKeepLine(String text, Set<String> existing) {
    if (text.isEmpty || text.length < 2) {
      return false;
    }
    if (existing.contains(text)) {
      return false;
    }
    if (text == '系统提示' || text.contains('统一身份认证平台')) {
      return false;
    }
    if (text.contains('showDynclicks')) {
      return false;
    }
    if (text == '官方微信' || text == 'VR校园' || text == '视频号') {
      return false;
    }
    if (RegExp(r'^点击数').hasMatch(text)) {
      return false;
    }
    return true;
  }

  String _normalizeText(String value) {
    return value
        .replaceAll('\u00a0', ' ')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\n\s+'), '\n')
        .trim();
  }

  String _normalizeCategoryText(String value) {
    return _normalizeText(value).replaceAll(':', '').replaceAll('：', '');
  }

  void _logSnapshotDetails(
    List<CampusNoticeSection> sections,
    AppLogger? logger,
  ) {
    if (logger == null) {
      return;
    }

    final lines = <String>[];
    for (final section in sections) {
      lines.add(
        'section=${section.displayLabel ?? section.category.name} items=${section.items.length} listPageUrl=${section.listPageUrl ?? '-'}',
      );
      if (section.items.isEmpty) {
        lines.add('  <empty>');
        continue;
      }
      for (final item in section.items) {
        lines.add(
          '  item newsId=${item.newsId} treeId=${item.treeId} date=${item.publishedAt.toIso8601String()}',
        );
        lines.add('    title=${item.title}');
        lines.add('    summary=${item.summary ?? '-'}');
        lines.add('    detailUrl=${item.detailUrl}');
      }
    }

    logger.infoBlock('[NOTICE][PARSED][SNAPSHOT]', lines.join('\n'));
  }

  void _logCategoryPageDetails({
    required String categoryLabel,
    required int currentPage,
    required int totalPages,
    required String? prevPageUrl,
    required String? nextPageUrl,
    required List<CampusNoticeItem> items,
    required AppLogger? logger,
  }) {
    if (logger == null) {
      return;
    }

    final lines = <String>[
      'category=$categoryLabel',
      'currentPage=$currentPage',
      'totalPages=$totalPages',
      'prevPageUrl=${prevPageUrl ?? '-'}',
      'nextPageUrl=${nextPageUrl ?? '-'}',
      'itemCount=${items.length}',
    ];

    for (final item in items) {
      lines.add(
        'item newsId=${item.newsId} treeId=${item.treeId} date=${item.publishedAt.toIso8601String()}',
      );
      lines.add('  categoryLabel=${item.categoryLabel ?? '-'}');
      lines.add('  title=${item.title}');
      lines.add('  summary=${item.summary ?? '-'}');
      lines.add('  detailUrl=${item.detailUrl}');
    }

    logger.infoBlock(
      '[NOTICE][PARSED][CATEGORY][$categoryLabel]',
      lines.join('\n'),
    );
  }

  void _logDetailDetails({
    required String detailTitle,
    required String? source,
    required List<String> metaLines,
    required List<NoticeContentBlock> contentBlocks,
    required List<CampusNoticeAttachment> attachments,
    required AppLogger? logger,
  }) {
    if (logger == null) {
      return;
    }

    final lines = <String>[
      'title=$detailTitle',
      'source=${source ?? '-'}',
      'metaLines=${metaLines.isEmpty ? '[]' : metaLines.join(' | ')}',
      'contentBlockCount=${contentBlocks.length}',
      'attachmentCount=${attachments.length}',
    ];

    for (var index = 0; index < contentBlocks.length; index += 1) {
      final block = contentBlocks[index];
      switch (block) {
        case NoticeTextBlock(:final text):
          lines.add('block[$index]=text');
          lines.add(text);
        case NoticeImageBlock(:final url):
          lines.add('block[$index]=image');
          lines.add(url);
      }
    }

    for (var index = 0; index < attachments.length; index += 1) {
      final attachment = attachments[index];
      lines.add('attachment[$index].title=${attachment.title}');
      lines.add('attachment[$index].url=${attachment.url}');
    }

    logger.infoBlock('[NOTICE][PARSED][DETAIL]', lines.join('\n'));
  }
}

class _PaginationInfo {
  const _PaginationInfo({
    required this.currentPage,
    required this.totalPages,
    this.prevPageUrl,
    this.nextPageUrl,
  });

  final int currentPage;
  final int totalPages;
  final String? prevPageUrl;
  final String? nextPageUrl;
}

class _CategoryNavEntry {
  const _CategoryNavEntry({required this.label, required this.url});

  final String label;
  final String url;
}

extension<T> on List<T> {
  T? get lastOrNull => isEmpty ? null : last;
}
