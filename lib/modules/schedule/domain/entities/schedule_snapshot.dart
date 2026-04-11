import '../../../../core/models/data_origin.dart';

class Term {
  const Term({required this.id, required this.name, this.isSelected = false});

  final String id;
  final String name;
  final bool isSelected;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'isSelected': isSelected,
  };

  factory Term.fromJson(Map<String, dynamic> json) {
    return Term(
      id: json['id'] as String,
      name: json['name'] as String,
      isSelected: json['isSelected'] as bool? ?? false,
    );
  }

  Term copyWith({String? id, String? name, bool? isSelected}) {
    return Term(
      id: id ?? this.id,
      name: name ?? this.name,
      isSelected: isSelected ?? this.isSelected,
    );
  }
}

class WeekRange {
  const WeekRange({required this.startWeek, required this.endWeek});

  final int startWeek;
  final int endWeek;

  String get label => '$startWeek-$endWeek 周';

  Map<String, dynamic> toJson() => {'startWeek': startWeek, 'endWeek': endWeek};

  factory WeekRange.fromJson(Map<String, dynamic> json) {
    return WeekRange(
      startWeek: json['startWeek'] as int,
      endWeek: json['endWeek'] as int,
    );
  }
}

class TeachingLocation {
  const TeachingLocation({
    required this.campus,
    required this.building,
    required this.room,
  });

  final String campus;
  final String building;
  final String room;

  String get fullName {
    final parts = [
      campus,
      building,
      room,
    ].where((item) => item.trim().isNotEmpty && item.trim() != '-').toList();
    return parts.isEmpty ? '地点待定' : parts.join(' · ');
  }

  Map<String, dynamic> toJson() => {
    'campus': campus,
    'building': building,
    'room': room,
  };

  factory TeachingLocation.fromJson(Map<String, dynamic> json) {
    return TeachingLocation(
      campus: json['campus'] as String,
      building: json['building'] as String,
      room: json['room'] as String,
    );
  }
}

class ClassSession {
  const ClassSession({
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    required this.weekRange,
    required this.location,
    required this.teacher,
    this.startSection,
    this.endSection,
    this.weekDescription,
    this.dayLabel,
  });

  final int dayOfWeek;
  final String startTime;
  final String endTime;
  final WeekRange weekRange;
  final TeachingLocation location;
  final String teacher;
  final int? startSection;
  final int? endSection;
  final String? weekDescription;
  final String? dayLabel;

  String get weekdayLabel {
    if (dayLabel != null && dayLabel!.trim().isNotEmpty) {
      return dayLabel!;
    }
    const labels = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return labels[dayOfWeek - 1];
  }

  String get timeLabel => '$startTime - $endTime';

  String get sectionLabel {
    if (startSection == null && endSection == null) {
      return '节次待定';
    }
    if (startSection == endSection) {
      return '第 $startSection 节';
    }
    return '第 $startSection-$endSection 节';
  }

  String get weekLabel => weekDescription?.trim().isNotEmpty == true
      ? weekDescription!
      : weekRange.label;

  Map<String, dynamic> toJson() => {
    'dayOfWeek': dayOfWeek,
    'startTime': startTime,
    'endTime': endTime,
    'weekRange': weekRange.toJson(),
    'location': location.toJson(),
    'teacher': teacher,
    'startSection': startSection,
    'endSection': endSection,
    'weekDescription': weekDescription,
    'dayLabel': dayLabel,
  };

  factory ClassSession.fromJson(Map<String, dynamic> json) {
    return ClassSession(
      dayOfWeek: json['dayOfWeek'] as int,
      startTime: json['startTime'] as String,
      endTime: json['endTime'] as String,
      weekRange: WeekRange.fromJson(json['weekRange'] as Map<String, dynamic>),
      location: TeachingLocation.fromJson(
        json['location'] as Map<String, dynamic>,
      ),
      teacher: json['teacher'] as String? ?? '',
      startSection: json['startSection'] as int?,
      endSection: json['endSection'] as int?,
      weekDescription: json['weekDescription'] as String?,
      dayLabel: json['dayLabel'] as String?,
    );
  }
}

class Course {
  const Course({
    required this.id,
    required this.name,
    required this.teacher,
    required this.sessions,
    this.courseCode,
    this.note,
  });

  final String id;
  final String name;
  final String teacher;
  final List<ClassSession> sessions;
  final String? courseCode;
  final String? note;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'teacher': teacher,
    'courseCode': courseCode,
    'note': note,
    'sessions': sessions.map((session) => session.toJson()).toList(),
  };

  factory Course.fromJson(Map<String, dynamic> json) {
    return Course(
      id: json['id'] as String,
      name: json['name'] as String,
      teacher: json['teacher'] as String,
      courseCode: json['courseCode'] as String?,
      note: json['note'] as String?,
      sessions: (json['sessions'] as List<dynamic>)
          .map((item) => ClassSession.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}

class ScheduleSnapshot {
  static const int fallbackCurrentWeek = 5;

  const ScheduleSnapshot({
    required this.term,
    required this.availableTerms,
    required this.courses,
    required this.fetchedAt,
    required this.origin,
    this.currentWeek,
  });

  final Term term;
  final List<Term> availableTerms;
  final int? currentWeek;
  final List<Course> courses;
  final DateTime fetchedAt;
  final DataOrigin origin;

  bool get isCurrentTerm => currentWeek != null;
  int get displayWeek => currentWeek ?? fallbackCurrentWeek;
  bool get isUsingFallbackWeek => currentWeek == null;
  int get maxWeek {
    final allEntries = entries;
    if (allEntries.isEmpty) {
      return displayWeek;
    }

    var max = displayWeek;
    for (final entry in allEntries) {
      if (entry.session.weekRange.endWeek > max) {
        max = entry.session.weekRange.endWeek;
      }
    }
    return max;
  }

  List<ScheduleEntry> get entries {
    final items = <ScheduleEntry>[];
    for (final course in courses) {
      for (final session in course.sessions) {
        items.add(ScheduleEntry(course: course, session: session));
      }
    }
    items.sort((left, right) {
      final byDay = left.session.dayOfWeek.compareTo(right.session.dayOfWeek);
      if (byDay != 0) {
        return byDay;
      }
      if (left.session.startSection != null &&
          right.session.startSection != null) {
        final bySection = left.session.startSection!.compareTo(
          right.session.startSection!,
        );
        if (bySection != 0) {
          return bySection;
        }
      }
      return left.session.startTime.compareTo(right.session.startTime);
    });
    return items;
  }

  List<ScheduleEntry> get visibleEntries {
    return entriesForWeek();
  }

  List<ScheduleEntry> entriesForWeek({int? week, bool showAllWeeks = false}) {
    if (showAllWeeks) {
      return entries;
    }

    final targetWeek = week ?? displayWeek;
    return entries.where((item) {
      return targetWeek >= item.session.weekRange.startWeek &&
          targetWeek <= item.session.weekRange.endWeek;
    }).toList();
  }

  List<ScheduleEntry> sessionsForDay(
    int dayOfWeek, {
    int? week,
    bool showAllWeeks = false,
  }) {
    return entriesForWeek(
      week: week,
      showAllWeeks: showAllWeeks,
    ).where((item) => item.session.dayOfWeek == dayOfWeek).toList();
  }

  ScheduleSnapshot copyWith({
    Term? term,
    List<Term>? availableTerms,
    int? currentWeek,
    bool clearCurrentWeek = false,
    DateTime? fetchedAt,
    DataOrigin? origin,
  }) {
    return ScheduleSnapshot(
      term: term ?? this.term,
      availableTerms: availableTerms ?? this.availableTerms,
      currentWeek: clearCurrentWeek ? null : currentWeek ?? this.currentWeek,
      courses: courses,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      origin: origin ?? this.origin,
    );
  }

  Map<String, dynamic> toJson() => {
    'term': term.toJson(),
    'availableTerms': availableTerms.map((term) => term.toJson()).toList(),
    'currentWeek': currentWeek,
    'courses': courses.map((course) => course.toJson()).toList(),
    'fetchedAt': fetchedAt.toIso8601String(),
    'origin': origin.name,
  };

  factory ScheduleSnapshot.fromJson(Map<String, dynamic> json) {
    return ScheduleSnapshot(
      term: Term.fromJson(json['term'] as Map<String, dynamic>),
      availableTerms: (json['availableTerms'] as List<dynamic>? ?? const [])
          .map((item) => Term.fromJson(item as Map<String, dynamic>))
          .toList(),
      currentWeek: json['currentWeek'] as int?,
      courses: (json['courses'] as List<dynamic>)
          .map((item) => Course.fromJson(item as Map<String, dynamic>))
          .toList(),
      fetchedAt: DateTime.parse(json['fetchedAt'] as String),
      origin: DataOrigin.values.byName(json['origin'] as String),
    );
  }
}

class ScheduleEntry {
  const ScheduleEntry({required this.course, required this.session});

  final Course course;
  final ClassSession session;
}
