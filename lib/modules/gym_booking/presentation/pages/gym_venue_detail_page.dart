import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../app/di/app_providers.dart';
import '../../../../app/settings/app_preferences_controller.dart';
import '../../../../core/error/error_display.dart';
import '../../../../core/result/result.dart';
import '../../../../shared/widgets/async_value_view.dart';
import '../../../../shared/widgets/app_snackbar.dart';
import '../../../../shared/widgets/constrained_body.dart';
import '../../../../shared/widgets/surface_card.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../domain/entities/gym_booking_overview.dart';
import '../../domain/entities/gym_venue_search_page.dart' as search;
import '../../domain/entities/venue_detail.dart';
import '../../domain/entities/venue_review.dart';
import '../controllers/gym_booking_controller.dart';
import '../widgets/gym_booking_components.dart';
import '../widgets/phone_number_dialog.dart';

class GymVenueDetailPage extends ConsumerStatefulWidget {
  const GymVenueDetailPage({
    super.key,
    required this.venueId,
    required this.venueName,
    this.bizWid,
    this.initialDate,
  });

  final String venueId;
  final String venueName;
  final String? bizWid;
  final DateTime? initialDate;

  @override
  ConsumerState<GymVenueDetailPage> createState() => _GymVenueDetailPageState();
}

class _GymVenueDetailPageState extends ConsumerState<GymVenueDetailPage> {
  late DateTime _selectedDate;
  Venue? _bookingVenue;
  List<BookableSlot> _slots = const [];
  Object? _slotError;
  bool _loadingSlots = false;

  VenueReviewPage? _reviewPage;
  Object? _reviewError;
  bool _loadingReviews = false;
  bool _loadingMoreReviews = false;

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _selectedDate =
        widget.initialDate ?? DateTime(today.year, today.month, today.day);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSlots();
      _loadReviews(reset: true);
    });
  }

  String get _effectiveBizWid {
    final fromVenue = _bookingVenue?.bizWid ?? '';
    if (fromVenue.isNotEmpty) {
      return fromVenue;
    }
    return widget.bizWid ?? '';
  }

  Future<void> _loadSlots() async {
    setState(() {
      _loadingSlots = true;
      _slotError = null;
    });

    final authState = await ref.read(authControllerProvider.future);
    final session = authState.session;
    if (session == null) {
      setState(() {
        _loadingSlots = false;
        _slotError = '当前未登录，无法读取场地时段。';
      });
      return;
    }

    final result = await ref.read(searchGymVenuesUseCaseProvider)(
      session: session,
      query: search.GymVenueSearchQuery(
        date: _selectedDate,
        pageNumber: 1,
        pageSize: 1,
        venueId: widget.venueId,
      ),
    );

    if (!mounted) {
      return;
    }

    switch (result) {
      case Success<search.GymVenueSearchPage>(data: final data):
        final venue = data.venues.isNotEmpty ? data.venues.first : null;
        final baseSlots = venue == null
            ? const <BookableSlot>[]
            : (data.slotsByVenue[venue.id] ?? const []);

        // 在基础排期之上，再用 getSjdByRoom 拿"实时剩余可约"时段交集，
        // 把已经被别人订掉/被锁定的时段从 UI 里剔除。
        var slots = baseSlots;
        if (venue != null && baseSlots.isNotEmpty) {
          final repo = ref.read(gymBookingRepositoryProvider);
          final availableResult = await repo.fetchRoomAvailableSlots(
            session: session,
            roomId: venue.id,
            applyDate: _selectedDate,
          );
          if (availableResult case Success<List<String>>(data: final available)) {
            if (available.isNotEmpty) {
              final allowed = available.toSet();
              slots = baseSlots
                  .where((slot) => allowed.contains(slot.timeLabel))
                  .toList();
            }
          }
          if (!mounted) {
            return;
          }
        }

        setState(() {
          _bookingVenue = venue;
          _slots = slots;
          _loadingSlots = false;
        });
        if (_effectiveBizWid.isNotEmpty && _reviewPage == null) {
          _loadReviews(reset: true);
        }
      case FailureResult<search.GymVenueSearchPage>(failure: final failure):
        setState(() {
          _loadingSlots = false;
          _slotError = failure;
        });
    }
  }

  Future<void> _loadReviews({required bool reset}) async {
    final bizWid = _effectiveBizWid;
    if (bizWid.isEmpty) {
      setState(() {
        _reviewPage = const VenueReviewPage(reviews: [], totalCount: 0);
        _loadingReviews = false;
        _loadingMoreReviews = false;
      });
      return;
    }

    setState(() {
      if (reset) {
        _loadingReviews = true;
      } else {
        _loadingMoreReviews = true;
      }
      _reviewError = null;
    });

    final authState = await ref.read(authControllerProvider.future);
    final session = authState.session;
    if (session == null) {
      setState(() {
        _loadingReviews = false;
        _loadingMoreReviews = false;
        _reviewError = '当前未登录，无法读取评论。';
      });
      return;
    }

    final pageNumber = reset ? 1 : (_reviewPage?.pageNumber ?? 1) + 1;
    final result = await ref.read(fetchVenueReviewsUseCaseProvider)(
      session: session,
      bizWid: bizWid,
      page: pageNumber,
      pageSize: 8,
    );

    if (!mounted) {
      return;
    }

    switch (result) {
      case Success<VenueReviewPage>(data: final data):
        setState(() {
          if (reset || _reviewPage == null) {
            _reviewPage = data;
          } else {
            _reviewPage = _reviewPage!.copyWith(
              reviews: [..._reviewPage!.reviews, ...data.reviews],
              totalCount: data.totalCount,
              pageNumber: data.pageNumber,
              pageSize: data.pageSize,
            );
          }
          _loadingReviews = false;
          _loadingMoreReviews = false;
        });
      case FailureResult<VenueReviewPage>(failure: final failure):
        setState(() {
          _loadingReviews = false;
          _loadingMoreReviews = false;
          _reviewError = failure;
        });
    }
  }

  Future<void> _bookSlot(Venue venue, BookableSlot slot) async {
    var phone = ref.read(appPreferencesControllerProvider).gymPhoneNumber;
    if (phone == null || phone.isEmpty) {
      phone = await showPhoneNumberDialog(context);
      if (phone == null) {
        return;
      }
      await ref
          .read(appPreferencesControllerProvider.notifier)
          .setGymPhoneNumber(phone);
    }

    if (!mounted) {
      return;
    }

    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: const Text('确认预约'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(venue.name),
                  const SizedBox(height: 8),
                  Text(
                    DateFormat(
                      'yyyy-MM-dd EEEE',
                      'zh_CN',
                    ).format(_selectedDate),
                  ),
                  const SizedBox(height: 4),
                  Text(slot.timeLabel),
                  if (venue.capacity > 0) ...[
                    const SizedBox(height: 4),
                    Text('建议使用人数不超过 ${venue.capacity} 人'),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('确认预约'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!confirmed || !mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    AppSnackBar.show(
      context,
      message: '正在提交预约...',
      tone: AppSnackBarTone.info,
      icon: Icons.hourglass_top_rounded,
      duration: const Duration(seconds: 12),
    );

    final result = await ref
        .read(gymBookingControllerProvider.notifier)
        .bookSlot(venue: venue, slot: slot, phone: phone, date: _selectedDate);

    if (!mounted) {
      return;
    }

    messenger.hideCurrentSnackBar();
    switch (result) {
      case Success<BookingRecord>(data: final record):
        AppSnackBar.show(
          context,
          message: '${record.venueName} ${record.slotLabel} 预约成功',
          tone: AppSnackBarTone.success,
          icon: Icons.check_circle_rounded,
          clearCurrent: false,
        );
        ref.invalidate(myGymAppointmentsProvider);
        _loadSlots();
      case FailureResult<BookingRecord>(failure: final failure):
        AppSnackBar.show(
          context,
          message: formatError(failure).message,
          tone: AppSnackBarTone.error,
          clearCurrent: false,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(gymVenueDetailProvider(widget.venueId));

    return Scaffold(
      appBar: AppBar(title: Text(widget.venueName)),
      body: ConstrainedBody(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 120),
          children: [
            _BookingPanel(
              selectedDate: _selectedDate,
              onDateChanged: (date) {
                setState(() => _selectedDate = date);
                _loadSlots();
              },
              loading: _loadingSlots,
              error: _slotError,
              venue: _bookingVenue,
              slots: _slots,
              onBook: _bookSlot,
            ),
            const SizedBox(height: 14),
            AsyncValueView(
              value: detailAsync,
              onRetry: () =>
                  ref.invalidate(gymVenueDetailProvider(widget.venueId)),
              loadingLabel: '加载场地详情',
              dataBuilder: (detail) => _VenueDetailPanel(detail: detail),
            ),
            const SizedBox(height: 14),
            _ReviewPanel(
              reviewPage: _reviewPage,
              loading: _loadingReviews,
              loadingMore: _loadingMoreReviews,
              error: _reviewError,
              onRetry: () => _loadReviews(reset: true),
              onLoadMore: () => _loadReviews(reset: false),
            ),
          ],
        ),
      ),
    );
  }
}

class _BookingPanel extends StatelessWidget {
  const _BookingPanel({
    required this.selectedDate,
    required this.onDateChanged,
    required this.loading,
    required this.error,
    required this.venue,
    required this.slots,
    required this.onBook,
  });

  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateChanged;
  final bool loading;
  final Object? error;
  final Venue? venue;
  final List<BookableSlot> slots;
  final Future<void> Function(Venue venue, BookableSlot slot) onBook;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '选择时段',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            '先选日期，再确认当前场地当天开放的预约时段。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          GymDateSelector(
            selectedDate: selectedDate,
            onDateChanged: onDateChanged,
          ),
          const SizedBox(height: 14),
          if (loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: CircularProgressIndicator(),
              ),
            )
          else if (error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  formatError(error!).message,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else if (venue == null || slots.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  '该日期暂无可预约时段',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
            Column(
              children: [
                for (var i = 0; i < slots.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      thickness: 0.6,
                      color: Theme.of(context).dividerColor.withValues(alpha: 0.4),
                    ),
                  GymSlotTile(
                    slot: slots[i],
                    capacity: venue!.capacity,
                    onBook: () => onBook(venue!, slots[i]),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _VenueDetailPanel extends StatelessWidget {
  const _VenueDetailPanel({required this.detail});

  final VenueDetail detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SurfaceCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '场地信息',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          _InfoRow(label: '名称', value: detail.name),
          if (detail.address != null)
            _InfoRow(label: '地址', value: detail.address!),
          if (detail.venueType != null)
            _InfoRow(label: '类型', value: detail.venueType!),
          if (detail.department != null)
            _InfoRow(label: '项目', value: detail.department!),
          _InfoRow(label: '人数', value: '${detail.capacity}'),
          if (detail.maxAdvanceDays != null)
            _InfoRow(label: '提前预约', value: '${detail.maxAdvanceDays} 天'),
          if (detail.openStatus != null)
            _InfoRow(label: '开放状态', value: detail.openStatus!),
          if (detail.bookable != null)
            _InfoRow(label: '预约审核', value: detail.bookable!),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewPanel extends StatelessWidget {
  const _ReviewPanel({
    required this.reviewPage,
    required this.loading,
    required this.loadingMore,
    required this.error,
    required this.onRetry,
    required this.onLoadMore,
  });

  final VenueReviewPage? reviewPage;
  final bool loading;
  final bool loadingMore;
  final Object? error;
  final VoidCallback onRetry;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    final reviews = reviewPage?.reviews ?? const <VenueReview>[];

    return SurfaceCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '用户评论',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (reviewPage != null)
                Text(
                  '${reviewPage!.totalCount} 条',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: CircularProgressIndicator(),
              ),
            )
          else if (error != null && reviews.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Column(
                  children: [
                    Text(
                      formatError(error!).message,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.tonal(
                      onPressed: onRetry,
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            )
          else if (reviews.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  '暂无评论',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else ...[
            for (var i = 0; i < reviews.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  thickness: 0.6,
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.4),
                ),
              _ReviewTile(review: reviews[i]),
            ],
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: Text(
                  formatError(error!).message,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            if (reviewPage?.hasMore == true)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Align(
                  alignment: Alignment.center,
                  child: FilledButton.tonal(
                    onPressed: loadingMore ? null : onLoadMore,
                    child: Text(loadingMore ? '加载中...' : '加载更多评论'),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({required this.review});

  final VenueReview review;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: theme.colorScheme.secondaryContainer,
                child: Text(
                  review.userName.isNotEmpty ? review.userName[0] : '?',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  review.userName,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _StarRating(rating: review.rating),
            ],
          ),
          if (review.createdAt != null) ...[
            const SizedBox(height: 6),
            Text(
              DateFormat('yyyy-MM-dd').format(review.createdAt!),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (review.content != null && review.content!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(review.content!, style: theme.textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}

class _StarRating extends StatelessWidget {
  const _StarRating({required this.rating});

  final double rating;

  @override
  Widget build(BuildContext context) {
    final icons = List.generate(5, (index) {
      if (rating >= index + 1) {
        return Icons.star_rounded;
      }
      if (rating >= index + 0.5) {
        return Icons.star_half_rounded;
      }
      return Icons.star_outline_rounded;
    });

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: icons.map((icon) {
        return Icon(icon, size: 16, color: const Color(0xFFE8A838));
      }).toList(),
    );
  }
}
