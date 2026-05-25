import 'package:flutter/material.dart';

import '../../../../app/theme/design_tokens.dart';

/// 登录页用的内联错误提示。
/// 视觉是一条柔和的红底胶囊：底色 errorContainer，文字 onErrorContainer。
/// 比一行散装 Icon+Text 更克制，也比 SnackBar 更稳定（不会突然冒出来又消失）。
class InlineErrorBanner extends StatelessWidget {
  const InlineErrorBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: tone.errorContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: tone.error.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 18,
            color: tone.error,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: tone.onErrorContainer,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
