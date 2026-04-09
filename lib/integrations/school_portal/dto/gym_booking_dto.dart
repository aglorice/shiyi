class GymBookingDto {
  const GymBookingDto({
    required this.date,
    required this.rule,
    required this.venues,
    required this.records,
  });

  final DateTime date;
  final GymRuleDto rule;
  final List<GymVenueDto> venues;
  final List<GymRecordDto> records;
}

class GymRuleDto {
  const GymRuleDto({
    required this.summary,
    required this.advanceWindowDays,
    required this.supportsSameDay,
  });

  final String summary;
  final int advanceWindowDays;
  final bool supportsSameDay;
}

class GymVenueDto {
  const GymVenueDto({
    required this.id,
    required this.name,
    required this.location,
    required this.bizWid,
    required this.slots,
    this.venueType,
    this.department,
    this.departmentId,
    this.capacity = 0,
  });

  final String id;
  final String name;
  final String location;
  final String bizWid;
  final String? venueType;
  final String? department;
  final String? departmentId;
  final int capacity;
  final List<GymSlotDto> slots;
}

class GymSlotDto {
  const GymSlotDto({
    required this.id,
    required this.startTime,
    required this.endTime,
    required this.capacity,
    required this.remaining,
    required this.date,
    required this.weekday,
    this.price = 0.0,
  });

  final String id;
  final String startTime;
  final String endTime;
  final int capacity;
  final int remaining;
  final DateTime date;
  final int weekday;
  final double price;
}

class GymRecordDto {
  const GymRecordDto({
    required this.id,
    required this.venueName,
    required this.slotLabel,
    required this.date,
    required this.status,
    this.statusCode,
    this.canCancel = false,
  });

  final String id;
  final String venueName;
  final String slotLabel;
  final DateTime date;
  final String status;
  final String? statusCode;
  final bool canCancel;
}
