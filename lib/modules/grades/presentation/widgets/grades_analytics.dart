import 'package:flutter/material.dart';

import '../../../../app/theme/design_tokens.dart';
import '../../../../shared/widgets/surface_card.dart';
import '../../domain/entities/grades_snapshot.dart';

/// 成绩页"数据可视化"卡片：
/// 1) 三个统计胶囊：课程数 / 已修学分 / 平均绩点
/// 2) 学期 GPA 柱状图（不引第三方库，CustomPainter 手画，避免膨胀依赖）
///
/// 这块只看 [GradesSnapshot] 已经持有的 records，不再发额外请求。
class GradesAnalytics extends StatelessWidget {
  const GradesAnalytics({super.key, required this.snapshot});

  final GradesSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stats = _GradeStats.from(snapshot.records);
    final perTermGpa = _termGpaSeries(snapshot);

    return SurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '学业概览',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  label: '课程',
                  value: '${stats.totalCourses}',
                  suffix: '门',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatTile(
                  label: '已修学分',
                  value: stats.totalCredits == null
                      ? '-'
                      : stats.totalCredits!.toStringAsFixed(1),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatTile(
                  label: '平均绩点',
                  value: stats.gpa == null
                      ? '-'
                      : stats.gpa!.toStringAsFixed(2),
                ),
              ),
            ],
          ),
          if (perTermGpa.length >= 2) ...[
            const SizedBox(height: 18),
            Text(
              '近期学期 GPA 走势',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 110,
              child: _TermGpaBarChart(series: perTermGpa),
            ),
          ],
        ],
      ),
    );
  }

  /// 用按学期分组的有效绩点构造一条 GPA 序列（保留原始时序，新到旧）。
  /// 只在 records 至少能拼出 2 个学期、且每学期至少有 1 个 gradePoint 时返回。
  List<_TermGpaPoint> _termGpaSeries(GradesSnapshot snapshot) {
    final byTerm = <String, List<GradeRecord>>{};
    final order = <String>[];
    for (final record in snapshot.records) {
      final term = record.termName;
      if (!byTerm.containsKey(term)) {
        byTerm[term] = [];
        order.add(term);
      }
      byTerm[term]!.add(record);
    }
    final out = <_TermGpaPoint>[];
    for (final term in order) {
      final stats = _GradeStats.from(byTerm[term]!);
      if (stats.gpa != null) {
        out.add(_TermGpaPoint(termName: term, gpa: stats.gpa!));
      }
    }
    // 限制最多展示 6 个学期，太多了视觉上挤；保留最新的 6 个。
    if (out.length > 6) {
      return out.sublist(out.length - 6);
    }
    return out;
  }
}

class _GradeStats {
  const _GradeStats({
    required this.totalCourses,
    required this.totalCredits,
    required this.gpa,
  });

  final int totalCourses;
  final double? totalCredits;
  final double? gpa;

  static _GradeStats from(List<GradeRecord> records) {
    var totalCredit = 0.0;
    var weightedGp = 0.0;
    var creditedCount = 0;
    var gpCount = 0;

    for (final record in records) {
      if (record.credit != null) {
        totalCredit += record.credit!;
        creditedCount++;
      }
      if (record.credit != null && record.gradePoint != null) {
        weightedGp += record.credit! * record.gradePoint!;
        gpCount++;
      }
    }

    return _GradeStats(
      totalCourses: records.length,
      totalCredits: creditedCount == 0 ? null : totalCredit,
      gpa: (gpCount == 0 || totalCredit == 0)
          ? null
          : weightedGp / totalCredit,
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    this.suffix,
  });

  final String label;
  final String value;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.4,
                  height: 1,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (suffix != null) ...[
                const SizedBox(width: 2),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    suffix!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _TermGpaPoint {
  const _TermGpaPoint({required this.termName, required this.gpa});

  final String termName;
  final double gpa;
}

/// 极简学期 GPA 柱状图。
/// - X 轴是学期序号（缩短显示，如 "23-24 上"）
/// - 柱高按 [series] 中的最高 GPA 归一化到 80% 的高度，留 20% 给标签
/// - 用主题主色作为柱体颜色，圆角 4
class _TermGpaBarChart extends StatelessWidget {
  const _TermGpaBarChart({required this.series});

  final List<_TermGpaPoint> series;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxGpa = series.map((p) => p.gpa).reduce((a, b) => a > b ? a : b);
    final minGpa = series.map((p) => p.gpa).reduce((a, b) => a < b ? a : b);
    // 如果所有学期 GPA 几乎一致，留一点最低高度避免柱子全是 0 像素。
    final span = (maxGpa - minGpa) < 0.4 ? 0.6 : (maxGpa - minGpa + 0.3);
    final base = (maxGpa - span).clamp(0.0, double.infinity);

    return LayoutBuilder(
      builder: (context, constraints) {
        final usableHeight = constraints.maxHeight - 28;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final point in series) ...[
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      point.gpa.toStringAsFixed(2),
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.primary,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 320),
                      curve: Curves.easeOutCubic,
                      height: ((point.gpa - base) / span * usableHeight)
                          .clamp(4.0, usableHeight),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            theme.colorScheme.primary
                                .withValues(alpha: 0.85),
                            theme.colorScheme.primary
                                .withValues(alpha: 0.55),
                          ],
                        ),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4),
                          bottom: Radius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _shortTermLabel(point.termName),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  /// `2023-24 第一学期` → `23-24 上`。够省，挤得下 6 列。
  String _shortTermLabel(String full) {
    final yearMatch = RegExp(r'(\d{2})\d{2}-(\d{2})').firstMatch(full);
    final yearLabel = yearMatch != null
        ? '${yearMatch.group(1)}-${yearMatch.group(2)}'
        : full;
    if (full.contains('第一')) return '$yearLabel 上';
    if (full.contains('第二')) return '$yearLabel 下';
    if (full.contains('秋')) return '$yearLabel 秋';
    if (full.contains('春')) return '$yearLabel 春';
    if (full.contains('夏')) return '$yearLabel 夏';
    if (full.contains('冬')) return '$yearLabel 冬';
    return yearLabel;
  }
}
