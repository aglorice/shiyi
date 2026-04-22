import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import '../../core/error/failure.dart';
import '../../core/logging/app_logger.dart';
import '../../core/models/data_origin.dart';
import '../../modules/notices/domain/entities/campus_notice.dart';

class WyuGraduateNoticeParser {
  const WyuGraduateNoticeParser();

  CampusNoticeSnapshot parseSnapshot(
    String html, {
    required Uri baseUri,
    AppLogger? logger,
  }) {
    final document = html_parser.parse(html);
    final sections = <CampusNoticeSection>[
      _parseSimpleListSection(
        root: document.querySelector('.tzgglf .talislk'),
        baseUri: baseUri,
        category: CampusNoticeCategory.graduateNoticeAnnouncement,
        displayLabel:
            CampusNoticeCategory.graduateNoticeAnnouncement.defaultLabel,
        listPageUrl: baseUri.resolve('tzgg.htm').toString(),
      ),
      _parseDepartmentNewsSection(
        root: document.querySelector('.tzggrr .taoppz'),
        baseUri: baseUri,
        category: CampusNoticeCategory.graduateDepartmentNews,
        displayLabel: CampusNoticeCategory.graduateDepartmentNews.defaultLabel,
        listPageUrl: baseUri.resolve('bmxw.htm').toString(),
      ),
      _parseSimpleListSection(
        root: document.querySelector('#c01 .taggk'),
        baseUri: baseUri,
        category: CampusNoticeCategory.graduateAdmissions,
        displayLabel: CampusNoticeCategory.graduateAdmissions.defaultLabel,
        listPageUrl: baseUri.resolve('zsdt.htm').toString(),
      ),
      _parseSimpleListSection(
        root: document.querySelector('#c02 .taggk'),
        baseUri: baseUri,
        category: CampusNoticeCategory.graduateTheoryStudy,
        displayLabel: CampusNoticeCategory.graduateTheoryStudy.defaultLabel,
        listPageUrl: baseUri.resolve('llxx.htm').toString(),
      ),
      _parseSimpleListSection(
        root: document.querySelector('#c03 .taggk'),
        baseUri: baseUri,
        category: CampusNoticeCategory.graduateEducationBriefing,
        displayLabel:
            CampusNoticeCategory.graduateEducationBriefing.defaultLabel,
        listPageUrl: baseUri.resolve('yjsjydt.htm').toString(),
      ),
    ];

    logger?.info(
      '[GRAD_NOTICE] 研究生通知首页解析完成 '
      'sections=${sections.map((item) => '${item.displayLabel}=${item.items.length}').join(' | ')}',
    );

    return CampusNoticeSnapshot(
      sections: sections,
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
    final items = _parseCategoryPageItems(
      document,
      pageUri: pageUri,
      category: category,
      categoryLabel: category.defaultLabel,
    );
    final pagination = _parsePagination(document, pageUri: pageUri);

    logger?.info(
      '[GRAD_NOTICE] 分类分页解析完成 category=${category.defaultLabel} '
      'page=${pagination.currentPage}/${pagination.totalPages} '
      'items=${items.length} hasMore=${pagination.nextPageUrl != null}',
    );

    return CampusNoticeCategoryPage(
      category: category,
      pageUrl: pageUri.toString(),
      categoryLabel: category.defaultLabel,
      currentPage: pagination.currentPage,
      totalPages: pagination.totalPages,
      items: items,
      prevPageUrl: pagination.prevPageUrl,
      nextPageUrl: pagination.nextPageUrl,
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
      throw const ParsingFailure('研究生通知正文解析失败，未找到有效内容。');
    }

    logger?.info(
      '[GRAD_NOTICE] 详情解析完成 title=$title '
      'texts=${contentBlocks.whereType<NoticeTextBlock>().length} '
      'images=${contentBlocks.whereType<NoticeImageBlock>().length} '
      'attachments=${attachments.length}',
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

  CampusNoticeSection _parseSimpleListSection({
    required Element? root,
    required Uri baseUri,
    required CampusNoticeCategory category,
    required String displayLabel,
    required String listPageUrl,
  }) {
    final items =
        root
            ?.querySelectorAll('li')
            .map((node) {
              return _parseSimpleListItem(
                node,
                baseUri: baseUri,
                category: category,
                categoryLabel: displayLabel,
              );
            })
            .whereType<CampusNoticeItem>()
            .toList() ??
        const <CampusNoticeItem>[];

    return CampusNoticeSection(
      category: category,
      items: items,
      displayLabel: displayLabel,
      listPageUrl: listPageUrl,
    );
  }

  CampusNoticeSection _parseDepartmentNewsSection({
    required Element? root,
    required Uri baseUri,
    required CampusNoticeCategory category,
    required String displayLabel,
    required String listPageUrl,
  }) {
    final items = <CampusNoticeItem>[];
    for (final node
        in root?.querySelectorAll('.tanr780li') ?? const <Element>[]) {
      final anchor = node.querySelector('a[href]');
      final href = anchor?.attributes['href'] ?? '';
      final monthDay = _normalizeText(
        node.querySelector('.tanr780lilf h3')?.text ?? '',
      );
      final year = _normalizeText(
        node.querySelector('.tanr780lilf p')?.text ?? '',
      );
      final title = _normalizeText(
        anchor?.attributes['title'] ??
            anchor?.querySelector('h3')?.text ??
            anchor?.text ??
            '',
      );
      final summary = _normalizeText(anchor?.querySelector('p')?.text ?? '');

      if (href.isEmpty || title.isEmpty || monthDay.isEmpty || year.isEmpty) {
        continue;
      }

      final item = _buildNoticeItem(
        href: href,
        title: title,
        categoryLabel: displayLabel,
        summary: summary.isEmpty ? null : summary,
        dateText: '$year-$monthDay',
        baseUri: baseUri,
        category: category,
      );
      if (item != null) {
        items.add(item);
      }
    }

    return CampusNoticeSection(
      category: category,
      items: items,
      displayLabel: displayLabel,
      listPageUrl: listPageUrl,
    );
  }

  CampusNoticeItem? _parseSimpleListItem(
    Element node, {
    required Uri baseUri,
    required CampusNoticeCategory category,
    required String categoryLabel,
  }) {
    final anchor = node.querySelector('a[href]');
    final href = anchor?.attributes['href'] ?? '';
    final title = _normalizeText(
      anchor?.attributes['title'] ?? anchor?.text ?? '',
    );
    final dateText = _extractDateText(node.text);
    if (href.isEmpty || title.isEmpty || dateText == null) {
      return null;
    }

    return _buildNoticeItem(
      href: href,
      title: title,
      categoryLabel: categoryLabel,
      summary: _extractSummaryFromNode(node, title: title, dateText: dateText),
      dateText: dateText,
      baseUri: baseUri,
      category: category,
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

      final title = _normalizeText(anchor.attributes['title'] ?? anchor.text);
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
        category: category,
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
      final title = _normalizeText(anchor.attributes['title'] ?? anchor.text);
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
        category: category,
      );
      if (item == null || !seen.add(item.cacheKey)) {
        continue;
      }
      items.add(item);
    }

    return items;
  }

  _PaginationInfo _parsePagination(Document document, {required Uri pageUri}) {
    final pageText = _normalizeText(document.body?.text ?? '');
    final match = RegExp(r'共\s*\d+条\s*(\d+)\s*/\s*(\d+)').firstMatch(pageText);
    final currentPage = int.tryParse(match?.group(1) ?? '') ?? 1;
    final totalPages = int.tryParse(match?.group(2) ?? '') ?? 1;

    String? prevPageUrl;
    String? nextPageUrl;
    for (final anchor in document.querySelectorAll('a[href]')) {
      final href = anchor.attributes['href']?.trim() ?? '';
      final label = _normalizeText(anchor.text);
      if (href.isEmpty) {
        continue;
      }
      if (label == '上页' && prevPageUrl == null) {
        prevPageUrl = pageUri.resolve(href).toString();
      }
      if (label == '下页' && nextPageUrl == null) {
        nextPageUrl = pageUri.resolve(href).toString();
      }
    }

    return _PaginationInfo(
      currentPage: currentPage,
      totalPages: totalPages,
      prevPageUrl: prevPageUrl,
      nextPageUrl: nextPageUrl,
    );
  }

  CampusNoticeItem? _buildNoticeItem({
    required String href,
    required String title,
    required String categoryLabel,
    required String dateText,
    required Uri baseUri,
    required CampusNoticeCategory category,
    String? summary,
  }) {
    final detailUri = baseUri.resolve(href);
    final pathSegments = detailUri.pathSegments;
    final newsId =
        detailUri.queryParameters['wbnewsid'] ??
        (pathSegments.isNotEmpty
            ? pathSegments.last.replaceAll('.htm', '')
            : '');
    final treeId =
        detailUri.queryParameters['wbtreeid'] ??
        (pathSegments.length >= 2 ? pathSegments[pathSegments.length - 2] : '');

    return CampusNoticeItem(
      category: category,
      newsId: newsId,
      treeId: treeId,
      title: title,
      categoryLabel: categoryLabel,
      summary: summary,
      publishedAt: _parseDate(dateText),
      detailUrl: detailUri.toString(),
    );
  }

  String? _extractTitle(Document document) {
    for (final selector in const ['.conth1', '.arti_title', 'h1', 'title']) {
      final text = _normalizeText(document.querySelector(selector)?.text ?? '');
      if (text.isNotEmpty) {
        return text
            .replaceAll('-五邑大学-研究生处', '')
            .replaceAll(' - 五邑大学-研究生处', '')
            .trim();
      }
    }
    return null;
  }

  String? _extractSource(Document document) {
    final meta = _normalizeText(document.querySelector('.conthsj')?.text ?? '');
    final match = RegExp(r'信息来源[:：]\s*(.+?)(?:点击数|$)').firstMatch(meta);
    final value = _normalizeText(match?.group(1) ?? '');
    return value.isEmpty ? null : value;
  }

  List<String> _extractMetaLines(Document document) {
    final meta = _normalizeText(document.querySelector('.conthsj')?.text ?? '');
    if (meta.isEmpty) {
      return const [];
    }

    final lines = <String>[];
    final dateMatch = RegExp(r'日期[:：]\s*([0-9-]+)').firstMatch(meta);
    final sourceMatch = RegExp(r'信息来源[:：]\s*(.+?)(?:点击数|$)').firstMatch(meta);

    final dateValue = _normalizeText(dateMatch?.group(1) ?? '');
    if (dateValue.isNotEmpty) {
      lines.add('日期：$dateValue');
    }
    final sourceValue = _normalizeText(sourceMatch?.group(1) ?? '');
    if (sourceValue.isNotEmpty) {
      lines.add('信息来源：$sourceValue');
    }
    return lines;
  }

  Element _findContentRoot(Document document) {
    for (final selector in const [
      '.v_news_content',
      '#vsb_content',
      '.concon',
      '.article-content',
      '.content',
    ]) {
      final node = document.querySelector(selector);
      if (node == null) {
        continue;
      }
      if (_normalizeText(node.text).length >= 20) {
        return node;
      }
    }

    return document.body ?? document.documentElement!;
  }

  List<NoticeContentBlock> _extractContentBlocks(Element root, Uri pageUri) {
    final blocks = <NoticeContentBlock>[];
    final seenTexts = <String>{};
    final seenImageUrls = <String>{};

    for (final script in root.querySelectorAll('script, style, noscript')) {
      script.remove();
    }

    for (final node in root.querySelectorAll('p, li, h2, h3, h4, h5, tr')) {
      for (final image in node.querySelectorAll('img')) {
        final src = _pickImageSource(image);
        if (src == null || src.isEmpty) {
          continue;
        }
        final resolved = pageUri.resolve(src).toString();
        if (seenImageUrls.add(resolved)) {
          blocks.add(NoticeImageBlock(resolved));
        }
      }

      final text = _normalizeText(node.text);
      if (_shouldKeepLine(text, seenTexts)) {
        blocks.add(NoticeTextBlock(text));
      }
    }

    if (blocks.isNotEmpty) {
      return blocks;
    }

    for (final line in root.text.split(RegExp(r'[\n\r]+'))) {
      final text = _normalizeText(line);
      if (_shouldKeepLine(text, seenTexts)) {
        blocks.add(NoticeTextBlock(text));
      }
    }

    return blocks;
  }

  String? _pickImageSource(Element image) {
    for (final key in const [
      'zoomfile',
      'data-original',
      'data-src',
      'data-actualsrc',
      'orisrc',
      '_src',
      'src',
    ]) {
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
      'form[name="_newscontent_fromname"]',
      '.conth',
      '.concon',
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
    final attachments = <CampusNoticeAttachment>[];
    final seen = <String>{};

    for (final link in root.querySelectorAll('a[href]')) {
      final href = link.attributes['href']?.trim() ?? '';
      if (href.isEmpty) {
        continue;
      }

      final resolved = pageUri.resolve(href).toString();
      final text = _normalizeText(link.text);
      if (!_looksLikeAttachmentLink(href: resolved, text: text) ||
          !seen.add(resolved)) {
        continue;
      }

      attachments.add(
        CampusNoticeAttachment(
          title: text.isEmpty ? '附件' : text,
          url: resolved,
        ),
      );
    }

    return attachments;
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

  bool _looksLikeDetailHref(String href) {
    final normalized = href.trim();
    return normalized.isNotEmpty && normalized.contains('info/');
  }

  String? _extractDateText(String text) {
    final match = RegExp(r'(\d{4}[/-]\d{2}[/-]\d{2})').firstMatch(text);
    return match?.group(1);
  }

  DateTime _parseDate(String value) {
    final parts = value.replaceAll('/', '-').trim().split('-');
    if (parts.length != 3) {
      throw ParsingFailure('研究生通知日期格式异常: $value');
    }
    return DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }

  String? _extractSummaryFromNode(
    Element node, {
    required String title,
    required String dateText,
  }) {
    for (final selector in const [
      '.zy',
      '.summary',
      '.desc',
      '.abstract',
      '.content',
      '.text',
      'p',
    ]) {
      for (final element in node.querySelectorAll(selector)) {
        final cleaned = _cleanSummaryText(
          _normalizeText(element.text),
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
    required String dateText,
  }) {
    var value = text.trim();
    if (value.isEmpty) {
      return null;
    }

    final normalizedTitle = _normalizeText(title);
    final normalizedDate = _normalizeText(dateText);
    if (normalizedTitle.isNotEmpty) {
      value = value.replaceAll(normalizedTitle, ' ');
    }
    if (normalizedDate.isNotEmpty) {
      value = value.replaceAll(normalizedDate, ' ');
    }

    value = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (value.isEmpty || value == normalizedTitle) {
      return null;
    }
    return value;
  }

  bool _shouldKeepLine(String text, Set<String> existing) {
    if (text.isEmpty || text.length < 2) {
      return false;
    }
    if (existing.contains(text)) {
      return false;
    }
    if (text.contains('点击数') || text.contains('上一条') || text.contains('下一条')) {
      return false;
    }
    existing.add(text);
    return true;
  }

  String _normalizeText(String value) {
    return value
        .replaceAll('\u00a0', ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\n\s+'), '\n')
        .trim();
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
