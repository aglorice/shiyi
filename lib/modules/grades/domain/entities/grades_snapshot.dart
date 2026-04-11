import '../../../../core/models/data_origin.dart';
import '../../../schedule/domain/entities/schedule_snapshot.dart';

class GradeRecord {
  const GradeRecord({
    required this.courseName,
    required this.termName,
    required this.grade,
    this.courseCode,
    this.credit,
    this.gradePoint,
    this.assessmentMethod,
    this.teacher,
    this.classHours,
  });

  final String courseName;
  final String termName;
  final String grade;
  final String? courseCode;
  final double? credit;
  final double? gradePoint;
  final String? assessmentMethod;
  final String? teacher;
  final String? classHours;

  Map<String, dynamic> toJson() => {
    'courseName': courseName,
    'termName': termName,
    'grade': grade,
    'courseCode': courseCode,
    'credit': credit,
    'gradePoint': gradePoint,
    'assessmentMethod': assessmentMethod,
    'teacher': teacher,
    'classHours': classHours,
  };

  factory GradeRecord.fromJson(Map<String, dynamic> json) {
    return GradeRecord(
      courseName: json['courseName'] as String,
      termName: json['termName'] as String,
      grade: json['grade'] as String,
      courseCode: json['courseCode'] as String?,
      credit: (json['credit'] as num?)?.toDouble(),
      gradePoint: (json['gradePoint'] as num?)?.toDouble(),
      assessmentMethod: json['assessmentMethod'] as String?,
      teacher: json['teacher'] as String?,
      classHours: json['classHours'] as String?,
    );
  }
}

class GradesSnapshot {
  const GradesSnapshot({
    required this.records,
    required this.availableTerms,
    required this.fetchedAt,
    required this.origin,
    this.selectedTerm,
  });

  final List<GradeRecord> records;
  final List<Term> availableTerms;
  final DateTime fetchedAt;
  final DataOrigin origin;
  final Term? selectedTerm;

  List<String> get terms {
    final values = <String>[];
    for (final record in records) {
      if (!values.contains(record.termName)) {
        values.add(record.termName);
      }
    }
    return values;
  }

  List<Term> get filterTerms {
    final values = <Term>[...availableTerms];
    for (final termName in terms) {
      final exists = values.any((term) => matchesTermName(termName, term.name));
      if (!exists) {
        values.add(Term(id: 'record::$termName', name: termName));
      }
    }
    return values;
  }

  Term? termById(String termId) {
    for (final term in filterTerms) {
      if (term.id == termId) {
        return term;
      }
    }
    return null;
  }

  List<GradeRecord> recordsForTerm(String termName) {
    return records.where((record) => record.termName == termName).toList();
  }

  List<GradeRecord> recordsForTermId(String termId) {
    final term = termById(termId);
    if (term == null) {
      return const [];
    }
    return records
        .where((record) => matchesTermName(record.termName, term.name))
        .toList();
  }

  GradesSnapshot copyWith({
    List<Term>? availableTerms,
    DateTime? fetchedAt,
    DataOrigin? origin,
    Term? selectedTerm,
  }) {
    return GradesSnapshot(
      records: records,
      availableTerms: availableTerms ?? this.availableTerms,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      origin: origin ?? this.origin,
      selectedTerm: selectedTerm ?? this.selectedTerm,
    );
  }

  Map<String, dynamic> toJson() => {
    'records': records.map((record) => record.toJson()).toList(),
    'availableTerms': availableTerms.map((term) => term.toJson()).toList(),
    'fetchedAt': fetchedAt.toIso8601String(),
    'origin': origin.name,
    'selectedTerm': selectedTerm?.toJson(),
  };

  factory GradesSnapshot.fromJson(Map<String, dynamic> json) {
    return GradesSnapshot(
      records: (json['records'] as List<dynamic>)
          .map((item) => GradeRecord.fromJson(item as Map<String, dynamic>))
          .toList(),
      availableTerms: (json['availableTerms'] as List<dynamic>? ?? const [])
          .map((item) => Term.fromJson(item as Map<String, dynamic>))
          .toList(),
      fetchedAt: DateTime.parse(json['fetchedAt'] as String),
      origin: DataOrigin.values.byName(json['origin'] as String),
      selectedTerm: json['selectedTerm'] is Map
          ? Term.fromJson(
              Map<String, dynamic>.from(
                (json['selectedTerm'] as Map).cast<dynamic, dynamic>(),
              ),
            )
          : null,
    );
  }

  static bool matchesTermName(String recordTermName, String termName) {
    final recordNormalized = _normalizeTermName(recordTermName);
    final termNormalized = _normalizeTermName(termName);
    if (recordNormalized == termNormalized ||
        recordNormalized.contains(termNormalized) ||
        termNormalized.contains(recordNormalized)) {
      return true;
    }

    final recordYear = _extractStartYear(recordTermName);
    final termYear = _extractStartYear(termName);
    final recordSeason = _extractSeason(recordTermName);
    final termSeason = _extractSeason(termName);

    return recordYear != null &&
        termYear != null &&
        recordYear == termYear &&
        recordSeason != null &&
        recordSeason == termSeason;
  }

  static String _normalizeTermName(String value) {
    return value.replaceAll(RegExp(r'\s+'), '').trim();
  }

  static int? _extractStartYear(String value) {
    final rangeMatch = RegExp(r'(20\d{2})').firstMatch(value);
    if (rangeMatch != null) {
      return int.tryParse(rangeMatch.group(1)!);
    }

    final shortMatch = RegExp(r'(\d{2})年').firstMatch(value);
    if (shortMatch != null) {
      final shortYear = int.tryParse(shortMatch.group(1)!);
      if (shortYear != null) {
        return 2000 + shortYear;
      }
    }

    return null;
  }

  static String? _extractSeason(String value) {
    if (value.contains('秋') || value.contains('第一学期')) {
      return 'fall';
    }
    if (value.contains('春') || value.contains('第二学期')) {
      return 'spring';
    }
    if (value.contains('夏') || value.contains('第三学期')) {
      return 'summer';
    }
    if (value.contains('冬') || value.contains('第四学期')) {
      return 'winter';
    }
    return null;
  }
}
