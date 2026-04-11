import '../../../../core/models/data_origin.dart';
import '../../../schedule/domain/entities/schedule_snapshot.dart';

class ExamRecord {
  const ExamRecord({
    required this.courseName,
    required this.dateLabel,
    required this.timeLabel,
    required this.location,
    this.courseCode,
    this.className,
    this.examMethod,
    this.primaryTeacher,
    this.assistantTeacher,
    this.candidateCount,
    this.seatNumber,
    this.remark,
    this.assessmentForm,
    this.examPaperMode,
    this.examCategory,
  });

  final String courseName;
  final String dateLabel;
  final String timeLabel;
  final String location;
  final String? courseCode;
  final String? className;
  final String? examMethod;
  final String? primaryTeacher;
  final String? assistantTeacher;
  final String? candidateCount;
  final String? seatNumber;
  final String? remark;
  final String? assessmentForm;
  final String? examPaperMode;
  final String? examCategory;

  List<String> get displayMetaTags {
    final values = <String>[];

    void append(String? value) {
      if (value == null) {
        return;
      }
      final normalized = value.trim();
      if (normalized.isEmpty || values.contains(normalized)) {
        return;
      }
      values.add(normalized);
    }

    append(assessmentForm);
    append(examPaperMode);
    append(examCategory);
    append(examMethod);
    return values;
  }

  Map<String, dynamic> toJson() => {
    'courseName': courseName,
    'dateLabel': dateLabel,
    'timeLabel': timeLabel,
    'location': location,
    'courseCode': courseCode,
    'className': className,
    'examMethod': examMethod,
    'primaryTeacher': primaryTeacher,
    'assistantTeacher': assistantTeacher,
    'candidateCount': candidateCount,
    'seatNumber': seatNumber,
    'remark': remark,
    'assessmentForm': assessmentForm,
    'examPaperMode': examPaperMode,
    'examCategory': examCategory,
  };

  factory ExamRecord.fromJson(Map<String, dynamic> json) {
    return ExamRecord(
      courseName: json['courseName'] as String,
      dateLabel: json['dateLabel'] as String,
      timeLabel: json['timeLabel'] as String,
      location: json['location'] as String,
      courseCode: json['courseCode'] as String?,
      className: json['className'] as String?,
      examMethod: json['examMethod'] as String?,
      primaryTeacher: json['primaryTeacher'] as String?,
      assistantTeacher: json['assistantTeacher'] as String?,
      candidateCount: json['candidateCount'] as String?,
      seatNumber: json['seatNumber'] as String?,
      remark: json['remark'] as String?,
      assessmentForm: json['assessmentForm'] as String?,
      examPaperMode: json['examPaperMode'] as String?,
      examCategory: json['examCategory'] as String?,
    );
  }
}

class ExamScheduleSnapshot {
  const ExamScheduleSnapshot({
    required this.term,
    required this.availableTerms,
    required this.records,
    required this.fetchedAt,
    required this.origin,
  });

  final Term term;
  final List<Term> availableTerms;
  final List<ExamRecord> records;
  final DateTime fetchedAt;
  final DataOrigin origin;

  ExamScheduleSnapshot copyWith({
    Term? term,
    List<Term>? availableTerms,
    DateTime? fetchedAt,
    DataOrigin? origin,
  }) {
    return ExamScheduleSnapshot(
      term: term ?? this.term,
      availableTerms: availableTerms ?? this.availableTerms,
      records: records,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      origin: origin ?? this.origin,
    );
  }

  Map<String, dynamic> toJson() => {
    'term': term.toJson(),
    'availableTerms': availableTerms.map((term) => term.toJson()).toList(),
    'records': records.map((record) => record.toJson()).toList(),
    'fetchedAt': fetchedAt.toIso8601String(),
    'origin': origin.name,
  };

  factory ExamScheduleSnapshot.fromJson(Map<String, dynamic> json) {
    return ExamScheduleSnapshot(
      term: Term.fromJson(json['term'] as Map<String, dynamic>),
      availableTerms: (json['availableTerms'] as List<dynamic>? ?? const [])
          .map((item) => Term.fromJson(item as Map<String, dynamic>))
          .toList(),
      records: (json['records'] as List<dynamic>)
          .map((item) => ExamRecord.fromJson(item as Map<String, dynamic>))
          .toList(),
      fetchedAt: DateTime.parse(json['fetchedAt'] as String),
      origin: DataOrigin.values.byName(json['origin'] as String),
    );
  }
}
