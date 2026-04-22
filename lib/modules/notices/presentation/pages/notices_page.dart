import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../shared/widgets/async_value_view.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../domain/entities/campus_notice.dart';
import '../controllers/graduate_notices_controller.dart';
import '../controllers/notices_controller.dart';
import '../models/notices_view_state.dart';

class NoticesPage extends ConsumerStatefulWidget {
  const NoticesPage({super.key});

  @override
  ConsumerState<NoticesPage> createState() => _NoticesPageState();
}

class _NoticesPageState extends ConsumerState<NoticesPage> {
  final ScrollController _scrollController = ScrollController();
  final Map<NoticeBoardSource, CampusNoticeCategory> _selectedCategories = {
    NoticeBoardSource.campus: CampusNoticeCategory.campusNotice,
    NoticeBoardSource.graduate: CampusNoticeCategory.graduateNoticeAnnouncement,
  };

  NoticeBoardSource _selectedSource = NoticeBoardSource.campus;
  bool _hasManuallySelectedSource = false;

  CampusNoticeCategory get _selectedCategory =>
      _selectedCategories[_activeSource]!;

  NoticeBoardSource get _activeSource {
    if (_hasManuallySelectedSource) {
      return _selectedSource;
    }

    final isAuthenticated =
        ref.read(authControllerProvider).asData?.value.isAuthenticated ?? false;
    return isAuthenticated ? _selectedSource : NoticeBoardSource.graduate;
  }

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
    if (maxScroll - currentScroll > 200) {
      return;
    }

    final feed = _currentState()?.feedFor(_selectedCategory);
    if (feed != null && feed.hasMore && !feed.isLoadingMore) {
      _loadNextPage();
    }
  }

  AsyncValue<NoticesState> _activeNoticesAsync() {
    return switch (_activeSource) {
      NoticeBoardSource.campus => ref.watch(noticesControllerProvider),
      NoticeBoardSource.graduate => ref.watch(
        graduateNoticesControllerProvider,
      ),
    };
  }

  NoticesState? _currentState() {
    return switch (_activeSource) {
      NoticeBoardSource.campus =>
        ref.read(noticesControllerProvider).asData?.value,
      NoticeBoardSource.graduate =>
        ref.read(graduateNoticesControllerProvider).asData?.value,
    };
  }

  Future<void> _refreshSelectedSource() {
    return switch (_activeSource) {
      NoticeBoardSource.campus =>
        ref.read(noticesControllerProvider.notifier).refresh(),
      NoticeBoardSource.graduate =>
        ref.read(graduateNoticesControllerProvider.notifier).refresh(),
    };
  }

  void _ensureCategoryLoaded() {
    switch (_activeSource) {
      case NoticeBoardSource.campus:
        ref
            .read(noticesControllerProvider.notifier)
            .ensureCategoryLoaded(_selectedCategory);
      case NoticeBoardSource.graduate:
        ref
            .read(graduateNoticesControllerProvider.notifier)
            .ensureCategoryLoaded(_selectedCategory);
    }
  }

  void _loadNextPage() {
    switch (_activeSource) {
      case NoticeBoardSource.campus:
        ref
            .read(noticesControllerProvider.notifier)
            .loadNextPage(_selectedCategory);
      case NoticeBoardSource.graduate:
        ref
            .read(graduateNoticesControllerProvider.notifier)
            .loadNextPage(_selectedCategory);
    }
  }

  void _toggleSource(NoticeBoardSource activeSource) {
    setState(() {
      _selectedSource = switch (activeSource) {
        NoticeBoardSource.campus => NoticeBoardSource.graduate,
        NoticeBoardSource.graduate => NoticeBoardSource.campus,
      };
      _hasManuallySelectedSource = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final authAsync = ref.watch(authControllerProvider);
    final isAuthenticated = authAsync.asData?.value.isAuthenticated ?? false;
    final activeSource = _hasManuallySelectedSource
        ? _selectedSource
        : (isAuthenticated ? _selectedSource : NoticeBoardSource.graduate);
    final noticesAsync = _activeNoticesAsync();
    final categories = CampusNoticeCategoryX.forBoard(activeSource);

    return Scaffold(
      appBar: AppBar(
        title: const Text('通知'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton.icon(
              onPressed: () => _toggleSource(activeSource),
              icon: const Icon(Icons.swap_horiz_rounded, size: 18),
              label: Text(switch (activeSource) {
                NoticeBoardSource.campus => '校级',
                NoticeBoardSource.graduate => '研究生',
              }),
            ),
          ),
        ],
      ),
      body: AsyncValueView(
        value: noticesAsync,
        onRetry: _refreshSelectedSource,
        loadingLabel: '通知同步中',
        dataBuilder: (state) {
          final feed = state.feedFor(_selectedCategory);
          final selectedLabel = state.labelFor(_selectedCategory);

          return RefreshIndicator(
            onRefresh: _refreshSelectedSource,
            child: CustomScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: _CategoryBar(
                      categories: categories,
                      state: state,
                      selectedCategory: _selectedCategory,
                      onSelected: (value) {
                        setState(() {
                          _selectedCategories[activeSource] = value;
                        });
                      },
                    ),
                  ),
                ),
                if (feed.isInitialLoading && feed.items.isEmpty)
                  const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (feed.items.isEmpty)
                  SliverFillRemaining(
                    child: Center(
                      child: _EmptyFeedState(
                        label: selectedLabel,
                        canSync:
                            !feed.isHydrated &&
                            feed.listPageUrl != null &&
                            feed.listPageUrl!.isNotEmpty,
                        isSyncing: feed.isInitialLoading,
                        onSync: _ensureCategoryLoaded,
                      ),
                    ),
                  )
                else ...[
                  SliverToBoxAdapter(
                    child: _FeedHeader(
                      source: activeSource,
                      feed: feed,
                      categoryLabel: selectedLabel,
                    ),
                  ),
                  SliverList.builder(
                    itemCount: feed.items.length,
                    itemBuilder: (context, index) {
                      final item = feed.items[index];
                      return Column(
                        children: [
                          _NoticeTile(
                            item: item,
                            onTap: () =>
                                context.push('/notices/detail', extra: item),
                          ),
                          if (index < feed.items.length - 1)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                              ),
                              child: Divider(
                                height: 1,
                                thickness: 1,
                                color: Theme.of(context)
                                    .colorScheme
                                    .outlineVariant
                                    .withValues(alpha: 0.5),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                  SliverToBoxAdapter(
                    child: _FeedFooter(
                      feed: feed,
                      onSync: _ensureCategoryLoaded,
                      onRetry: _loadNextPage,
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CategoryBar extends StatelessWidget {
  const _CategoryBar({
    required this.categories,
    required this.state,
    required this.selectedCategory,
    required this.onSelected,
  });

  final List<CampusNoticeCategory> categories;
  final NoticesState state;
  final CampusNoticeCategory selectedCategory;
  final ValueChanged<CampusNoticeCategory> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final category in categories) ...[
            _CategoryChip(
              label: state.labelFor(category),
              count: state.feedFor(category).items.length,
              selected: category == selectedCategory,
              onTap: () => onSelected(category),
            ),
            if (category != categories.last) const SizedBox(width: 10),
          ],
        ],
      ),
    );
  }
}

class _FeedHeader extends StatelessWidget {
  const _FeedHeader({
    required this.source,
    required this.feed,
    required this.categoryLabel,
  });

  final NoticeBoardSource source;
  final NoticeFeedState feed;
  final String categoryLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _HeaderTag(label: source.label),
              _HeaderTag(label: categoryLabel),
            ],
          ),
          if (feed.isInitialLoading && feed.items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '正在同步 $categoryLabel 最新列表',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          if (feed.errorMessage != null &&
              feed.errorMessage!.isNotEmpty &&
              feed.items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer.withValues(
                    alpha: 0.42,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  feed.errorMessage!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HeaderTag extends StatelessWidget {
  const _HeaderTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _FeedFooter extends StatelessWidget {
  const _FeedFooter({
    required this.feed,
    required this.onSync,
    required this.onRetry,
  });

  final NoticeFeedState feed;
  final VoidCallback onSync;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (feed.isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(20, 18, 20, 30),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2.2)),
      );
    }

    if (feed.loadMoreErrorMessage != null &&
        feed.loadMoreErrorMessage!.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
        child: Column(
          children: [
            Text(
              feed.loadMoreErrorMessage!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      );
    }

    if (!feed.isHydrated &&
        feed.listPageUrl != null &&
        feed.listPageUrl!.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
        child: Center(
          child: FilledButton.tonal(
            onPressed: feed.isInitialLoading ? null : onSync,
            child: Text(feed.isInitialLoading ? '同步中...' : '加载完整列表'),
          ),
        ),
      );
    }

    if (!feed.hasMore) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
        child: Center(
          child: Text(
            '没有更多了',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return const SizedBox(height: 24);
  }
}

class _EmptyFeedState extends StatelessWidget {
  const _EmptyFeedState({
    required this.label,
    required this.canSync,
    required this.isSyncing,
    required this.onSync,
  });

  final String label;
  final bool canSync;
  final bool isSyncing;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label暂无内容',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (canSync) ...[
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: isSyncing ? null : onSync,
              child: Text(isSyncing ? '同步中...' : '加载完整列表'),
            ),
          ],
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: selected ? colorScheme.primary : colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style:
                    Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: selected
                          ? colorScheme.onPrimary
                          : colorScheme.onSurface,
                      fontWeight: FontWeight.w800,
                    ) ??
                    const TextStyle(),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.18)
                      : colorScheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$count',
                  style:
                      Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: selected
                            ? colorScheme.onPrimary
                            : colorScheme.primary,
                        fontWeight: FontWeight.w800,
                      ) ??
                      const TextStyle(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoticeTile extends StatelessWidget {
  const _NoticeTile({required this.item, required this.onTap});

  final CampusNoticeItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final dateLabel = DateFormat('MM-dd').format(item.publishedAt);
    final summary = item.summary?.trim();

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                    ),
                  ),
                  if (summary != null && summary.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        height: 1.45,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            item.categoryLabel ?? item.category.defaultLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w600,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        dateLabel,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
