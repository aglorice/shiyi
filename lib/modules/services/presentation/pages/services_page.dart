import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/widgets/async_value_view.dart';
import '../../../../shared/widgets/constrained_body.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../domain/entities/service_card_data.dart';
import '../controllers/services_controller.dart';

class ServicesPage extends ConsumerWidget {
  const ServicesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servicesAsync = ref.watch(servicesControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('校园服务')),
      body: ConstrainedBody(
        child: AsyncValueView(
          value: servicesAsync,
          onRetry: () =>
              ref.read(servicesControllerProvider.notifier).refresh(),
          loadingLabel: '加载服务列表',
          dataBuilder: (state) {
            if (state.groups.isEmpty) {
              return const EmptyState(
                title: '暂无服务',
                subtitle: '可能是这个学期还没开放，可以下拉刷新一次。',
                mood: EmptyStateMood.empty,
              );
            }
            return RefreshIndicator(
              onRefresh: () =>
                  ref.read(servicesControllerProvider.notifier).refresh(),
              child: _GroupsView(state: state),
            );
          },
        ),
      ),
    );
  }
}

class _GroupsView extends StatelessWidget {
  const _GroupsView({required this.state});

  final ServicesState state;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        if (state.groups.length == 1)
          _GroupTabView(group: state.groups.first, servicesState: state)
        else
          for (final group in state.groups) ...[
            _GroupSection(group: group, servicesState: state),
            const SizedBox(height: 24),
          ],
      ],
    );
  }
}

class _GroupSection extends StatelessWidget {
  const _GroupSection({required this.group, required this.servicesState});

  final ServiceCardGroup group;
  final ServicesState servicesState;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            group.cardName,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(height: 12),
        _GroupTabView(group: group, servicesState: servicesState),
      ],
    );
  }
}

class _GroupTabView extends ConsumerStatefulWidget {
  const _GroupTabView({required this.group, required this.servicesState});

  final ServiceCardGroup group;
  final ServicesState servicesState;

  @override
  ConsumerState<_GroupTabView> createState() => _GroupTabViewState();
}

class _GroupTabViewState extends ConsumerState<_GroupTabView> {
  String? _selectedTypeId;
  double _dragStartX = 0;

  @override
  void initState() {
    super.initState();
    _selectedTypeId = widget.group.categories.isEmpty
        ? null
        : widget.group.categories.first.typeId;
    _scheduleSelectedCategoryLoad();
  }

  @override
  void didUpdateWidget(covariant _GroupTabView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.group.categories.isEmpty) {
      _selectedTypeId = null;
      return;
    }

    final stillExists = widget.group.categories.any(
      (item) => item.typeId == _selectedTypeId,
    );
    if (!stillExists) {
      _selectedTypeId = widget.group.categories.first.typeId;
    }
    _scheduleSelectedCategoryLoad();
  }

  void _selectCategory(String typeId) {
    final categories = widget.group.categories;
    final newIndex = categories.indexWhere((c) => c.typeId == typeId);
    if (newIndex < 0 || typeId == _selectedTypeId) return;

    setState(() {
      _selectedTypeId = typeId;
    });
    _scheduleSelectedCategoryLoad();
  }

  void _onHorizontalDragStart(DragStartDetails details) {
    _dragStartX = details.globalPosition.dx;
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    final categories = widget.group.categories;
    if (categories.length < 2) return;

    final dx = details.globalPosition.dx - _dragStartX;
    if (dx.abs() < 40) return;

    final currentIndex = categories.indexWhere(
      (c) => c.typeId == _selectedTypeId,
    );
    if (currentIndex < 0) return;

    if (dx < 0 && currentIndex < categories.length - 1) {
      _selectCategory(categories[currentIndex + 1].typeId);
    } else if (dx > 0 && currentIndex > 0) {
      _selectCategory(categories[currentIndex - 1].typeId);
    }
  }

  void _scheduleSelectedCategoryLoad({bool forceRefresh = false}) {
    final selectedCategory = _currentCategory();
    if (selectedCategory == null) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      ref
          .read(servicesControllerProvider.notifier)
          .ensureCategoryLoaded(
            widget.group,
            selectedCategory,
            forceRefresh: forceRefresh,
          );
    });
  }

  ServiceCategory? _currentCategory() {
    final categories = widget.group.categories;
    if (categories.isEmpty) {
      return null;
    }

    for (final category in categories) {
      if (category.typeId == _selectedTypeId) {
        return category;
      }
    }
    return categories.first;
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.group;

    if (group.categories.isEmpty) {
      return _ItemsGrid(items: group.items);
    }

    final selectedCategory = _currentCategory()!;
    final selectedItems = group.itemsForCategory(selectedCategory);
    final isLoading = widget.servicesState.isCategoryLoading(
      group,
      selectedCategory,
    );
    final errorMessage = widget.servicesState.categoryError(
      group,
      selectedCategory,
    );

    if (group.categories.length == 1) {
      return _CategoryItemsPane(
        items: selectedItems,
        isLoading: isLoading,
        errorMessage: errorMessage,
        onRetry: () => _scheduleSelectedCategoryLoad(forceRefresh: true),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final category in group.categories) ...[
                _ServiceCategoryChip(
                  category: category,
                  count: group.categoryCount(category),
                  selected: category.typeId == selectedCategory.typeId,
                  onTap: () => _selectCategory(category.typeId),
                ),
                const SizedBox(width: 10),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onHorizontalDragStart: _onHorizontalDragStart,
          onHorizontalDragEnd: _onHorizontalDragEnd,
          child: _CategoryItemsPane(
            items: selectedItems,
            isLoading: isLoading,
            errorMessage: errorMessage,
            onRetry: () => _scheduleSelectedCategoryLoad(forceRefresh: true),
          ),
        ),
      ],
    );
  }
}

class _CategoryItemsPane extends StatelessWidget {
  const _CategoryItemsPane({
    required this.items,
    required this.isLoading,
    required this.errorMessage,
    required this.onRetry,
  });

  final List<ServiceItem> items;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (items.isNotEmpty) {
      return _ItemsGrid(items: items);
    }

    if (isLoading) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 26),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    if (errorMessage != null && errorMessage!.isNotEmpty) {
      return _CategoryPlaceholder(
        message: errorMessage!,
        actionLabel: '重试',
        onTap: onRetry,
      );
    }

    return const _CategoryPlaceholder(message: '这个分类下暂时没有解析到服务项。');
  }
}

class _ItemsGrid extends StatelessWidget {
  const _ItemsGrid({required this.items});

  final List<ServiceItem> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const columns = 4;
        const spacing = 8.0;
        final cellWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final item in items)
              SizedBox(
                width: cellWidth,
                child: _ServiceChip(
                  item: item,
                  onTap: () => context.push('/services/webview', extra: item),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _CategoryPlaceholder extends StatelessWidget {
  const _CategoryPlaceholder({
    required this.message,
    this.actionLabel,
    this.onTap,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (actionLabel != null && onTap != null) ...[
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: onTap, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

class _ServiceCategoryChip extends StatelessWidget {
  const _ServiceCategoryChip({
    required this.category,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final ServiceCategory category;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: selected ? colorScheme.primary : colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                category.typeName,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? colorScheme.onPrimary
                      : colorScheme.onSurface,
                ),
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
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: selected
                        ? colorScheme.onPrimary
                        : colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ServiceChip extends StatelessWidget {
  const _ServiceChip({required this.item, required this.onTap});

  final ServiceItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(
                  alpha: 0.6,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: item.iconLink != null && item.iconLink!.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.network(
                        item.iconLink!,
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Icon(
                          Icons.apps,
                          color: theme.colorScheme.primary,
                          size: 24,
                        ),
                      ),
                    )
                  : Icon(
                      Icons.apps,
                      color: theme.colorScheme.primary,
                      size: 24,
                    ),
            ),
            const SizedBox(height: 6),
            Text(
              item.appName,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
