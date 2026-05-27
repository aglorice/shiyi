/// "周次描述"字符串解析器。从教务系统返回的多种文本格式里抠出真正的周次列表。
///
/// 教务系统给的字符串很自由：
/// - 简单连续：`1-16`、`1~16`、`1-16周`
/// - 单/双周：`1-16(单周)`、`2-16(双周)`、`1-16（双周）`（中文括号）
/// - 离散：`1,3,5,7`、`1、3、5`（中文顿号）
/// - 混合：`1-4,7,9-12`、`1-12,14-16`（停课周）
///
/// 解析失败 / 字符串为空时返回 `null`，让调用方回落到默认连续区间逻辑。
///
/// 这个函数被 `ClassSession.effectiveWeeks` 用，是过滤"今天是否真的有这节课"
/// 的关键路径——单/双周课、停课周次的剔除全靠它。所以单独成文件 + 单测覆盖。
library;

/// 解析"周次描述"字符串，返回去重后的升序周列表。
///
/// 例：
/// - `parseWeekDescription('1-16(单周)')` → `[1, 3, 5, 7, 9, 11, 13, 15]`
/// - `parseWeekDescription('1-12,14-16')` → `[1..12, 14, 15, 16]`
/// - `parseWeekDescription(null)` → `null`
List<int>? parseWeekDescription(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  var text = raw
      .replaceAll('（', '(')
      .replaceAll('）', ')')
      .replaceAll('～', '~')
      .replaceAll('、', ',')
      .replaceAll(' ', '')
      .trim();

  int parityFilter = 0; // 0 不过滤，1 仅奇周，2 仅偶周
  final parityMatch = RegExp(r'\(([^)]+)\)').firstMatch(text);
  if (parityMatch != null) {
    final tag = parityMatch.group(1)!;
    if (tag.contains('单')) parityFilter = 1;
    if (tag.contains('双')) parityFilter = 2;
    text = text.replaceAll(parityMatch.group(0)!, '');
  }
  text = text.replaceAll('周', '').replaceAll('教学', '').trim();
  if (text.isEmpty) return null;

  final weeks = <int>{};
  for (final segment in text.split(',')) {
    final seg = segment.trim();
    if (seg.isEmpty) continue;
    final range = RegExp(r'^(\d+)\s*[-~]\s*(\d+)$').firstMatch(seg);
    if (range != null) {
      final from = int.parse(range.group(1)!);
      final to = int.parse(range.group(2)!);
      if (to >= from) {
        for (var w = from; w <= to; w++) {
          weeks.add(w);
        }
      }
      continue;
    }
    final single = RegExp(r'^\d+$').firstMatch(seg);
    if (single != null) {
      weeks.add(int.parse(single.group(0)!));
    }
  }
  if (weeks.isEmpty) return null;

  Iterable<int> result = weeks;
  if (parityFilter == 1) {
    result = weeks.where((w) => w.isOdd);
  } else if (parityFilter == 2) {
    result = weeks.where((w) => w.isEven);
  }
  final list = result.toList()..sort();
  return list.isEmpty ? null : list;
}
