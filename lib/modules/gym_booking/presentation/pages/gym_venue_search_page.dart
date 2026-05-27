import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/di/app_providers.dart';
import '../../../../core/error/error_display.dart';
import '../../../../core/result/result.dart';
import '../../../../shared/widgets/constrained_body.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/surface_card.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../domain/entities/gym_booking_overview.dart';
import '../../domain/entities/gym_search_filter.dart';
import '../../domain/entities/gym_venue_search_page.dart' as domain;
import '../controllers/gym_booking_controller.dart';
import '../widgets/gym_booking_components.dart';

class GymVenueSearchPage extends ConsumerStatefulWidget {
  const GymVenueSearchPage({super.key, this.initialDate});

  final DateTime? initialDate;

  @override
  ConsumerState<GymVenueSearchPage> createState() => _GymVenueSearchPageState();
}

class _GymVenueSearchPageState extends ConsumerState<GymVenueSearchPage> {
  late final TextEditingController _keywordController;
  late DateTime _selectedDate;
  GymFilterOption? _selectedVenueType;
  GymFilterOption? _selectedSport;
  domain.GymVenueSearchPage? _page;
  Object? _error;
  bool _loading = false;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _selectedDate =
        widget.initialDate ?? DateTime(today.year, today.month, today.day);
    _keywordController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _search(reset: true);
    });
  }

  @override
  void dispose() {
    _keywordController.dispose();
    super.dispose();
  }

  Future<void> _search({required bool reset}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      setState(() {
        _loadingMore = true;
        _error = null;
      });
    }

    final authState = await ref.read(authControllerProvider.future);
    final session = authState.session;
    if (session == null) {
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = '当前未登录，无法搜索场地。';
      });
      return;
    }

    final pageNumber = reset ? 1 : (_page?.query.pageNumber ?? 1) + 1;
    final query = domain.GymVenueSearchQuery(
      date: _selectedDate,
      pageNumber: pageNumber,
      pageSize: 10,
      keyword: _keywordController.text.trim(),
      venueTypeId: _selectedVenueType?.id,
      venueTypeLabel: _selectedVenueType?.label,
      venueTypeBuilder: _selectedVenueType?.builder,
      venueTypeBuilderList: _selectedVenueType?.builderList,
      sportId: _selectedSport?.id,
      sportLabel: _selectedSport?.label,
      sportBuilder: _selectedSport?.builder,
      sportBuilderList: _selectedSport?.builderList,
    );

    final result = await ref.read(searchGymVenuesUseCaseProvider)(
      session: session,
      query: query,
    );

    if (!mounted) {
      return;
    }

    switch (result) {
      case Success<domain.GymVenueSearchPage>(data: final data):
        setState(() {
          if (reset || _page == null) {
            _page = data;
          } else {
            _page = _page!.copyWith(
              query: data.query,
              venues: [..._page!.venues, ...data.venues],
              slotsByVenue: {..._page!.slotsByVenue, ...data.slotsByVenue},
              totalSize: data.totalSize,
              fetchedAt: data.fetchedAt,
              origin: data.origin,
            );
          }
          _loading = false;
          _loadingMore = false;
        });
      case FailureResult<domain.GymVenueSearchPage>(failure: final failure):
        setState(() {
          _loading = false;
          _loadingMore = false;
          _error = failure;
        });
    }
  }

  Future<void> _refresh() => _search(reset: true);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final modelAsync = ref.watch(gymSearchModelProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('搜索场地')),
      body: ConstrainedBody(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 120),
            children: [
              SurfaceCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '筛选条件',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    GymDateSelector(
                      selectedDate: _selectedDate,
                      onDateChanged: (date) {
                        setState(() => _selectedDate = date);
                        _search(reset: true);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _keywordController,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        labelText: '搜索场地名称',
                        hintText: '例如：羽毛球、综合体育馆',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _keywordController.text.isEmpty
                            ? null
                            : IconButton(
                                onPressed: () {
                                  _keywordController.clear();
                                  setState(() {});
                                  _search(reset: true);
                                },
                                icon: const Icon(Icons.close_rounded),
                              ),
                      ),
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _search(reset: true),
                    ),
                    const SizedBox(height: 12),
                    _DetailedFilterCard(
                      modelAsync: modelAsync,
                      selectedVenueType: _selectedVenueType,
                      selectedSport: _selectedSport,
                      onVenueTypeSelected: (value) {
                        setState(() => _selectedVenueType = value);
                        _search(reset: true);
                      },
                      onSportSelected: (value) {
                        setState(() => _selectedSport = value);
                        _search(reset: true);
                      },
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              _keywordController.clear();
                              setState(() {
                                _selectedVenueType = null;
                                _selectedSport = null;
                              });
                              _search(reset: true);
                            },
                            child: const Text('清空条件'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => _search(reset: true),
                            child: const Text('开始搜索'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (_page != null)
                _SearchSummaryCard(page: _page!, loading: _loadingMore),
              if (_loading && _page == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null && _page == null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 48),
                  child: Center(
                    child: Text(
                      formatError(_error!).message,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              else if (_page != null && _page!.venues.isEmpty)
                const _SearchEmptyState()
              else ...[
                ...?_page?.venues.map((venue) {
                  final slots = _page?.slotsByVenue[venue.id] ?? const [];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _VenueSearchCard(
                      venue: venue,
                      slots: slots,
                      selectedDate: _selectedDate,
                    ),
                  );
                }),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      formatError(_error!).message,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                if (_page?.hasMore == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: FilledButton.tonal(
                      onPressed: _loadingMore
                          ? null
                          : () => _search(reset: false),
                      child: Text(_loadingMore ? '加载中...' : '加载更多'),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailedFilterCard extends StatelessWidget {
  const _DetailedFilterCard({
    required this.modelAsync,
    required this.selectedVenueType,
    required this.selectedSport,
    required this.onVenueTypeSelected,
    required this.onSportSelected,
  });

  final AsyncValue<GymSearchModel> modelAsync;
  final GymFilterOption? selectedVenueType;
  final GymFilterOption? selectedSport;
  final ValueChanged<GymFilterOption?> onVenueTypeSelected;
  final ValueChanged<GymFilterOption?> onSportSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = [
      if (selectedSport != null) '项目: ${selectedSport!.label}',
      if (selectedVenueType != null) '场馆: ${selectedVenueType!.label}',
    ].join('  /  ');

    return SurfaceCard(
      padding: EdgeInsets.zero,
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
          initiallyExpanded: selectedVenueType != null || selectedSport != null,
          leading: const Icon(Icons.tune_rounded),
          title: Text(
            '详细筛选',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          subtitle: Text(
            subtitle.isEmpty ? '按体育项目或场馆类型筛选' : subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          children: [
            switch (modelAsync) {
              AsyncData(:final value) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _FilterOptionGroup(
                    title: value.sportControl?.caption ?? '体育项目',
                    options: value.sports,
                    selected: selectedSport,
                    onSelected: onSportSelected,
                  ),
                  const SizedBox(height: 14),
                  _FilterOptionGroup(
                    title: value.venueTypeControl?.caption ?? '场馆类型',
                    options: value.venueTypes,
                    selected: selectedVenueType,
                    onSelected: onVenueTypeSelected,
                  ),
                ],
              ),
              AsyncError(:final error) => Text(
                formatError(error).message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
              _ => const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Center(child: CircularProgressIndicator()),
              ),
            },
          ],
        ),
      ),
    );
  }
}

class _FilterOptionGroup extends StatelessWidget {
  const _FilterOptionGroup({
    required this.title,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final String title;
  final List<GymFilterOption> options;
  final GymFilterOption? selected;
  final ValueChanged<GymFilterOption?> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        if (options.isEmpty)
          Text(
            '当前没有拿到候选项。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('全部'),
                selected: selected == null,
                onSelected: (_) => onSelected(null),
              ),
              ...options.map((option) {
                final isSelected = selected?.id == option.id;
                return ChoiceChip(
                  label: Text(option.label),
                  selected: isSelected,
                  onSelected: (_) => onSelected(isSelected ? null : option),
                );
              }),
            ],
          ),
      ],
    );
  }
}

class _SearchSummaryCard extends StatelessWidget {
  const _SearchSummaryCard({required this.page, required this.loading});

  final domain.GymVenueSearchPage page;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SurfaceCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '共 ${page.totalSize} 个场地',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            if (loading)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
      ),
    );
  }
}

class _VenueSearchCard extends StatelessWidget {
  const _VenueSearchCard({
    required this.venue,
    required this.slots,
    required this.selectedDate,
  });

  final Venue venue;
  final List<BookableSlot> slots;
  final DateTime selectedDate;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      venue.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (venue.address != null && venue.address!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        venue.address!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Text(
                slots.isEmpty ? '查看详情' : '${slots.length} 个时段',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (venue.venueType != null) _MetaChip(label: venue.venueType!),
              if (venue.sportName != null) _MetaChip(label: venue.sportName!),
              if (venue.capacity > 0)
                _MetaChip(label: '建议 ${venue.capacity} 人'),
              if (venue.openStatus != null) _MetaChip(label: venue.openStatus!),
            ],
          ),
          const SizedBox(height: 12),
          if (slots.isEmpty)
            Text(
              '进入详情页查看可约时段',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: slots
                  .take(6)
                  .map(
                    (slot) => _MetaChip(label: slot.timeLabel, primary: true),
                  )
                  .toList(),
            ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonal(
              onPressed: () => context.push(
                '/gym-booking/venue/${venue.id}'
                '?name=${Uri.encodeComponent(venue.name)}'
                '&bizWid=${Uri.encodeComponent(venue.bizWid)}'
                '&date=${DateFormat('yyyy-MM-dd').format(selectedDate)}',
              ),
              child: const Text('查看详情'),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label, this.primary = false});

  final String label;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: primary
            ? colorScheme.primaryContainer.withValues(alpha: 0.6)
            : colorScheme.secondaryContainer.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _SearchEmptyState extends StatelessWidget {
  const _SearchEmptyState();

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: EdgeInsets.zero,
      child: const EmptyState(
        title: '没有找到符合条件的场地',
        subtitle: '换个时间或去掉部分筛选条件试试。',
        mood: EmptyStateMood.empty,
      ),
    );
  }
}
