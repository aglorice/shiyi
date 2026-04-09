import 'dart:convert';

import '../../../core/error/failure.dart';
import '../../../core/result/result.dart';
import '../dto/gym_booking_dto.dart';

class GymBookingParser {
  const GymBookingParser();

  Result<GymBookingDto> parse(String rawBody) {
    try {
      final decoded = jsonDecode(rawBody);
      if (decoded is! Map<String, dynamic>) {
        return const FailureResult(
          ParsingFailure('Gym booking payload is not a JSON object.'),
        );
      }

      final venues = (decoded['venues'] as List<dynamic>)
          .map(
            (venue) => GymVenueDto(
              id: venue['id'] as String,
              name: venue['name'] as String,
              location: venue['location'] as String,
              bizWid: venue['bizWid'] as String? ?? '',
              venueType: venue['venueType'] as String?,
              department: venue['department'] as String?,
              departmentId: venue['departmentId'] as String?,
              capacity: venue['capacity'] as int? ?? 0,
              slots: (venue['slots'] as List<dynamic>)
                  .map(
                    (slot) => GymSlotDto(
                      id: slot['id'] as String,
                      startTime: slot['startTime'] as String,
                      endTime: slot['endTime'] as String,
                      capacity: slot['capacity'] as int,
                      remaining: slot['remaining'] as int,
                      date: DateTime.parse(slot['date'] as String),
                      weekday: slot['weekday'] as int,
                      price: (slot['price'] as num?)?.toDouble() ?? 0.0,
                    ),
                  )
                  .toList(),
            ),
          )
          .toList();

      final records = (decoded['records'] as List<dynamic>)
          .map(
            (record) => GymRecordDto(
              id: record['id'] as String,
              venueName: record['venueName'] as String,
              slotLabel: record['slotLabel'] as String,
              date: DateTime.parse(record['date'] as String),
              status: record['status'] as String,
              statusCode: record['statusCode'] as String?,
              canCancel: record['canCancel'] as bool? ?? false,
            ),
          )
          .toList();

      return Success(
        GymBookingDto(
          date: DateTime.parse(decoded['date'] as String),
          rule: GymRuleDto(
            summary: decoded['rule']['summary'] as String,
            advanceWindowDays: decoded['rule']['advanceWindowDays'] as int,
            supportsSameDay: decoded['rule']['supportsSameDay'] as bool,
          ),
          venues: venues,
          records: records,
        ),
      );
    } catch (error, stackTrace) {
      return FailureResult(
        ParsingFailure(
          'Failed to parse gym booking payload.',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }
}
