import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../shared/widgets/async_value_view.dart';
import '../../domain/entities/school_news.dart';
import '../controllers/school_news_controller.dart';
import '../models/school_news_feed_state.dart';

class SchoolNewsPage extends ConsumerStatefulWidget {
  const SchoolNewsPage({super.key});

  @override
  ConsumerState<SchoolNewsPage> createState() => _SchoolNewsPageState();
}

class _SchoolNewsPageState extends ConsumerState<SchoolNewsPage> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) {
      return;
    }

    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    if (maxScroll - currentScroll > 260) {
      return;
    }

    final feed = ref.read(schoolNewsControllerProvider).asData?.value;
    if (feed != null && feed.hasMore && !feed.isLoadingMore) {
      ref.read(schoolNewsControllerProvider.notifier).loadNextPage();
    }
  }

  Future<void> _refresh() {
    return ref.read(schoolNewsControllerProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final newsAsync = ref.watch(schoolNewsControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('学校要闻')),
      body: AsyncValueView(
        value: newsAsync,
        onRetry: _refresh,
        loadingLabel: '要闻同步中',
        dataBuilder: (state) {
          return RefreshIndicator(
            onRefresh: _refresh,
            child: CustomScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                if (state.items.isEmpty)
                  const SliverFillRemaining(
                    child: Center(child: Text('暂无学校要闻')),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                    sliver: SliverList.separated(
                      itemCount: state.items.length,
                      itemBuilder: (context, index) {
                        final item = state.items[index];
                        return _NewsArticleTile(
                          item: item,
                          featured: index == 0,
                          onTap: () =>
                              context.push('/school-news/detail', extra: item),
                        );
                      },
                      separatorBuilder: (context, index) => Divider(
                        height: 1,
                        color: Theme.of(
                          context,
                        ).colorScheme.outlineVariant.withValues(alpha: 0.56),
                      ),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: _NewsFeedFooter(
                    feed: state,
                    onRetry: () => ref
                        .read(schoolNewsControllerProvider.notifier)
                        .loadNextPage(),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _NewsArticleTile extends StatelessWidget {
  const _NewsArticleTile({
    required this.item,
    required this.featured,
    required this.onTap,
  });

  final SchoolNewsItem item;
  final bool featured;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final fullDateLabel = DateFormat(
      'yyyy-MM-dd',
      'zh_CN',
    ).format(item.publishedAt);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (featured) ...[
                    _FeaturedPill(color: colorScheme.primary),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    fullDateLabel,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                item.title,
                maxLines: featured ? 3 : 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  height: 1.36,
                ),
              ),
              if (item.summary != null && item.summary!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  item.summary!,
                  maxLines: featured ? 3 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    height: 1.55,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    '阅读全文',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 16,
                    color: colorScheme.primary,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeaturedPill extends StatelessWidget {
  const _FeaturedPill({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '最新',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _NewsFeedFooter extends StatelessWidget {
  const _NewsFeedFooter({required this.feed, required this.onRetry});

  final SchoolNewsFeedState feed;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (feed.isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 34),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2.2)),
      );
    }

    if (feed.loadMoreErrorMessage != null &&
        feed.loadMoreErrorMessage!.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 34),
        child: Column(
          children: [
            Text(
              feed.loadMoreErrorMessage!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.error,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 34),
      child: Center(
        child: Text(
          feed.hasMore ? '继续上滑加载更多' : '没有更多了',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
