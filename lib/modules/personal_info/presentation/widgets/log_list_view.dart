import 'package:flutter/material.dart';

import '../../../../app/theme/design_tokens.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/module_error_state.dart';
import '../../domain/entities/user_log_entry.dart';
import '../controllers/user_logs_controller.dart';

/// 通用「下拉刷新 + 滚动到底自动加载下一页」的日志列表。
///
/// 调用方传入当前 [PagedLogState] 与 refresh / loadMore 回调，
/// 由 widget 监听滚动并在接近底部时调 onLoadMore。
class LogListView extends StatefulWidget {
  const LogListView({
    super.key,
    required this.state,
    required this.onRefresh,
    required this.onLoadMore,
    required this.itemBuilder,
    this.emptyHint = '暂无记录',
  });

  final PagedLogState state;
  final Future<void> Function() onRefresh;
  final void Function() onLoadMore;
  final Widget Function(BuildContext context, UserLogEntry entry) itemBuilder;
  final String emptyHint;

  @override
  State<LogListView> createState() => _LogListViewState();
}

class _LogListViewState extends State<LogListView> {
  final _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    final pos = _controller.position;
    if (pos.pixels >= pos.maxScrollExtent - 240) {
      widget.onLoadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final theme = Theme.of(context);

    if (state.loading && state.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null && state.items.isEmpty) {
      return ModuleErrorState(
        message: state.error!,
        onRetry: widget.onRefresh,
      );
    }
    if (state.items.isEmpty) {
      return RefreshIndicator(
        onRefresh: widget.onRefresh,
        child: ListView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.pageH,
            vertical: AppSpacing.lg,
          ),
          children: [
            const SizedBox(height: 24),
            EmptyState(
              title: widget.emptyHint,
              subtitle: '下拉一次试试，新的记录会出现在这里。',
              mood: EmptyStateMood.empty,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView.separated(
        controller: _controller,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.pageH,
          AppSpacing.sm,
          AppSpacing.pageH,
          AppSpacing.pageBottomGap,
        ),
        itemCount: state.items.length + 1,
        separatorBuilder: (_, __) => Divider(
          height: 0.6,
          thickness: 0.6,
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
          indent: 32,
        ),
        itemBuilder: (context, index) {
          if (index < state.items.length) {
            return widget.itemBuilder(context, state.items[index]);
          }
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: Center(
              child: state.hasMore
                  ? (state.loadingMore
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.colorScheme.outline,
                          ),
                        )
                      : Text(
                          '上拉加载更多',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ))
                  : Text(
                      '— 已经到底了 · 共 ${state.total} 条 —',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
            ),
          );
        },
      ),
    );
  }
}
