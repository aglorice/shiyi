import '../../../../core/models/data_origin.dart';

class Venue {
  const Venue({
    required this.id,
    required this.name,
    required this.location,
    required this.bizWid,
    this.venueType,
    this.venueTypeId,
    this.sportId,
    this.sportName,
    this.department,
    this.departmentId,
    this.venueCode,
    this.address,
    this.openStatus,
    this.approvalMode,
    this.capacity = 0,
  });

  final String id;
  final String name;
  final String location;
  final String bizWid;
  final String? venueType;
  final String? venueTypeId;
  final String? sportId;
  final String? sportName;
  final String? department;
  final String? departmentId;
  final String? venueCode;
  final String? address;
  final String? openStatus;
  final String? approvalMode;
  final int capacity;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'location': location,
    'bizWid': bizWid,
    'venueType': venueType,
    'venueTypeId': venueTypeId,
    'sportId': sportId,
    'sportName': sportName,
    'department': department,
    'departmentId': departmentId,
    'venueCode': venueCode,
    'address': address,
    'openStatus': openStatus,
    'approvalMode': approvalMode,
    'capacity': capacity,
  };

  factory Venue.fromJson(Map<String, dynamic> json) {
    return Venue(
      id: json['id'] as String,
      name: json['name'] as String,
      location: json['location'] as String,
      bizWid: json['bizWid'] as String,
      venueType: json['venueType'] as String?,
      venueTypeId: json['venueTypeId'] as String?,
      sportId: json['sportId'] as String?,
      sportName: json['sportName'] as String?,
      department: json['department'] as String?,
      departmentId: json['departmentId'] as String?,
      venueCode: json['venueCode'] as String?,
      address: json['address'] as String?,
      openStatus: json['openStatus'] as String?,
      approvalMode: json['approvalMode'] as String?,
      capacity: json['capacity'] as int? ?? 0,
    );
  }
}

class BookableSlot {
  const BookableSlot({
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

  bool get isAvailable => remaining > 0;

  String get timeLabel => '$startTime-$endTime';

  BookableSlot copyWith({int? remaining}) {
    return BookableSlot(
      id: id,
      startTime: startTime,
      endTime: endTime,
      capacity: capacity,
      remaining: remaining ?? this.remaining,
      date: date,
      weekday: weekday,
      price: price,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'startTime': startTime,
    'endTime': endTime,
    'capacity': capacity,
    'remaining': remaining,
    'date': date.toIso8601String(),
    'weekday': weekday,
    'price': price,
  };

  factory BookableSlot.fromJson(Map<String, dynamic> json) {
    return BookableSlot(
      id: json['id'] as String,
      startTime: json['startTime'] as String,
      endTime: json['endTime'] as String,
      capacity: json['capacity'] as int,
      remaining: json['remaining'] as int,
      date: DateTime.parse(json['date'] as String),
      weekday: json['weekday'] as int,
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class BookingRule {
  const BookingRule({
    required this.summary,
    required this.advanceWindowDays,
    required this.supportsSameDay,
  });

  final String summary;
  final int advanceWindowDays;
  final bool supportsSameDay;

  Map<String, dynamic> toJson() => {
    'summary': summary,
    'advanceWindowDays': advanceWindowDays,
    'supportsSameDay': supportsSameDay,
  };

  factory BookingRule.fromJson(Map<String, dynamic> json) {
    return BookingRule(
      summary: json['summary'] as String,
      advanceWindowDays: json['advanceWindowDays'] as int,
      supportsSameDay: json['supportsSameDay'] as bool,
    );
  }
}

class BookingDraft {
  const BookingDraft({
    required this.venue,
    required this.slot,
    required this.attendeeName,
    required this.date,
    required this.userAccount,
    this.phone,
    this.bizWid,
  });

  final Venue venue;
  final BookableSlot slot;
  final String attendeeName;
  final DateTime date;
  final String userAccount;
  final String? phone;
  final String? bizWid;
}

class GymBookingEligibility {
  const GymBookingEligibility({required this.canApply, this.message});

  final bool canApply;
  final String? message;
}

class BookingRecord {
  const BookingRecord({
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

  Map<String, dynamic> toJson() => {
    'id': id,
    'venueName': venueName,
    'slotLabel': slotLabel,
    'date': date.toIso8601String(),
    'status': status,
    'statusCode': statusCode,
    'canCancel': canCancel,
  };

  factory BookingRecord.fromJson(Map<String, dynamic> json) {
    return BookingRecord(
      id: json['id'] as String,
      venueName: json['venueName'] as String,
      slotLabel: json['slotLabel'] as String,
      date: DateTime.parse(json['date'] as String),
      status: json['status'] as String,
      statusCode: json['statusCode'] as String?,
      canCancel: json['canCancel'] as bool? ?? false,
    );
  }
}

class GymBookingOverview {
  const GymBookingOverview({
    required this.date,
    required this.venues,
    required this.slotsByVenue,
    required this.rule,
    required this.records,
    required this.fetchedAt,
    required this.origin,
  });

  final DateTime date;
  final List<Venue> venues;
  final Map<String, List<BookableSlot>> slotsByVenue;
  final BookingRule rule;
  final List<BookingRecord> records;
  final DateTime fetchedAt;
  final DataOrigin origin;

  GymBookingOverview copyWith({
    DateTime? date,
    List<Venue>? venues,
    Map<String, List<BookableSlot>>? slotsByVenue,
    BookingRule? rule,
    List<BookingRecord>? records,
    DateTime? fetchedAt,
    DataOrigin? origin,
  }) {
    return GymBookingOverview(
      date: date ?? this.date,
      venues: venues ?? this.venues,
      slotsByVenue: slotsByVenue ?? this.slotsByVenue,
      rule: rule ?? this.rule,
      records: records ?? this.records,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      origin: origin ?? this.origin,
    );
  }

  Map<String, dynamic> toJson() => {
    'date': date.toIso8601String(),
    'venues': venues.map((venue) => venue.toJson()).toList(),
    'slotsByVenue': slotsByVenue.map(
      (key, value) =>
          MapEntry(key, value.map((slot) => slot.toJson()).toList()),
    ),
    'rule': rule.toJson(),
    'records': records.map((record) => record.toJson()).toList(),
    'fetchedAt': fetchedAt.toIso8601String(),
    'origin': origin.name,
  };

  factory GymBookingOverview.fromJson(Map<String, dynamic> json) {
    final slotsRaw = json['slotsByVenue'] as Map<String, dynamic>;

    return GymBookingOverview(
      date: DateTime.parse(json['date'] as String),
      venues: (json['venues'] as List<dynamic>)
          .map((item) => Venue.fromJson(item as Map<String, dynamic>))
          .toList(),
      slotsByVenue: slotsRaw.map(
        (key, value) => MapEntry(
          key,
          (value as List<dynamic>)
              .map(
                (item) => BookableSlot.fromJson(item as Map<String, dynamic>),
              )
              .toList(),
        ),
      ),
      rule: BookingRule.fromJson(json['rule'] as Map<String, dynamic>),
      records: (json['records'] as List<dynamic>)
          .map((item) => BookingRecord.fromJson(item as Map<String, dynamic>))
          .toList(),
      fetchedAt: DateTime.parse(json['fetchedAt'] as String),
      origin: DataOrigin.values.byName(json['origin'] as String),
    );
  }
}
