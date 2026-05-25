import 'package:flutter/material.dart';

import '../../app/theme/design_tokens.dart';
import '../../core/error/failure.dart';

/// 全 app 通用的"模块加载失败"占位。
///
/// 形态：图标 + 一行解释 + 重试按钮（可选）。
/// 当 [failure] 是 [SessionExpiredFailure] 时副标题会变成"需要重新登录"。
class ModuleErrorState extends StatelessWidget {
  const ModuleErrorState({
    super.key,
    required this.message,
    this.icon,
    this.failure,
    this.onRetry,
    this.onSecondary,
    this.secondaryLabel,
    this.compact = false,
  });

  final String message;
  final IconData? icon;
  final Failure? failure;
  final Future<void> Function()? onRetry;

  /// 例如「重新登录」「修改账号」等次级动作。
  final Future<void> Function()? onSecondary;
  final String? secondaryLabel;

  /// compact=true 时高度更小，没有大量边距，便于嵌在卡片里。
  final bool compact;

  bool get _sessionExpired => failure is SessionExpiredFailure;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = theme.colorScheme.error;
    final iconData = icon ??
        (_sessionExpired
            ? Icons.lock_outline_rounded
            : Icons.error_outline_rounded);

    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: compact ? AppSpacing.md : AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(iconData, size: compact ? 28 : 40, color: tone),
            SizedBox(height: compact ? AppSpacing.sm : AppSpacing.md),
            Text(
              _sessionExpired ? '登录已过期' : '加载失败',
              style: (compact
                      ? theme.textTheme.titleSmall
                      : theme.textTheme.titleMedium)
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              _sessionExpired ? '需要重新登录后再试一次' : message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (onRetry != null || onSecondary != null) ...[
              SizedBox(height: compact ? AppSpacing.md : AppSpacing.lg),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (onSecondary != null) ...[
                    OutlinedButton(
                      onPressed: () => onSecondary!(),
                      child: Text(secondaryLabel ?? '其他操作'),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  if (onRetry != null)
                    FilledButton.tonal(
                      onPressed: () => onRetry!(),
                      child: const Text('重试'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
