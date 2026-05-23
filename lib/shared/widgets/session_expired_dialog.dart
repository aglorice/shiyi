import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/di/app_providers.dart';
import '../../modules/auth/presentation/controllers/auth_controller.dart';
import 'app_snackbar.dart';

enum _SessionExpiredAction { relogin, logout }

/// 登录态失效时弹出的对话框。
///
/// 两种模式：
/// - 本地保存了账号密码（学号+密码登录的用户）：
///   "重新登录" 走 [AuthController.relogin]，自动用保存的凭证再登一次；
/// - 本地没有保存凭证（走过短信验证码登录的用户）：
///   只提供 "去登录"，会清空 session 并把路由跳回 /login，让用户自己挑方式。
Future<void> showSessionExpiredDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  final hasCredential =
      await ref.read(authRepositoryProvider).hasSavedCredential();

  if (!context.mounted) return;

  if (hasCredential) {
    await _showRecoverableDialog(context, ref);
  } else {
    await _showLoginAgainDialog(context, ref);
  }
}

Future<void> _showRecoverableDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  final action = await showDialog<_SessionExpiredAction>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      icon: Icon(
        Icons.lock_outline,
        color: Theme.of(context).colorScheme.error,
      ),
      title: const Text('登录已过期'),
      content: const Text('学校门户登录态已失效。已为你保存了账号密码，是否重新登录？'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, _SessionExpiredAction.logout),
          child: const Text('退出登录'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, _SessionExpiredAction.relogin),
          child: const Text('重新登录'),
        ),
      ],
    ),
  );

  if (!context.mounted) return;

  switch (action) {
    case _SessionExpiredAction.relogin:
      final success = await ref.read(authControllerProvider.notifier).relogin();
      if (context.mounted && !success) {
        AppSnackBar.show(
          context,
          message: '重新登录失败，请检查网络或重新输入密码。',
          tone: AppSnackBarTone.error,
        );
      }
    case _SessionExpiredAction.logout:
      await ref.read(authControllerProvider.notifier).logout();
      if (context.mounted) {
        context.go('/login');
      }
    case null:
      break;
  }
}

Future<void> _showLoginAgainDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      icon: Icon(
        Icons.lock_outline,
        color: Theme.of(context).colorScheme.error,
      ),
      title: const Text('登录已过期'),
      content: const Text(
        '短信验证码登录无法自动续期，需要你重新登录一次。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('稍后处理'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('去登录'),
        ),
      ],
    ),
  );

  if (!context.mounted) return;

  if (confirmed == true) {
    await ref.read(authControllerProvider.notifier).logout();
    if (context.mounted) {
      context.go('/login');
    }
  }
}
