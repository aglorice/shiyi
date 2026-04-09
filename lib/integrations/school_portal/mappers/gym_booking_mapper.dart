import '../../../core/models/data_origin.dart';
import '../../../modules/gym_booking/domain/entities/gym_booking_overview.dart';
import '../dto/gym_booking_dto.dart';

class GymBookingMapper {
  const GymBookingMapper();

  GymBookingOverview map(GymBookingDto dto, DateTime fetchedAt) {
    final venues = dto.venues
        .map(
          (venue) => Venue(
            id: venue.id,
            name: venue.name,
            location: venue.location,
            bizWid: venue.bizWid,
            venueType: venue.venueType,
            department: venue.department,
            departmentId: venue.departmentId,
            capacity: venue.capacity,
          ),
        )
        .toList();

    final slotsByVenue = <String, List<BookableSlot>>{};
    for (final venue in dto.venues) {
      slotsByVenue[venue.id] = venue.slots
          .map(
            (slot) => BookableSlot(
              id: slot.id,
              startTime: slot.startTime,
              endTime: slot.endTime,
              capacity: slot.capacity,
              remaining: slot.remaining,
              date: slot.date,
              weekday: slot.weekday,
              price: slot.price,
            ),
          )
          .toList();
    }

    return GymBookingOverview(
      date: dto.date,
      venues: venues,
      slotsByVenue: slotsByVenue,
      rule: BookingRule(
        summary: dto.rule.summary,
        advanceWindowDays: dto.rule.advanceWindowDays,
        supportsSameDay: dto.rule.supportsSameDay,
      ),
      records: dto.records
          .map(
            (record) => BookingRecord(
              id: record.id,
              venueName: record.venueName,
              slotLabel: record.slotLabel,
              date: record.date,
              status: record.status,
              statusCode: record.statusCode,
              canCancel: record.canCancel,
            ),
          )
          .toList(),
      fetchedAt: fetchedAt,
      origin: DataOrigin.remote,
    );
  }
}
