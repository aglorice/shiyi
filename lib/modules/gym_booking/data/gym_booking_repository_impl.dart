import '../../../core/logging/app_logger.dart';
import '../../../core/models/data_origin.dart';
import '../../../core/result/result.dart';
import '../../../core/storage/json_cache_store.dart';
import '../../../integrations/school_portal/school_portal_gateway.dart';
import '../../auth/domain/entities/app_session.dart';
import '../domain/entities/appointment_detail.dart';
import '../domain/entities/gym_appointment_page.dart';
import '../domain/entities/gym_booking_overview.dart';
import '../domain/entities/gym_search_filter.dart';
import '../domain/entities/gym_venue_search_page.dart';
import '../domain/entities/venue_detail.dart';
import '../domain/entities/venue_review.dart';
import '../domain/repositories/gym_booking_repository.dart';

class GymBookingRepositoryImpl implements GymBookingRepository {
  const GymBookingRepositoryImpl({
    required SchoolPortalGateway gateway,
    required JsonCacheStore cacheStore,
    required AppLogger logger,
  }) : _gateway = gateway,
       _cacheStore = cacheStore,
       _logger = logger;

  final SchoolPortalGateway _gateway;
  final JsonCacheStore _cacheStore;
  final AppLogger _logger;

  static const _appointmentsCacheKey = 'gym.my_appointments';

  String _cacheKey(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    return 'gym.overview.${normalized.toIso8601String()}';
  }

  @override
  Future<Result<GymBookingOverview>> fetchOverview({
    required AppSession session,
    required DateTime date,
    bool forceRefresh = false,
  }) async {
    final remote = await _gateway.fetchGymBookingOverview(session, date: date);

    if (remote case Success<GymBookingOverview>(data: final overview)) {
      await _cacheStore.writeMap(_cacheKey(date), overview.toJson());
      return Success(overview);
    }

    final cached = await _cacheStore.readMap(_cacheKey(date));
    if (cached != null) {
      _logger.warn('Falling back to cached gym booking overview.');
      return Success(
        GymBookingOverview.fromJson(cached).copyWith(origin: DataOrigin.cache),
      );
    }

    return FailureResult(remote.failureOrNull!);
  }

  @override
  Future<Result<BookingRecord>> submitBooking({
    required AppSession session,
    required BookingDraft draft,
  }) async {
    final result = await _gateway.submitGymBooking(session, draft: draft);

    if (result case Success<BookingRecord>(data: final record)) {
      final cacheKey = _cacheKey(draft.date);
      final cached = await _cacheStore.readMap(cacheKey);
      if (cached != null) {
        final overview = GymBookingOverview.fromJson(cached);
        final targetNorm = DateTime(
          draft.date.year,
          draft.date.month,
          draft.date.day,
        );
        final updatedSlots = <String, List<BookableSlot>>{
          for (final entry in overview.slotsByVenue.entries)
            entry.key: entry.value
                .map(
                  (slot) =>
                      slot.id == draft.slot.id &&
                          DateTime(
                                slot.date.year,
                                slot.date.month,
                                slot.date.day,
                              ) ==
                              targetNorm
                      ? slot.copyWith(remaining: slot.remaining - 1)
                      : slot,
                )
                .toList(),
        };

        final updated = overview.copyWith(
          slotsByVenue: updatedSlots,
          records: [record, ...overview.records],
          fetchedAt: DateTime.now(),
          origin: overview.origin,
        );

        await _cacheStore.writeMap(cacheKey, updated.toJson());
      }

      return Success(record);
    }

    return FailureResult(result.failureOrNull!);
  }

  @override
  Future<Result<List<BookingRecord>>> fetchMyAppointments({
    required AppSession session,
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = await _cacheStore.readMap(_appointmentsCacheKey);
      if (cached != null) {
        final records = (cached['records'] as List<dynamic>)
            .map((item) => BookingRecord.fromJson(item as Map<String, dynamic>))
            .toList();
        _logger.debug('Using cached gym appointments count=${records.length}');
        return Success(records);
      }
    }

    final result = await _gateway.fetchMyGymAppointments(session);
    if (result case Success<List<BookingRecord>>(data: final records)) {
      await _cacheStore.writeMap(_appointmentsCacheKey, {
        'records': records.map((r) => r.toJson()).toList(),
      });
      return Success(records);
    }

    final cached = await _cacheStore.readMap(_appointmentsCacheKey);
    if (cached != null) {
      final records = (cached['records'] as List<dynamic>)
          .map((item) => BookingRecord.fromJson(item as Map<String, dynamic>))
          .toList();
      _logger.warn('Falling back to cached gym appointments.');
      return Success(records);
    }

    return FailureResult(result.failureOrNull!);
  }

  @override
  Future<Result<GymAppointmentPage>> fetchMyAppointmentsPage({
    required AppSession session,
    required GymAppointmentQuery query,
  }) async {
    return _gateway.fetchMyGymAppointmentsPage(session, query: query);
  }

  @override
  Future<Result<GymVenueSearchPage>> searchVenues({
    required AppSession session,
    required GymVenueSearchQuery query,
  }) async {
    return _gateway.searchGymVenues(session, query: query);
  }

  @override
  Future<Result<AppointmentDetail>> fetchAppointmentDetail({
    required AppSession session,
    required String wid,
  }) async {
    return _gateway.fetchGymAppointmentDetail(session, wid: wid);
  }

  @override
  Future<Result<void>> cancelAppointment({
    required AppSession session,
    required String appointmentId,
    String? reason,
  }) async {
    return _gateway.cancelGymAppointment(
      session,
      appointmentId: appointmentId,
      reason: reason,
    );
  }

  @override
  Future<Result<VenueDetail>> fetchVenueDetail({
    required AppSession session,
    required String wid,
  }) async {
    final result = await _gateway.fetchGymRoomDetail(session, wid: wid);

    if (result case Success<VenueDetail>(data: final detail)) {
      return Success(detail);
    }

    return FailureResult(result.failureOrNull!);
  }

  @override
  Future<Result<VenueReviewPage>> fetchVenueReviews({
    required AppSession session,
    required String bizWid,
    int page = 1,
    int pageSize = 10,
  }) async {
    final result = await _gateway.fetchGymRoomReviews(
      session,
      bizWid: bizWid,
      page: page,
      pageSize: pageSize,
    );

    if (result case Success<VenueReviewPage>(data: final reviewPage)) {
      return Success(reviewPage);
    }

    return FailureResult(result.failureOrNull!);
  }

  @override
  Future<Result<GymSearchModel>> fetchSearchModel({
    required AppSession session,
  }) async {
    return _gateway.fetchGymSearchModel(session);
  }
}
