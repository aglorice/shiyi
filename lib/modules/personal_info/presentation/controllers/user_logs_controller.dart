import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di/app_providers.dart';
import '../../../../core/result/result.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../domain/entities/user_log_entry.dart';

/// 个人中心几条 Tab 的统一加载状态。
class UserLogsState {
  const UserLogsState({
    this.online = const AsyncValue<List<OnlineSession>>.loading(),
    this.authLogs = const AsyncValue<UserLogPage>.loading(),
    this.appLogs = const AsyncValue<UserLogPage>.loading(),
    this.pwdLogs = const AsyncValue<UserLogPage>.loading(),
  });

  final AsyncValue<List<OnlineSession>> online;
  final AsyncValue<UserLogPage> authLogs;
  final AsyncValue<UserLogPage> appLogs;
  final AsyncValue<UserLogPage> pwdLogs;

  UserLogsState copyWith({
    AsyncValue<List<OnlineSession>>? online,
    AsyncValue<UserLogPage>? authLogs,
    AsyncValue<UserLogPage>? appLogs,
    AsyncValue<UserLogPage>? pwdLogs,
  }) {
    return UserLogsState(
      online: online ?? this.online,
      authLogs: authLogs ?? this.authLogs,
      appLogs: appLogs ?? this.appLogs,
      pwdLogs: pwdLogs ?? this.pwdLogs,
    );
  }
}

final userLogsControllerProvider =
    NotifierProvider<UserLogsController, UserLogsState>(
        UserLogsController.new);

class UserLogsController extends Notifier<UserLogsState> {
  @override
  UserLogsState build() {
    Future.microtask(loadAll);
    return const UserLogsState();
  }

  Future<void> loadAll() async {
    await Future.wait([
      refreshOnline(),
      refreshLogs(UserLogType.authentication),
      refreshLogs(UserLogType.appAccess),
      refreshLogs(UserLogType.passwordMaintain),
    ]);
  }

  Future<void> refreshOnline() async {
    state = state.copyWith(online: const AsyncValue.loading());
    final session = await _readSession();
    if (session == null) {
      state = state.copyWith(
        online: AsyncValue.error('未登录', StackTrace.current),
      );
      return;
    }
    final result = await ref.read(schoolPortalGatewayProvider).queryOnlineSessions(session);
    state = state.copyWith(
      online: switch (result) {
        Success(:final data) => AsyncValue.data(data),
        FailureResult(:final failure) =>
          AsyncValue.error(failure.message, StackTrace.current),
      },
    );
  }

  /// 踢出指定 [id] 的在线会话。
  /// 返回 [KickOnlineResult]：调用方负责响应 selfKicked（清本地登录态）。
  Future<KickOnlineResult> kickOnlineSession(String id) async {
    final session = await _readSession();
    if (session == null) return KickOnlineResult.error;
    final result = await ref
        .read(schoolPortalGatewayProvider)
        .kickOnlineSession(session, id: id);
    if (result == KickOnlineResult.success) {
      await refreshOnline();
    }
    return result;
  }

  Future<void> refreshLogs(UserLogType type) async {
    void apply(AsyncValue<UserLogPage> v) {
      switch (type) {
        case UserLogType.authentication:
          state = state.copyWith(authLogs: v);
        case UserLogType.appAccess:
          state = state.copyWith(appLogs: v);
        case UserLogType.passwordMaintain:
          state = state.copyWith(pwdLogs: v);
      }
    }

    apply(const AsyncValue.loading());
    final session = await _readSession();
    if (session == null) {
      apply(AsyncValue.error('未登录', StackTrace.current));
      return;
    }
    final result = await ref
        .read(schoolPortalGatewayProvider)
        .queryUserLogs(session, type: type, pageSize: 30);
    apply(switch (result) {
      Success(:final data) => AsyncValue.data(data),
      FailureResult(:final failure) =>
        AsyncValue.error(failure.message, StackTrace.current),
    });
  }

  Future<dynamic> _readSession() async {
    final auth = await ref.read(authControllerProvider.future);
    return auth.session;
  }
}

/// 简单的 IP → 地点缓存：一次输入一个 IP，按 IP 分发请求。
final ipLocationLookupProvider =
    FutureProvider.autoDispose.family<String?, String>((ref, ip) async {
  return ref.read(schoolPortalGatewayProvider).lookupIpLocation(ip);
});
