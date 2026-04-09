import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/di/app_providers.dart';
import '../../../../app/settings/app_preferences.dart';
import '../../../../app/settings/app_preferences_controller.dart';
import '../../../../core/error/error_display.dart';
import '../../../../core/result/result.dart';
import '../../../../shared/widgets/async_value_view.dart';
import '../../../../shared/widgets/surface_card.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../domain/entities/gym_booking_overview.dart';
import '../../domain/entities/gym_recommendation.dart';
import '../../domain/entities/gym_search_filter.dart';
import '../../domain/entities/gym_venue_search_page.dart' as search;
import '../controllers/gym_booking_controller.dart';
import '../widgets/gym_booking_components.dart';

class GymBookingPage extends ConsumerWidget {
  const GymBookingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overviewAsync = ref.watch(gymBookingControllerProvider);
    final controller = ref.read(gymBookingControllerProvider.notifier);
    final selectedDate = controller.selectedDate;
    final preferences = ref.watch(appPreferencesControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('体育场预约'),
        actions: [
          IconButton(
            tooltip: '预约偏好',
            onPressed: () => context.push('/gym-booking/profile'),
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
      body: AsyncValueView(
        value: overviewAsync,
        onRetry: controller.refresh,
        loadingLabel: '同步体育场预约信息',
        dataBuilder: (overview) {
          return RefreshIndicator(
            onRefresh: controller.refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
              children: [
                _OverviewHero(
                  overview: overview,
                  selectedDate: selectedDate,
                  onDateChanged: controller.changeDate,
                ),
                const SizedBox(height: 14),
                _QuickActions(selectedDate: selectedDate),
                const SizedBox(height: 14),
                _RecommendationSection(
                  selectedDate: selectedDate,
                  preferences: preferences,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _OverviewHero extends ConsumerWidget {
  const _OverviewHero({
    required this.overview,
    required this.selectedDate,
    required this.onDateChanged,
  });

  final GymBookingOverview overview;
  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final phone = ref.watch(appPreferencesControllerProvider).gymPhoneNumber;
    final selectedSlots = _slotsForDate(overview, selectedDate);
    final selectedVenues = selectedSlots.keys.length;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          colors: [
            colorScheme.primary,
            Color.lerp(colorScheme.primary, colorScheme.tertiary, 0.38) ??
                colorScheme.tertiary,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '预约概览',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              overview.rule.summary,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white.withValues(alpha: 0.86),
                height: 1.45,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _HeroStat(label: '当日场地', value: '$selectedVenues'),
                _HeroStat(
                  label: '开放时段',
                  value:
                      '${selectedSlots.values.fold<int>(0, (sum, slots) => sum + slots.length)}',
                ),
                _HeroStat(
                  label: '已存手机号',
                  value: phone?.isNotEmpty == true ? '已保存' : '未设置',
                ),
              ],
            ),
            const SizedBox(height: 16),
            GymDateSelector(
              selectedDate: selectedDate,
              dayCount: overview.rule.advanceWindowDays.clamp(3, 7),
              onDateChanged: onDateChanged,
            ),
          ],
        ),
      ),
    );
  }

  Map<String, List<BookableSlot>> _slotsForDate(
    GymBookingOverview overview,
    DateTime selectedDate,
  ) {
    final normalized = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
    );
    final result = <String, List<BookableSlot>>{};
    for (final entry in overview.slotsByVenue.entries) {
      final filtered = entry.value
          .where(
            (slot) =>
                DateTime(slot.date.year, slot.date.month, slot.date.day) ==
                normalized,
          )
          .toList();
      if (filtered.isNotEmpty) {
        result[entry.key] = filtered;
      }
    }
    return result;
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.78),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.selectedDate});

  final DateTime selectedDate;

  @override
  Widget build(BuildContext context) {
    final formattedDate = DateFormat('yyyy-MM-dd').format(selectedDate);

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _ActionCard(
          title: '预约新场地',
          subtitle: '进入搜索、筛选和分页浏览',
          icon: Icons.travel_explore_rounded,
          color: const Color(0xFF2D8C8F),
          onTap: () => context.push('/gym-booking/search?date=$formattedDate'),
        ),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: MediaQuery.sizeOf(context).width > 480
          ? (MediaQuery.sizeOf(context).width - 52) / 2
          : double.infinity,
      child: SurfaceCard(
        padding: const EdgeInsets.all(0),
        child: InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, color: color),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_rounded,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecommendationSection extends ConsumerStatefulWidget {
  const _RecommendationSection({
    required this.selectedDate,
    required this.preferences,
  });

  final DateTime selectedDate;
  final AppPreferences preferences;

  @override
  ConsumerState<_RecommendationSection> createState() =>
      _RecommendationSectionState();
}

class _RecommendationSectionState
    extends ConsumerState<_RecommendationSection> {
  GymRecommendationSnapshot? _snapshot;
  Object? _error;
  bool _loadingCache = true;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCache();
    });
  }

  @override
  void didUpdateWidget(covariant _RecommendationSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_cacheKey(oldWidget.selectedDate, oldWidget.preferences) !=
        _cacheKey(widget.selectedDate, widget.preferences)) {
      _loadCache();
    }
  }

  Future<void> _loadCache() async {
    setState(() {
      _loadingCache = true;
      _error = null;
    });

    final cached = await ref
        .read(jsonCacheStoreProvider)
        .readMap(_cacheKey(widget.selectedDate, widget.preferences));

    if (!mounted) {
      return;
    }

    setState(() {
      _snapshot = cached == null
          ? GymRecommendationSnapshot(
              date: _normalizeDate(widget.selectedDate),
              items: const [],
              preferenceSummary: _preferenceSummary(widget.preferences),
            )
          : GymRecommendationSnapshot.fromJson(cached);
      _loadingCache = false;
    });
  }

  Future<void> _refreshRecommendations() async {
    if (_refreshing) {
      return;
    }

    setState(() {
      _refreshing = true;
      _error = null;
    });

    final session = (await ref.read(authControllerProvider.future)).session;
    if (session == null) {
      if (!mounted) {
        return;
      }
      setState(() {
        _refreshing = false;
        _error = '当前未登录，无法生成推荐。';
      });
      return;
    }

    if ((widget.preferences.gymPhoneNumber ?? '').trim().isEmpty) {
      if (!mounted) {
        return;
      }
      setState(() {
        _refreshing = false;
        _error = '请先在右上角偏好页设置预约手机号。';
      });
      return;
    }

    if (widget.preferences.gymPreferredSportId == null &&
        widget.preferences.gymPreferredVenueTypeId == null &&
        widget.preferences.gymTimePreference == null) {
      if (!mounted) {
        return;
      }
      setState(() {
        _refreshing = false;
        _error = '请先设置至少一个推荐偏好。';
      });
      return;
    }

    final modelResult = await ref.read(fetchGymSearchModelUseCaseProvider)(
      session: session,
    );
    if (modelResult case FailureResult<GymSearchModel>(
      failure: final failure,
    )) {
      if (!mounted) {
        return;
      }
      setState(() {
        _refreshing = false;
        _error = failure;
      });
      return;
    }

    final model = modelResult.dataOrNull!;
    final sportOption = _findOption(
      model.sports,
      widget.preferences.gymPreferredSportId,
    );
    final venueTypeOption = _findOption(
      model.venueTypes,
      widget.preferences.gymPreferredVenueTypeId,
    );

    final searchUseCase = ref.read(searchGymVenuesUseCaseProvider);
    final gateway = ref.read(schoolPortalGatewayProvider);
    final items = <GymRecommendationItem>[];
    final mergedSlots = <String, Map<String, BookableSlot>>{};
    final mergedVenues = <String, Venue>{};
    var pageNumber = 1;

    while (true) {
      final query = search.GymVenueSearchQuery(
        date: _normalizeDate(widget.selectedDate),
        pageNumber: pageNumber,
        pageSize: 50,
        venueTypeId: venueTypeOption?.id,
        venueTypeLabel: venueTypeOption?.label,
        venueTypeBuilder: venueTypeOption?.builder,
        venueTypeBuilderList: venueTypeOption?.builderList,
        sportId: sportOption?.id,
        sportLabel: sportOption?.label,
        sportBuilder: sportOption?.builder,
        sportBuilderList: sportOption?.builderList,
      );
      final pageResult = await searchUseCase(session: session, query: query);
      if (pageResult case FailureResult<search.GymVenueSearchPage>(
        failure: final failure,
      )) {
        if (!mounted) {
          return;
        }
        setState(() {
          _refreshing = false;
          _error = failure;
        });
        return;
      }

      final page = pageResult.dataOrNull!;
      for (final venue in page.venues) {
        mergedVenues[venue.id] = venue;
        final current = mergedSlots.putIfAbsent(venue.id, () => {});
        for (final slot
            in page.slotsByVenue[venue.id] ?? const <BookableSlot>[]) {
          if (!_matchesTimePreference(
            slot,
            widget.preferences.gymTimePreference,
          )) {
            continue;
          }
          current[slot.timeLabel] = slot;
        }
      }

      if (!page.hasMore) {
        break;
      }
      pageNumber += 1;
    }

    final sortedVenues = mergedVenues.values.toList()
      ..sort((left, right) => left.name.compareTo(right.name));

    for (final venue in sortedVenues) {
      final candidateSlots = mergedSlots[venue.id]?.values.toList() ?? const [];
      if (candidateSlots.isEmpty) {
        continue;
      }

      final availableSlots = <BookableSlot>[];
      for (final slot in candidateSlots) {
        final eligibility = await gateway.checkGymBookingEligibility(
          session,
          draft: BookingDraft(
            venue: venue,
            slot: slot,
            attendeeName: session.displayName,
            date: _normalizeDate(widget.selectedDate),
            userAccount: session.userId,
            phone: widget.preferences.gymPhoneNumber,
            bizWid: venue.bizWid,
          ),
        );
        if (eligibility case Success<GymBookingEligibility>(data: final data)) {
          if (data.canApply) {
            availableSlots.add(slot);
          }
        }
      }

      if (availableSlots.isNotEmpty) {
        items.add(
          GymRecommendationItem(
            venue: venue,
            slots: availableSlots
              ..sort((a, b) => a.startTime.compareTo(b.startTime)),
          ),
        );
      }
    }

    items.sort(
      (left, right) => right.slots.length.compareTo(left.slots.length),
    );

    final snapshot = GymRecommendationSnapshot(
      date: _normalizeDate(widget.selectedDate),
      items: items,
      preferenceSummary: _preferenceSummary(widget.preferences),
      fetchedAt: DateTime.now(),
    );

    await ref
        .read(jsonCacheStoreProvider)
        .writeMap(
          _cacheKey(widget.selectedDate, widget.preferences),
          snapshot.toJson(),
        );

    if (!mounted) {
      return;
    }
    setState(() {
      _snapshot = snapshot;
      _refreshing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final snapshot = _snapshot;

    return SurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '为你推荐',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                tooltip: '刷新推荐',
                onPressed: _refreshing ? null : _refreshRecommendations,
                icon: _refreshing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          Text(
            snapshot?.preferenceSummary.isNotEmpty == true
                ? snapshot!.preferenceSummary
                : '设置偏好后，点击刷新为你筛选可约场地。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (snapshot?.fetchedAt != null) ...[
            const SizedBox(height: 6),
            Text(
              '缓存更新于 ${DateFormat('MM-dd HH:mm').format(snapshot!.fetchedAt!.toLocal())}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (_loadingCache)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (_error != null)
            _EmptyHint(
              icon: Icons.sync_problem_rounded,
              text: formatError(_error!).message,
            )
          else if (snapshot == null || snapshot.items.isEmpty)
            const _EmptyHint(
              icon: Icons.auto_awesome_outlined,
              text: '还没有推荐缓存，点右上角刷新后按偏好生成。',
            )
          else
            ...snapshot.items.take(6).map((item) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _RecommendedVenueCard(
                  venue: item.venue,
                  slots: item.slots,
                  selectedDate: widget.selectedDate,
                ),
              );
            }),
        ],
      ),
    );
  }

  GymFilterOption? _findOption(List<GymFilterOption> options, String? id) {
    if (id == null || id.isEmpty) {
      return null;
    }
    for (final option in options) {
      if (option.id == id) {
        return option;
      }
    }
    return null;
  }

  bool _matchesTimePreference(
    BookableSlot slot,
    GymTimePreference? preference,
  ) {
    if (preference == null) {
      return true;
    }
    final hour = int.tryParse(slot.startTime.split(':').first) ?? 0;
    return switch (preference) {
      GymTimePreference.morning => hour < 12,
      GymTimePreference.afternoon => hour >= 12 && hour < 18,
      GymTimePreference.evening => hour >= 18,
    };
  }

  DateTime _normalizeDate(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  String _cacheKey(DateTime date, AppPreferences preferences) {
    final normalized = _normalizeDate(date);
    final dateKey = DateFormat('yyyyMMdd').format(normalized);
    final signature = [
      preferences.gymPreferredSportId ?? 'all-sport',
      preferences.gymPreferredVenueTypeId ?? 'all-venue',
      preferences.gymTimePreference?.name ?? 'all-time',
    ].join('_');
    return 'gym.recommendations.$dateKey.$signature';
  }

  String _preferenceSummary(AppPreferences preferences) {
    final parts = <String>[];
    if ((preferences.gymPreferredSportLabel ?? '').isNotEmpty) {
      parts.add('运动 ${preferences.gymPreferredSportLabel}');
    }
    if ((preferences.gymPreferredVenueTypeLabel ?? '').isNotEmpty) {
      parts.add('场馆 ${preferences.gymPreferredVenueTypeLabel}');
    }
    if (preferences.gymTimePreference != null) {
      parts.add('时段 ${preferences.gymTimePreference!.label}');
    }
    if (parts.isEmpty) {
      return '';
    }
    return '当前偏好：${parts.join(' / ')}';
  }
}

class _RecommendedVenueCard extends StatelessWidget {
  const _RecommendedVenueCard({
    required this.venue,
    required this.slots,
    required this.selectedDate,
  });

  final Venue venue;
  final List<BookableSlot> slots;
  final DateTime selectedDate;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  venue.name,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                '${slots.length} 个可约时段',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (venue.venueType != null) _TagChip(label: venue.venueType!),
              if (venue.sportName != null) _TagChip(label: venue.sportName!),
              if (venue.capacity > 0) _TagChip(label: '建议 ${venue.capacity} 人'),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: slots
                .take(5)
                .map((slot) => _TimeChip(label: slot.timeLabel))
                .toList(),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonal(
              onPressed: () => context.push(
                '/gym-booking/venue/${venue.id}'
                '?name=${Uri.encodeComponent(venue.name)}'
                '&bizWid=${Uri.encodeComponent(venue.bizWid)}'
                '&date=${DateFormat('yyyy-MM-dd').format(selectedDate)}',
              ),
              child: const Text('查看场地'),
            ),
          ),
        ],
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

class _TimeChip extends StatelessWidget {
  const _TimeChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.primaryContainer.withValues(alpha: 0.55),
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

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: Column(
          children: [
            Icon(
              icon,
              size: 34,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 10),
            Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
