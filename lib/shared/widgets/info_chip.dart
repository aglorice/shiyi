import 'package:flutter/material.dart';

import '../../app/theme/design_tokens.dart';

/// 通用「标签 chip」，用来替换之前各模块自己写的 _TagChip / _MetaChip /
/// _TimeChip 等若干份相似实现。
///
/// 调用方式：
/// ```dart
/// InfoChip(label: '羽毛球');
/// InfoChip(label: '违约', tone: theme.colorScheme.error);
/// InfoChip(label: '已使用', tone: theme.colorScheme.primary, filled: true);
/// ```
class InfoChip extends StatelessWidget {
  const InfoChip({
    super.key,
    required this.label,
    this.tone,
    this.icon,
    this.filled = false,
    this.dense = false,
  });

  final String label;

  /// 主色调，默认走 [ColorScheme.onSurfaceVariant]，也就是中性灰。
  final Color? tone;
  final IconData? icon;

  /// 实心样式（背景色更深，文本反白），默认是淡色描边版。
  final bool filled;

  /// 紧凑模式：减一些垂直内边距。
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = tone ?? theme.colorScheme.onSurfaceVariant;
    final bg = filled ? color : color.withValues(alpha: 0.12);
    final fg = filled ? theme.colorScheme.surface : color;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: dense ? 3 : AppSpacing.xxs + 1,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
