import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/app_providers.dart';
import '../../../core/error/failure.dart';
import '../../../core/result/result.dart';
import '../domain/entities/app_session.dart';
import '../presentation/controllers/auth_controller.dart';

/// 把"会话失效 → 自动刷新 → 用新 session 重试一次"这套样板抽成高阶函数。
///
/// schedule / grades / exams 三个 controller 之前各抄了一份 `_shouldRetryWithRelogin`
/// + `_refreshSessionForRetry`，逻辑完全一样，但凡哪天判定规则升级（比如新加
/// 一种"密码错误次数过多"的失败码），三处都得改。集中到这里以后，
/// 加新的 case 就只动一份。
class RetryWithRelogin<T> {
  RetryWithRelogin(this.ref);

  final Ref ref;

  /// [request] 只接受 session 这一个动态参数；其它定制都由调用方在闭包里固化。
  ///
  /// 流程：
  /// 1. 用当前 [AppSession] 跑一次；
  /// 2. 失败且像"会话失效"时，调 [refreshSessionUseCaseProvider] 拿新 session；
  /// 3. 用新 session 再跑一次；
  /// 4. 任意一步彻底失败，把原始 [Failure] 透传出去；
  ///    若刷新 session 也失败，会顺便把 auth 推进 reauthRequired 状态，
  ///    让 UI 弹"登录已过期"对话框。
  Future<Result<T>> call({
    required AppSession session,
    required Future<Result<T>> Function(AppSession session) request,
  }) async {
    final first = await request(session);
    if (first case FailureResult<T>(failure: final failure)
        when shouldRetry(failure)) {
      final refreshed = await _refreshSessionForRetry(failure);
      if (refreshed != null) {
        return request(refreshed);
      }
    }
    return first;
  }

  Future<AppSession?> _refreshSessionForRetry(Failure triggerFailure) async {
    final refreshResult = await ref.read(refreshSessionUseCaseProvider)();
    if (refreshResult case Success<AppSession>(data: final session)) {
      ref.read(authControllerProvider.notifier).replaceSession(session);
      return session;
    }
    ref
        .read(authControllerProvider.notifier)
        .requireReauth(refreshResult.failureOrNull ?? triggerFailure);
    return null;
  }

  /// 是否值得自动重试。命中下列两类即重试：
  /// - 显式标注的 [SessionExpiredFailure]
  /// - 失败 message 里出现学校系统常见的"未登录/已登出"提示文案
  static bool shouldRetry(Failure failure) {
    if (failure is SessionExpiredFailure) {
      return true;
    }
    return _looksLikeSessionExpiredMessage(failure.message);
  }

  static bool _looksLikeSessionExpiredMessage(String message) {
    return message.contains('尚未登录') ||
        message.contains('请先登录') ||
        message.contains('登录失效') ||
        message.contains('已在别处登录') ||
        message.contains('被迫退出');
  }
}
