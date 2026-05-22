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
      // 1. 只有当 gateway 已经在远端列表里挑到 effective=未使用 的真实记录时，
      //    才把它塞进列表 state（看 record.recordId 是否为空 + effective 状态）。
      //    历史脏数据（同 WID 同时段的旧记录）会因为 effective=已取消 被排除，
      //    不会污染列表。占位记录（recordId 为 null）也跳过塞入，
      //    完全交给 invalidate 让远端覆盖。
      final isConfirmed = record.recordId != null &&
          record.recordId!.isNotEmpty &&
          record.effectiveStatusCode == '001';
      if (isConfirmed) {
        _patchAppointmentsState(record);
      }

      // 2. 立刻让"我的预约"重新拉一次，让真实数据覆盖。
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

        // 只有确认的真实 record 才进 overview.records，避免占位/脏数据污染。
        state = AsyncData(
          current.copyWith(
            slotsByVenue: updatedSlots,
            records: isConfirmed ? [record, ...current.records] : current.records,
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

/// "我的预约"页搜索模型：包含 SYZT/HYSLX/SFWY 等控件
/// 及它们的 code URL（前端用它驱动 chip 候选项）。
final gymAppointmentSearchModelProvider =
    FutureProvider<GymSearchModel>((ref) async {
  final authState = await ref.watch(authControllerProvider.future);
  final session = authState.session;
  if (session == null) {
    throw const AuthenticationFailure('当前未登录，无法加载预约搜索模型。');
  }

  final repository = ref.read(gymBookingRepositoryProvider);
  final result = await repository.fetchAppointmentSearchModel(session: session);
  return result.requireValue();
});

/// 拉取任意一个 `/qljfwapp/code/<id>.do` 的候选项。
/// 调用方传 url，返回 [GymFilterOption] 列表。
final gymCodeOptionsProvider =
    FutureProvider.family<List<GymFilterOption>, String>((ref, codeUrl) async {
  final authState = await ref.watch(authControllerProvider.future);
  final session = authState.session;
  if (session == null) {
    throw const AuthenticationFailure('当前未登录，无法加载代码表。');
  }
  final repository = ref.read(gymBookingRepositoryProvider);
  final result = await repository.fetchCodeOptions(
    session: session,
    codeUrl: codeUrl,
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
