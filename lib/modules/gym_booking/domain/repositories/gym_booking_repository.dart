import '../../../../core/result/result.dart';
import '../../../auth/domain/entities/app_session.dart';
import '../entities/appointment_detail.dart';
import '../entities/gym_appointment_page.dart';
import '../entities/gym_booking_overview.dart';
import '../entities/gym_search_filter.dart';
import '../entities/gym_venue_search_page.dart';
import '../entities/venue_detail.dart';
import '../entities/venue_review.dart';

abstract class GymBookingRepository {
  Future<Result<GymBookingOverview>> fetchOverview({
    required AppSession session,
    required DateTime date,
    bool forceRefresh = false,
  });

  Future<Result<BookingRecord>> submitBooking({
    required AppSession session,
    required BookingDraft draft,
  });

  Future<Result<List<BookingRecord>>> fetchMyAppointments({
    required AppSession session,
    bool forceRefresh = false,
  });

  Future<Result<GymAppointmentPage>> fetchMyAppointmentsPage({
    required AppSession session,
    required GymAppointmentQuery query,
  });

  Future<Result<GymVenueSearchPage>> searchVenues({
    required AppSession session,
    required GymVenueSearchQuery query,
  });

  Future<Result<AppointmentDetail>> fetchAppointmentDetail({
    required AppSession session,
    required String wid,
  });

  Future<Result<void>> cancelAppointment({
    required AppSession session,
    required String appointmentId,
    String? reason,
  });

  Future<Result<VenueDetail>> fetchVenueDetail({
    required AppSession session,
    required String wid,
  });

  Future<Result<VenueReviewPage>> fetchVenueReviews({
    required AppSession session,
    required String bizWid,
    int page = 1,
    int pageSize = 10,
  });

  Future<Result<GymSearchModel>> fetchSearchModel({
    required AppSession session,
  });
}
