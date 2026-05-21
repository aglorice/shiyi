import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../../app/di/app_providers.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/appointment_detail.dart';
import '../../domain/entities/gym_appointment_page.dart';
import '../../domain/entities/gym_booking_overview.dart';
import '../../domain/entities/gym_search_filter.dart';
import '../../domain/entities/venue_detail.dart';
import '../../domain/entities/venue_review.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';

final gymBookingControllerProvider =
    AsyncNotifierProvider<GymBookingController, GymBookingOverview>(
      GymBookingController.new,
    );

final myGymAppointmentsProvider =
    AsyncNotifierProvider<MyGymAppointmentsNotifier, List<BookingRecord>>(
      MyGymAppointmentsNotifier.new,
    );

class GymBookingController extends AsyncNotifier<GymBookingOverview> {
  DateTime _selectedDate = DateTime.now();

  DateTime get selectedDate => _normalize(_selectedDate);

  @override
  Future<GymBookingOverview> build() async {
    _selectedDate = _normalize(DateTime.now());
    return _load(forceRefresh: false);
  }

  Future<Result<BookingRecord>> bookSlot({
    required Venue venue,
    required BookableSlot slot,
    String? phone,
    DateTime? date,
  }) async {
    final authState = await ref.read(authControllerProvider.future);
    final session = authState.session;
    if (session == null) {
      return const FailureResult(AuthenticationFailure('当前未登录，无法提交预约。'));
    }

    final bookingDate = _normalize(date ?? selectedDate);

    final result = await ref.read(submitGymBookingUseCaseProvider)(
      session: session,
      draft: BookingDraft(
        venue: venue,
        slot: slot,
        attendeeName: session.displayName,
        date: bookingDate,
        userAccount: session.userId,
        bizWid: venue.bizWid,
        phone: phone,
      ),
    );

    if (result case Success<BookingRecord>(data: final record)) {
      // 1. 立即把新预约塞到"我的预约"provider 的当前 state，
      //    让首页卡片和列表页瞬间显示，不必等下一次远端拉取。
      _patchAppointmentsState(record);

      // 2. 后台异步刷新一次远端，覆盖本地的占位数据。
      ref.invalidate(myGymAppointmentsProvider);

      final current = state.value;
      if (current != null) {
        final targetNorm = bookingDate;
        final updatedSlots = <String, List<BookableSlot>>{
          for (final entry in current.slotsByVenue.entries)
            entry.key: entry.value
                .map(
                  (item) =>
                      item.id == slot.id && _normalize(item.date) == targetNorm
                      ? item.copyWith(remaining: item.remaining - 1)
                      : item,
                )
                .toList(),
        };

        state = AsyncData(
          current.copyWith(
            slotsByVenue: updatedSlots,
            records: [record, ...current.records],
            fetchedAt: DateTime.now(),
          ),
        );
      }
    }

    return result;
  }

  void _patchAppointmentsState(BookingRecord record) {
    final notifier = ref.read(myGymAppointmentsProvider.notifier);
    final current = ref.read(myGymAppointmentsProvider).value;
    if (current == null) {
      return;
    }
    final next = [record, ...current];
    notifier.setRecords(next);
  }

  Future<void> changeDate(DateTime date) async {
    _selectedDate = _normalize(date);
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _load(forceRefresh: true));
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _load(forceRefresh: true));
  }

  Future<GymBookingOverview> _load({required bool forceRefresh}) async {
    final authState = await ref.watch(authControllerProvider.future);
    final session = authState.session;
    if (session == null) {
      throw const AuthenticationFailure('当前未登录，无法加载场馆预约。');
    }

    final result = await ref.read(fetchGymBookingOverviewUseCaseProvider)(
      session: session,
      date: selectedDate,
      forceRefresh: forceRefresh,
    );

    return result.requireValue();
  }

  DateTime _normalize(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }
}

class MyGymAppointmentsNotifier extends AsyncNotifier<List<BookingRecord>> {
  @override
  Future<List<BookingRecord>> build() async {
    return _load(forceRefresh: false);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _load(forceRefresh: true));
  }

  /// 立即用本地数据替换 state，避免预约/取消后等远端返回造成的闪烁。
  void setRecords(List<BookingRecord> records) {
    state = AsyncData(_deduplicateAndSort(records));
  }

  /// 把指定预约标记为已取消，立即体现在列表里。
  /// 服务端会用 `WID` 做匹配，所以这里也按 [BookingRecord.id]（场地 WID）匹配，
  /// 同时按预约日期 + 时段过滤，避免误伤同场地的其他预约。
  void markCancelled({
    required String appointmentId,
    required DateTime date,
    required String slotLabel,
  }) {
    final current = state.value;
    if (current == null) {
      return;
    }
    final updated = current.map((record) {
      final sameVenue = record.id == appointmentId;
      final sameDate = DateTime(record.date.year, record.date.month, record.date.day) ==
          DateTime(date.year, date.month, date.day);
      final sameSlot = record.slotLabel == slotLabel;
      if (sameVenue && sameDate && sameSlot) {
        return BookingRecord(
          id: record.id,
          venueName: record.venueName,
          slotLabel: record.slotLabel,
          date: record.date,
          status: '已取消',
          statusCode: '003',
          canCancel: false,
          recordId: record.recordId,
          bizWid: record.bizWid,
          payStatusCode: 'CG_QX',
          payStatusDisplay: '已取消',
          flowStatusCode: record.flowStatusCode,
          flowStatusDisplay: record.flowStatusDisplay,
          venueTypeCode: record.venueTypeCode,
          venueTypeDisplay: record.venueTypeDisplay,
          submittedAt: record.submittedAt,
          violation: record.violation,
        );
      }
      return record;
    }).toList();
    state = AsyncData(updated);
  }

  Future<List<BookingRecord>> _load({required bool forceRefresh}) async {
    final authState = await ref.watch(authControllerProvider.future);
    final session = authState.session;
    if (session == null) {
      return const [];
    }

    final result = await ref.read(fetchGymAppointmentsPageUseCaseProvider)(
      session: session,
      query: const GymAppointmentQuery(pageNumber: 1, pageSize: 20),
    );

    return switch (result) {
      Success<GymAppointmentPage>(data: final page) =>
        _deduplicateAndSort(page.records),
      _ => const [],
    };
  }

  /// 按 [BookingRecord.dedupeKey]（即 `ID_` 主键）去重，再按日期降序排列。
  /// 历史 `WID` 去重会把同场地的多次预约错杀，这里改成稳定主键。
  List<BookingRecord> _deduplicateAndSort(List<BookingRecord> records) {
    final seen = <String>{};
    final unique = <BookingRecord>[];
    for (final record in records) {
      if (seen.add(record.dedupeKey)) {
        unique.add(record);
      }
    }
    unique.sort((a, b) {
      final dateCompare = b.date.compareTo(a.date);
      if (dateCompare != 0) {
        return dateCompare;
      }
      final left = a.submittedAt;
      final right = b.submittedAt;
      if (left != null && right != null) {
        return right.compareTo(left);
      }
      return 0;
    });
    return unique;
  }
}

final gymAppointmentDetailProvider =
    FutureProvider.family<AppointmentDetail, String>((ref, wid) async {
      final authState = await ref.watch(authControllerProvider.future);
      final session = authState.session;
      if (session == null) {
        throw const AuthenticationFailure('当前未登录，无法加载预约详情。');
      }

      final result = await ref.read(fetchAppointmentDetailUseCaseProvider)(
        session: session,
        wid: wid,
      );

      return result.requireValue();
    });

final gymSearchModelProvider = FutureProvider<GymSearchModel>((ref) async {
  final authState = await ref.watch(authControllerProvider.future);
  final session = authState.session;
  if (session == null) {
    throw const AuthenticationFailure('当前未登录，无法加载搜索模型。');
  }

  final result = await ref.read(fetchGymSearchModelUseCaseProvider)(
    session: session,
  );

  return result.requireValue();
});

final selectedVenueFilterProvider = StateProvider<String?>((ref) => null);

Future<Result<void>> cancelAppointment(
  Ref ref,
  String appointmentId, {
  String? reason,
}) async {
  final authState = await ref.read(authControllerProvider.future);
  final session = authState.session;
  if (session == null) {
    return const FailureResult(AuthenticationFailure('当前未登录，无法取消预约。'));
  }

  final result = await ref.read(cancelGymAppointmentUseCaseProvider)(
    session: session,
    appointmentId: appointmentId,
    reason: reason ?? '0',
  );

  if (result.isSuccess) {
    ref.invalidate(myGymAppointmentsProvider);
  }

  return result;
}

final gymVenueDetailProvider = FutureProvider.family<VenueDetail, String>((
  ref,
  wid,
) async {
  final authState = await ref.watch(authControllerProvider.future);
  final session = authState.session;
  if (session == null) {
    throw const AuthenticationFailure('当前未登录，无法加载场地详情。');
  }

  final result = await ref.read(fetchVenueDetailUseCaseProvider)(
    session: session,
    wid: wid,
  );

  return result.requireValue();
});

final gymVenueReviewsProvider = FutureProvider.family<VenueReviewPage, String>((
  ref,
  bizWid,
) async {
  final authState = await ref.watch(authControllerProvider.future);
  final session = authState.session;
  if (session == null) {
    throw const AuthenticationFailure('当前未登录，无法加载场地评论。');
  }

  final result = await ref.read(fetchVenueReviewsUseCaseProvider)(
    session: session,
    bizWid: bizWid,
  );

  return result.requireValue();
});
