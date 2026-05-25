import 'package:flutter/material.dart';

import '../../../../app/theme/design_tokens.dart';

/// 账号密码 / 短信验证码 两种登录方式的开关。
/// 视觉上是一条软底色的胶囊条，选中态用主色 outline + 加粗文字，
/// 与 Material SegmentedButton 比起来更轻量、更小红书。
enum LoginMethod { password, sms }

class LoginMethodSwitch extends StatelessWidget {
  const LoginMethodSwitch({
    super.key,
    required this.current,
    required this.onChanged,
  });

  final LoginMethod current;
  final ValueChanged<LoginMethod> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SwitchSegment(
              label: '账号密码',
              selected: current == LoginMethod.password,
              onTap: () => onChanged(LoginMethod.password),
            ),
          ),
          Expanded(
            child: _SwitchSegment(
              label: '短信验证码',
              selected: current == LoginMethod.sms,
              onTap: () => onChanged(LoginMethod.sms),
            ),
          ),
        ],
      ),
    );
  }
}

class _SwitchSegment extends StatelessWidget {
  const _SwitchSegment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: selected ? null : onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? theme.brightness == Brightness.light
                  ? Colors.white
                  : theme.colorScheme.surfaceContainerHigh
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            color: selected
                ? theme.colorScheme.onSurface
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
