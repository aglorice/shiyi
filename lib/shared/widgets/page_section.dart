import 'package:flutter/material.dart';

import '../../app/theme/design_tokens.dart';

/// 页面分组：直接铺在 scaffold 背景上，不再包卡片。
///
/// 构成：
/// - 顶部一行小号灰字「分组标题」（可选）；
/// - 一组无背景的 [children]，由调用方决定是 list tile 还是其他 widget；
/// - 子项之间用极淡分隔线（也可以用 [SectionDivider]）。
///
/// 与之前 SettingsSection（带 SurfaceCard）相比，这个组件几乎不画线，
/// 让"分组"的概念靠间距和字号差表达，是小红书 / iOS Settings 的常见做法。
class PageSection extends StatelessWidget {
  const PageSection({
    super.key,
    this.title,
    this.action,
    required this.children,
    this.divider = true,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppSpacing.pageH,
    ),
  });

  final String? title;

  /// 标题右侧的可选小操作（例如「查看全部」）。
  final Widget? action;

  /// 一行行的子项。
  final List<Widget> children;

  /// 子项之间是否插淡分隔线。
  final bool divider;

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (divider && i < children.length - 1) {
        rows.add(const SectionDivider());
      }
    }

    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.lg, bottom: AppSpacing.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title!,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                  if (action != null) action!,
                ],
              ),
            ),
          ],
          ...rows,
        ],
      ),
    );
  }
}

/// 一条极淡分隔线。仅用来界定 [PageSection] 内子项之间的边界。
class SectionDivider extends StatelessWidget {
  const SectionDivider({super.key, this.indent = 56});

  /// 左侧缩进（默认对齐图标右侧的文字位置）。
  final double indent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: indent),
      child: Divider(
        height: 0.6,
        thickness: 0.6,
        color: Theme.of(context)
            .colorScheme
            .outlineVariant
            .withValues(alpha: 0.55),
      ),
    );
  }
}

/// 页面顶部大标题。
/// 接近小红书风格——大字直接顶在内容前，不依赖 AppBar。
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.pageH,
      AppSpacing.lg,
      AppSpacing.pageH,
      AppSpacing.sm,
    ),
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
