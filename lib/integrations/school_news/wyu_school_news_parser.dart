import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import '../../core/error/failure.dart';
import '../../core/logging/app_logger.dart';
import '../../core/models/data_origin.dart';
import '../../modules/school_news/domain/entities/school_news.dart';

class WyuSchoolNewsParser {
  const WyuSchoolNewsParser();

  SchoolNewsPageData parsePage(
    String html, {
    required Uri pageUri,
    AppLogger? logger,
  }) {
    final document = html_parser.parse(html);
    final items = _parseItems(document, pageUri: pageUri);
    final pagination = _parsePagination(document, pageUri: pageUri);

    if (items.isEmpty) {
      throw const ParsingFailure('学校要闻解析失败，未找到新闻列表。');
    }

    logger?.info(
      '[SCHOOL_NEWS] 列表解析完成 page=${pagination.currentPage}/${pagination.totalPages} '
      'items=${items.length} hasMore=${pagination.nextPageUrl != null}',
    );

    return SchoolNewsPageData(
      pageUrl: pageUri.toString(),
      currentPage: pagination.currentPage,
      totalPages: pagination.totalPages,
      items: items,
      prevPageUrl: pagination.prevPageUrl,
      nextPageUrl: pagination.nextPageUrl,
      fetchedAt: DateTime.now(),
      origin: DataOrigin.remote,
    );
  }

  SchoolNewsDetail parseDetail({
    required String html,
    required Uri pageUri,
    required SchoolNewsItem item,
    AppLogger? logger,
  }) {
    final document = html_parser.parse(html);
    final title = _extractDetailTitle(document) ?? item.title;
    final meta = _extractDetailMeta(document);
    final contentRoot = _findContentRoot(document);
    final contentBlocks = _extractContentBlocks(contentRoot, pageUri);

    if (contentBlocks.isEmpty) {
      throw const ParsingFailure('学校要闻正文解析失败，未找到有效内容。');
    }

    logger?.info(
      '[SCHOOL_NEWS] 详情解析完成 title=$title '
      'texts=${contentBlocks.whereType<SchoolNewsTextBlock>().length} '
      'images=${contentBlocks.whereType<SchoolNewsImageBlock>().length}',
    );

    return SchoolNewsDetail(
      item: item,
      title: title,
      metaLines: meta.lines,
      source: meta.source,
      contentBlocks: contentBlocks,
      fetchedAt: DateTime.now(),
      origin: DataOrigin.remote,
    );
  }

  List<SchoolNewsItem> _parseItems(Document document, {required Uri pageUri}) {
    final anchors = document.querySelectorAll('.ul-list-e1 a.con[href]');
    final candidates = anchors.isNotEmpty
        ? anchors
        : document.querySelectorAll('a.con[href]');
    final items = <SchoolNewsItem>[];
    final seen = <String>{};

    for (final anchor in candidates) {
      final href = anchor.attributes['href'] ?? '';
      if (href.trim().isEmpty) {
        continue;
      }

      final title = _normalizeText(
        anchor.querySelector('.tit')?.text ??
            anchor.attributes['title'] ??
            anchor.text,
      );
      final dateText = _extractDateText(anchor);
      if (title.isEmpty || dateText == null) {
        continue;
      }

      final detailUri = pageUri.resolve(href);
      final id = _extractId(detailUri);
      final item = SchoolNewsItem(
        id: id,
        title: title,
        summary: _cleanSummary(anchor.querySelector('.desc')?.text),
        publishedAt: _parseDate(dateText),
        detailUrl: detailUri.toString(),
      );
      if (!seen.add(item.cacheKey)) {
        continue;
      }
      items.add(item);
    }

    return items;
  }

  String? _extractDateText(Element anchor) {
    final mobileDate = _normalizeText(anchor.querySelector('.date-m')?.text);
    final mobileMatch = RegExp(
      r'\d{4}[/-]\d{2}[/-]\d{2}',
    ).firstMatch(mobileDate);
    if (mobileMatch != null) {
      return mobileMatch.group(0);
    }

    final yearMonth = _normalizeText(anchor.querySelector('.date .yue')?.text);
    final day = _normalizeText(anchor.querySelector('.date .ri')?.text);
    if (RegExp(r'^\d{4}[/-]\d{2}$').hasMatch(yearMonth) &&
        RegExp(r'^\d{1,2}$').hasMatch(day)) {
      return '$yearMonth-${day.padLeft(2, '0')}';
    }

    final fallback = _normalizeText(anchor.text);
    return RegExp(r'\d{4}[/-]\d{2}[/-]\d{2}').firstMatch(fallback)?.group(0);
  }

  DateTime _parseDate(String value) {
    final normalized = value.replaceAll('/', '-').trim();
    final parts = normalized.split('-');
    if (parts.length != 3) {
      throw ParsingFailure('学校要闻日期格式异常: $value');
    }
    return DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }

  _PaginationInfo _parsePagination(Document document, {required Uri pageUri}) {
    final paginationRoot = document.querySelector('.pb_sys_common');
    if (paginationRoot == null) {
      return const _PaginationInfo(currentPage: 1, totalPages: 1);
    }

    final currentPage =
        int.tryParse(
          _normalizeText(paginationRoot.querySelector('.p_no_d')?.text),
        ) ??
        1;
    var totalPages = currentPage;

    for (final anchor in paginationRoot.querySelectorAll('a[href]')) {
      final textCandidate = int.tryParse(_normalizeText(anchor.text));
      if (textCandidate != null && textCandidate > totalPages) {
        totalPages = textCandidate;
      }
    }

    final prevHref = paginationRoot
        .querySelector('.p_prev a[href]')
        ?.attributes['href'];
    final nextHref = paginationRoot
        .querySelector('.p_next a[href]')
        ?.attributes['href'];

    return _PaginationInfo(
      currentPage: currentPage,
      totalPages: totalPages,
      prevPageUrl: _resolveOptional(pageUri, prevHref),
      nextPageUrl: _resolveOptional(pageUri, nextHref),
    );
  }

  String? _resolveOptional(Uri baseUri, String? href) {
    final value = href?.trim() ?? '';
    if (value.isEmpty) {
      return null;
    }
    return baseUri.resolve(value).toString();
  }

  String _extractId(Uri detailUri) {
    final last = detailUri.pathSegments.isEmpty
        ? ''
        : detailUri.pathSegments.last;
    return last.replaceAll(RegExp(r'\.html?$'), '');
  }

  String _normalizeText(String? value) {
    return (value ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String? _cleanSummary(String? value) {
    final normalized = _normalizeText(value);
    if (normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  String? _extractDetailTitle(Document document) {
    const selectors = ['.m-txtbodydeatil h1', 'h1'];
    for (final selector in selectors) {
      final text = _normalizeText(document.querySelector(selector)?.text);
      if (text.isNotEmpty) {
        return text;
      }
    }

    final metaTitle = _normalizeText(
      document.querySelector('meta[name="pageTitle"]')?.attributes['content'],
    );
    if (metaTitle.isNotEmpty) {
      return metaTitle;
    }

    final pageTitle = _normalizeText(document.querySelector('title')?.text);
    if (pageTitle.isEmpty) {
      return null;
    }
    return pageTitle.replaceFirst(RegExp(r'-五邑大学$'), '').trim();
  }

  _DetailMeta _extractDetailMeta(Document document) {
    final info = document.querySelector('.m-txtbodydeatil .info');
    if (info == null) {
      return const _DetailMeta(lines: []);
    }

    final raw = _normalizeText(
      info.text,
    ).replaceAll(RegExp(r'点击数：.*?次'), '').trim();
    final lines = <String>[];

    final publishedMatch = RegExp(r'发布时间[:：]\s*([0-9/-]+)').firstMatch(raw);
    if (publishedMatch != null) {
      lines.add('发布时间：${publishedMatch.group(1)}');
    }

    final sourceMatch = RegExp(r'发布单位[:：]\s*([^\s]+)').firstMatch(raw);
    final source = sourceMatch?.group(1)?.trim();
    if (source != null && source.isNotEmpty) {
      lines.add('发布单位：$source');
    }

    if (lines.isEmpty && raw.isNotEmpty) {
      lines.add(raw);
    }

    return _DetailMeta(lines: lines, source: source);
  }

  Element _findContentRoot(Document document) {
    final root =
        document.querySelector('.v_news_content') ??
        document.querySelector('#vsb_content_2') ??
        document.querySelector('.m-txtbodydeatil .desc');
    if (root == null) {
      throw const ParsingFailure('学校要闻正文解析失败，正文容器缺失。');
    }
    return root;
  }

  List<SchoolNewsContentBlock> _extractContentBlocks(
    Element root,
    Uri pageUri,
  ) {
    final blocks = <SchoolNewsContentBlock>[];
    for (final child in root.children) {
      _appendContentBlocks(child, pageUri, blocks);
    }

    if (blocks.isEmpty) {
      final text = _cleanContentText(root.text);
      if (text != null) {
        blocks.add(SchoolNewsTextBlock(text: text));
      }
    }

    return blocks;
  }

  void _appendContentBlocks(
    Element element,
    Uri pageUri,
    List<SchoolNewsContentBlock> blocks,
  ) {
    final tag = element.localName?.toLowerCase() ?? '';
    if (tag == 'script' || tag == 'style' || tag == 'link') {
      return;
    }

    if (tag == 'img') {
      final image = _buildImageBlock(element, pageUri);
      if (image != null) {
        blocks.add(image);
      }
      return;
    }

    if (tag == 'p' || tag == 'li') {
      final text = _cleanContentText(element.text);
      if (text != null) {
        blocks.add(SchoolNewsTextBlock(text: text));
      }
      for (final imageNode in element.querySelectorAll('img')) {
        final image = _buildImageBlock(imageNode, pageUri);
        if (image != null) {
          blocks.add(image);
        }
      }
      return;
    }

    if (element.children.isNotEmpty) {
      for (final child in element.children) {
        _appendContentBlocks(child, pageUri, blocks);
      }
      return;
    }

    final text = _cleanContentText(element.text);
    if (text != null) {
      blocks.add(SchoolNewsTextBlock(text: text));
    }
  }

  SchoolNewsImageBlock? _buildImageBlock(Element imageNode, Uri pageUri) {
    final rawUrl =
        imageNode.attributes['src'] ??
        imageNode.attributes['orisrc'] ??
        imageNode.attributes['vurl'] ??
        '';
    final url = rawUrl.trim();
    if (url.isEmpty) {
      return null;
    }

    final alt = _normalizeText(
      imageNode.attributes['alt'] ?? imageNode.attributes['title'],
    );
    return SchoolNewsImageBlock(
      url: pageUri.resolve(url).toString(),
      alt: alt.isEmpty ? null : alt,
    );
  }

  String? _cleanContentText(String? value) {
    final normalized = _normalizeText(value);
    if (normalized.isEmpty || normalized == '\u00a0') {
      return null;
    }
    return normalized;
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

class _DetailMeta {
  const _DetailMeta({required this.lines, this.source});

  final List<String> lines;
  final String? source;
}
