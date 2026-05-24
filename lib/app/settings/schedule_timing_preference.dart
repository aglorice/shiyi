import 'dart:convert';

/// 用户在「课表 → 具体时间设置」里配置的时间表。
///
/// 总开关 [enabled] 关闭时，所有显示/导出仍然走默认/原始字符串；
/// 打开时，按 [resolveSectionTimes] 把第 N 节映射到 (HH:mm, HH:mm)。
class ScheduleTimingPreference {
  const ScheduleTimingPreference({
    required this.enabled,
    required this.lessonMinutes,
    required this.shortBreakMinutes,
    required this.longBreakMinutes,
    required this.morning,
    required this.afternoon,
    required this.evening,
  });

  final bool enabled;

  /// 一节课多少分钟。
  final int lessonMinutes;

  /// 默认课间分钟。
  final int shortBreakMinutes;

  /// 大课间分钟，用于被标记为长间隔的位置。
  final int longBreakMinutes;

  final TimingBlock morning;
  final TimingBlock afternoon;
  final TimingBlock evening;

  static const defaults = ScheduleTimingPreference(
    enabled: true,
    lessonMinutes: 45,
    shortBreakMinutes: 5,
    longBreakMinutes: 20,
    morning: TimingBlock(
      start: '08:15',
      sessionCount: 4,
      longBreakAt: {1}, // 第 2 节后是大课间
    ),
    afternoon: TimingBlock(
      start: '14:30',
      sessionCount: 4,
      longBreakAt: {1},
    ),
    evening: TimingBlock(
      start: '19:30',
      sessionCount: 3,
      longBreakAt: {1},
    ),
  );

  ScheduleTimingPreference copyWith({
    bool? enabled,
    int? lessonMinutes,
    int? shortBreakMinutes,
    int? longBreakMinutes,
    TimingBlock? morning,
    TimingBlock? afternoon,
    TimingBlock? evening,
  }) {
    return ScheduleTimingPreference(
      enabled: enabled ?? this.enabled,
      lessonMinutes: lessonMinutes ?? this.lessonMinutes,
      shortBreakMinutes: shortBreakMinutes ?? this.shortBreakMinutes,
      longBreakMinutes: longBreakMinutes ?? this.longBreakMinutes,
      morning: morning ?? this.morning,
      afternoon: afternoon ?? this.afternoon,
      evening: evening ?? this.evening,
    );
  }

  /// 把第 N 节（1-based 全局编号）映射到 (start, end)。
  /// 节号顺延：上午 1..M，下午 M+1..M+A，晚上 M+A+1..M+A+E。
  Map<int, ({String start, String end})> resolveSectionTimes() {
    final result = <int, ({String start, String end})>{};
    var section = 1;
    for (final block in [morning, afternoon, evening]) {
      final parsed = _parseHmToMinutes(block.start);
      if (parsed == null) {
        section += block.sessionCount;
        continue;
      }
      var minutes = parsed;
      for (var i = 0; i < block.sessionCount; i++) {
        final startMin = minutes;
        final endMin = startMin + lessonMinutes;
        result[section] = (
          start: _formatMinutes(startMin),
          end: _formatMinutes(endMin),
        );
        section++;
        if (i < block.sessionCount - 1) {
          final gap = block.gapMinutesAt(
            i,
            shortBreakMinutes: shortBreakMinutes,
            longBreakMinutes: longBreakMinutes,
          );
          minutes = endMin + gap;
        }
      }
    }
    return result;
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'lessonMinutes': lessonMinutes,
    'shortBreakMinutes': shortBreakMinutes,
    'longBreakMinutes': longBreakMinutes,
    'morning': morning.toJson(),
    'afternoon': afternoon.toJson(),
    'evening': evening.toJson(),
  };

  factory ScheduleTimingPreference.fromJson(Map<String, dynamic> json) {
    return ScheduleTimingPreference(
      enabled: json['enabled'] as bool? ?? true,
      lessonMinutes: (json['lessonMinutes'] as num?)?.toInt() ?? 45,
      shortBreakMinutes: (json['shortBreakMinutes'] as num?)?.toInt() ?? 5,
      longBreakMinutes: (json['longBreakMinutes'] as num?)?.toInt() ?? 20,
      morning: json['morning'] is Map
          ? TimingBlock.fromJson(json['morning'] as Map<String, dynamic>)
          : defaults.morning,
      afternoon: json['afternoon'] is Map
          ? TimingBlock.fromJson(json['afternoon'] as Map<String, dynamic>)
          : defaults.afternoon,
      evening: json['evening'] is Map
          ? TimingBlock.fromJson(json['evening'] as Map<String, dynamic>)
          : defaults.evening,
    );
  }

  static ScheduleTimingPreference fromJsonString(String? raw) {
    if (raw == null || raw.isEmpty) return defaults;
    try {
      final map = jsonDecode(raw);
      if (map is Map<String, dynamic>) {
        return ScheduleTimingPreference.fromJson(map);
      }
    } catch (_) {}
    return defaults;
  }

  String toJsonString() => jsonEncode(toJson());
}

class TimingBlock {
  const TimingBlock({
    required this.start,
    required this.sessionCount,
    this.longBreakAt = const <int>{},
    this.customGap = const <int, int>{},
  });

  final String start;

  /// 节数。
  final int sessionCount;

  /// 哪些 gap index 用「大课间」。gapIndex 0 = 第 1 节与第 2 节之间。
  final Set<int> longBreakAt;

  /// 自定义 gap 分钟，优先级高于 [longBreakAt]。
  final Map<int, int> customGap;

  TimingBlock copyWith({
    String? start,
    int? sessionCount,
    Set<int>? longBreakAt,
    Map<int, int>? customGap,
  }) {
    return TimingBlock(
      start: start ?? this.start,
      sessionCount: sessionCount ?? this.sessionCount,
      longBreakAt: longBreakAt ?? this.longBreakAt,
      customGap: customGap ?? this.customGap,
    );
  }

  /// 把 sessionCount 调小后，超出范围的 longBreakAt / customGap 应裁剪。
  TimingBlock trimmedToCount(int newCount) {
    final maxGap = newCount - 1;
    return TimingBlock(
      start: start,
      sessionCount: newCount,
      longBreakAt: longBreakAt.where((g) => g < maxGap).toSet(),
      customGap: {
        for (final entry in customGap.entries)
          if (entry.key < maxGap) entry.key: entry.value,
      },
    );
  }

  int gapMinutesAt(
    int gapIndex, {
    required int shortBreakMinutes,
    required int longBreakMinutes,
  }) {
    final custom = customGap[gapIndex];
    if (custom != null) return custom;
    if (longBreakAt.contains(gapIndex)) return longBreakMinutes;
    return shortBreakMinutes;
  }

  /// 切换 gap 在 短 / 大 / 自定义之间。
  /// 这里只支持在 短 ↔ 大 之间互切，自定义保留给 UI 直接调 [customGap]。
  TimingBlock toggleLongBreak(int gapIndex) {
    final next = Set<int>.from(longBreakAt);
    if (next.contains(gapIndex)) {
      next.remove(gapIndex);
    } else {
      next.add(gapIndex);
    }
    final newCustom = Map<int, int>.from(customGap)..remove(gapIndex);
    return TimingBlock(
      start: start,
      sessionCount: sessionCount,
      longBreakAt: next,
      customGap: newCustom,
    );
  }

  TimingBlock setCustomGap(int gapIndex, int? minutes) {
    final newCustom = Map<int, int>.from(customGap);
    if (minutes == null) {
      newCustom.remove(gapIndex);
    } else {
      newCustom[gapIndex] = minutes;
    }
    return TimingBlock(
      start: start,
      sessionCount: sessionCount,
      longBreakAt: longBreakAt,
      customGap: newCustom,
    );
  }

  Map<String, dynamic> toJson() => {
    'start': start,
    'sessionCount': sessionCount,
    'longBreakAt': longBreakAt.toList(),
    'customGap': customGap.map((k, v) => MapEntry(k.toString(), v)),
  };

  factory TimingBlock.fromJson(Map<String, dynamic> json) {
    final long = (json['longBreakAt'] as List<dynamic>? ?? const [])
        .map((e) => (e as num).toInt())
        .toSet();
    final custom = <int, int>{};
    final rawCustom = json['customGap'];
    if (rawCustom is Map) {
      rawCustom.forEach((key, value) {
        final k = int.tryParse('$key');
        if (k != null && value is num) {
          custom[k] = value.toInt();
        }
      });
    }
    return TimingBlock(
      start: json['start'] as String? ?? '08:00',
      sessionCount: (json['sessionCount'] as num?)?.toInt() ?? 1,
      longBreakAt: long,
      customGap: custom,
    );
  }
}

int? _parseHmToMinutes(String value) {
  final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(value.trim());
  if (match == null) return null;
  final h = int.tryParse(match.group(1)!);
  final m = int.tryParse(match.group(2)!);
  if (h == null || m == null) return null;
  return h * 60 + m;
}

String _formatMinutes(int minutes) {
  final clamped = minutes % (24 * 60);
  final positive = clamped < 0 ? clamped + 24 * 60 : clamped;
  final h = positive ~/ 60;
  final m = positive % 60;
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}
