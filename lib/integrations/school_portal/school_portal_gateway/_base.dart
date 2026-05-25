// 共享状态 + 跨子领域复用的 JSON / 日期 / 学期助手。
//
// 所有 mixin 的 `on` 约束都指向 [_GatewayBase]，因此可以直接读取
// `_portalApi`、`_logger` 等。
part of '../school_portal_gateway.dart';

class _GatewayBase {
  _GatewayBase({
    required SsoLoginOrchestrator loginOrchestrator,
    required SessionValidator sessionValidator,
    required WyuPortalApi portalApi,
    required AppLogger logger,
  })  : _loginOrchestrator = loginOrchestrator,
        _sessionValidator = sessionValidator,
        _portalApi = portalApi,
        _logger = logger;

  final SsoLoginOrchestrator _loginOrchestrator;
  final SessionValidator _sessionValidator;
  final WyuPortalApi _portalApi;
  final AppLogger _logger;
  final Random _random = Random();

  // -------------------- JSON 字段助手 --------------------

  String? _pickString(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value == null) {
        continue;
      }
      final text = value.toString().trim();
      if (text.isNotEmpty) {
        return text;
      }
    }
    return null;
  }

  int? _pickInt(Map<String, dynamic> map, List<String> keys) {
    final value = _pickString(map, keys);
    if (value == null) {
      return null;
    }
    return int.tryParse(value);
  }

  double? _pickDouble(Map<String, dynamic> map, List<String> keys) {
    final value = _pickString(map, keys);
    if (value == null) {
      return null;
    }
    return double.tryParse(value);
  }

  /// 把任意 JSON 兼容对象格式化成 2 空格缩进的字符串，方便日志阅读。
  /// 失败时回落到 `toString()`，确保日志不会因此抛错。
  String _prettyJson(Object? value) {
    if (value == null) {
      return 'null';
    }
    try {
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(value);
    } catch (_) {
      return value.toString();
    }
  }

  /// 把任意嵌套 JSON 里所有 Map 收集成一个扁平列表，给后端经常包好几层
  /// 的"列表数据"用：例如成绩接口里嵌套 datas/data/rows 都会被走到。
  List<Map<String, dynamic>> _collectRecordMaps(dynamic value) {
    final items = <Map<String, dynamic>>[];

    void visit(dynamic node) {
      if (node is List) {
        for (final item in node) {
          visit(item);
        }
        return;
      }

      if (node is! Map) {
        return;
      }

      final map = Map<String, dynamic>.from(node.cast<dynamic, dynamic>());
      items.add(map);
      for (final child in map.values) {
        visit(child);
      }
    }

    visit(value);
    return items;
  }

  // -------------------- 时间格式化 --------------------

  int _nonce() => _random.nextInt(100000);

  DateTime _normalizeDate(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  String _formatDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  // -------------------- 学期解析 / 教务态识别 --------------------

  Map<String, dynamic> _selectScheduleTerm(
    List<Map<String, dynamic>> terms, {
    String? requestedTermId,
  }) {
    if (requestedTermId != null && requestedTermId.isNotEmpty) {
      for (final term in terms) {
        if (_pickString(term, const ['termcode', 'termCode']) ==
            requestedTermId) {
          return term;
        }
      }
    }

    for (final term in terms) {
      if (_isSelectedTermCurrent(term)) {
        return term;
      }
    }
    return terms.first;
  }

  List<Term> _mapTerms(
    List<Map<String, dynamic>> termMaps, {
    required String selectedTermId,
  }) {
    return termMaps.map((map) {
      final id = _pickString(map, const ['termcode', 'termCode']) ?? '';
      final name =
          _pickString(map, const ['termname', 'termName', 'name']) ?? id;
      return Term(id: id, name: name, isSelected: id == selectedTermId);
    }).toList();
  }

  bool _isSelectedTermCurrent(Map<String, dynamic> termMap) {
    final value = _pickString(termMap, const [
      'selected',
      'dqxnq',
      'isCurrent',
      'currentFlag',
      'sfmr',
    ]);
    return value == '1' || value?.toLowerCase() == 'true';
  }

  bool _isAllTermsSelection(String? termId) =>
      termId != null && termId.isEmpty;

  // -------------------- 本科教务系统学期生成 --------------------

  List<Term> _generateUndergradTerms() {
    final now = DateTime.now();
    final terms = <Term>[];
    final currentAcademicYear = now.month >= 9 ? now.year : now.year - 1;
    final currentTermId = _currentUndergradTermId(now);

    for (
      var academicYear = currentAcademicYear;
      academicYear >= currentAcademicYear - 3;
      academicYear--
    ) {
      final firstTerm = _buildUndergradTerm(academicYear, 1);
      final secondTerm = _buildUndergradTerm(academicYear, 2);

      if (firstTerm.id == currentTermId) {
        terms
          ..add(firstTerm.copyWith(isSelected: true))
          ..add(secondTerm);
        continue;
      }
      if (secondTerm.id == currentTermId) {
        terms
          ..add(secondTerm.copyWith(isSelected: true))
          ..add(firstTerm);
        continue;
      }

      terms
        ..add(secondTerm)
        ..add(firstTerm);
    }

    return terms;
  }

  Term _selectUndergradTerm(List<Term> terms, {String? requestedTermId}) {
    if (requestedTermId != null && requestedTermId.isNotEmpty) {
      final match = terms.where((t) => t.id == requestedTermId);
      if (match.isNotEmpty) return match.first;
    }
    final selected = terms.where((t) => t.isSelected);
    if (selected.isNotEmpty) return selected.first;
    return terms.isNotEmpty ? terms.last : const Term(id: '', name: '未知学期');
  }

  Term _buildUndergradTerm(int academicYear, int semesterIndex) {
    final termCode = '$academicYear${semesterIndex.toString().padLeft(2, '0')}';
    return Term(
      id: termCode,
      name: _formatUndergradTermName(termCode) ?? termCode,
    );
  }

  String _currentUndergradTermId(DateTime now) {
    final academicYear = now.month >= 9 ? now.year : now.year - 1;
    final semesterIndex = now.month >= 3 && now.month <= 8 ? 2 : 1;
    return '$academicYear${semesterIndex.toString().padLeft(2, '0')}';
  }

  String? _formatUndergradTermName(String? termCode) {
    if (termCode == null) {
      return null;
    }

    final match = RegExp(r'^(20\d{2})(0[12])$').firstMatch(termCode);
    if (match == null) {
      return termCode;
    }

    final academicYear = int.parse(match.group(1)!);
    final semesterCode = match.group(2)!;
    final displayEndYear = (academicYear + 1) % 100;
    final semesterLabel = switch (semesterCode) {
      '01' => '第一学期',
      '02' => '第二学期',
      _ => termCode,
    };
    return '$academicYear-${displayEndYear.toString().padLeft(2, '0')} $semesterLabel';
  }

  Failure? _extractUndergradJxglAuthFailure(Map<String, dynamic> raw) {
    final code = _pickString(raw, const ['code', 'status']);
    final message = _pickString(raw, const ['message', 'msg', 'error']);
    if (code != '-401' &&
        code != '401' &&
        !_looksLikeSessionExpiredMessage(message)) {
      return null;
    }
    return SessionExpiredFailure(message ?? '教务系统会话已失效。');
  }

  bool _looksLikeSessionExpiredMessage(String? message) {
    if (message == null || message.isEmpty) {
      return false;
    }
    return message.contains('尚未登录') ||
        message.contains('请先登录') ||
        message.contains('登录失效') ||
        message.contains('已在别处登录') ||
        message.contains('被迫退出');
  }
}
