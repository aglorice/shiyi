import 'package:flutter/material.dart';

import '../../app/theme/design_tokens.dart';

/// 一个统一的「主视觉卡」组件，面向各模块顶部的渐变 hero card。
///
/// 这之前每个模块（电费/考试/场馆/详情/关于）都各画了一份，颜色硬编码，
/// 深色模式下有的会糊掉。统一到这里之后：
/// - 配色全部基于 [ColorScheme]（默认 primary→tertiary），自动跟随主题；
/// - 圆角和内边距走 [AppRadius] / [AppSpacing] 常量；
/// - 自带 [stats] 网格槽，模块只需要传数据。
class AccentHero extends StatelessWidget {
  const AccentHero({
    super.key,
    this.title,
    this.subtitle,
    this.subtitleWidget,
    this.leading,
    this.trailing,
    this.stats = const <AccentHeroStat>[],
    this.footer,
    this.gradientFrom,
    this.gradientTo,
    this.foregroundColor,
    this.padding,
  }) : assert(
          subtitle == null || subtitleWidget == null,
          'subtitle 和 subtitleWidget 二选一',
        );

  final String? title;
  final String? subtitle;
  final Widget? subtitleWidget;
  final Widget? leading;
  final Widget? trailing;
  final List<AccentHeroStat> stats;
  final Widget? footer;

  /// 渐变起色，默认 [ColorScheme.primary]。
  final Color? gradientFrom;

  /// 渐变止色，默认在 primary 与 tertiary 之间插值。
  final Color? gradientTo;

  /// 文字颜色（默认 white；高对比模式下可显式传入）。
  final Color? foregroundColor;

  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final from = gradientFrom ?? colorScheme.primary;
    final to = gradientTo ??
        Color.lerp(colorScheme.primary, colorScheme.tertiary, 0.38) ??
        colorScheme.tertiary;
    final fg = foregroundColor ?? Colors.white;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        gradient: LinearGradient(
          colors: [from, to],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: padding ?? const EdgeInsets.fromLTRB(18, 18, 18, 18),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: fg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null || leading != null || trailing != null)
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (leading != null) ...[
                    leading!,
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  Expanded(
                    child: title == null
                        ? const SizedBox.shrink()
                        : Text(
                            title!,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              color: fg,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
            if (subtitle != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                subtitle!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: fg.withValues(alpha: 0.86),
                  height: 1.45,
                ),
              ),
            ],
            if (subtitleWidget != null) ...[
              const SizedBox(height: AppSpacing.xs),
              subtitleWidget!,
            ],
            if (stats.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: stats
                    .map((stat) => _AccentHeroStatPill(stat: stat, fg: fg))
                    .toList(),
              ),
            ],
            if (footer != null) ...[
              const SizedBox(height: AppSpacing.md),
              footer!,
            ],
          ],
        ),
      ),
    );
  }
}

/// AccentHero 顶部统计区里的一格，例如「当日场地 3」「开放时段 12」。
class AccentHeroStat {
  const AccentHeroStat({required this.label, required this.value, this.icon});

  final String label;
  final String value;
  final IconData? icon;
}

class _AccentHeroStatPill extends StatelessWidget {
  const _AccentHeroStatPill({required this.stat, required this.fg});

  final AccentHeroStat stat;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm + 2,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (stat.icon != null) ...[
                Icon(stat.icon, size: 14, color: fg.withValues(alpha: 0.78)),
                const SizedBox(width: 4),
              ],
              Text(
                stat.value,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            stat.label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: fg.withValues(alpha: 0.78),
            ),
          ),
        ],
      ),
    );
  }
}
