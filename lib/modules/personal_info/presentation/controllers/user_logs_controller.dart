import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di/app_providers.dart';
import '../../../../core/result/result.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../domain/entities/user_log_entry.dart';

/// 通用分页状态：items + 当前最后一页 + total + 加载/错误位 + hasMore。
class PagedLogState {
  const PagedLogState({
    this.items = const [],
    this.pageIndex = 0,
    this.total = 0,
    this.loading = false,
    this.loadingMore = false,
    this.error,
  });

  final List<UserLogEntry> items;
  final int pageIndex;
  final int total;
  final bool loading;
  final bool loadingMore;
  final String? error;

  bool get hasMore => items.length < total;

  PagedLogState copyWith({
    List<UserLogEntry>? items,
    int? pageIndex,
    int? total,
    bool? loading,
    bool? loadingMore,
    Object? error = _sentinel,
  }) {
    return PagedLogState(
      items: items ?? this.items,
      pageIndex: pageIndex ?? this.pageIndex,
      total: total ?? this.total,
      loading: loading ?? this.loading,
      loadingMore: loadingMore ?? this.loadingMore,
      error: identical(error, _sentinel) ? this.error : error as String?,
    );
  }

  static const _sentinel = Object();
}

/// 三种日志各起一个 controller。
abstract class _BaseLogsController extends Notifier<PagedLogState> {
  static const _pageSize = 20;

  UserLogType get type;

  @override
  PagedLogState build() {
    Future.microtask(refresh);
    return const PagedLogState(loading: true);
  }

  Future<void> refresh() async {
    state = state.copyWith(
      loading: true,
      loadingMore: false,
      error: null,
    );
    final session = await _readSession();
    if (session == null) {
      state = const PagedLogState(error: '未登录');
      return;
    }
    final result = await ref.read(schoolPortalGatewayProvider).queryUserLogs(
          session,
          type: type,
          pageIndex: 1,
          pageSize: _pageSize,
        );
    switch (result) {
      case Success(:final data):
        state = PagedLogState(
          items: data.items,
          pageIndex: 1,
          total: data.total,
        );
      case FailureResult(:final failure):
        state = PagedLogState(error: failure.message);
    }
  }

  Future<void> loadMore() async {
    if (state.loading || state.loadingMore) return;
    if (!state.hasMore) return;
    state = state.copyWith(loadingMore: true, error: null);
    final session = await _readSession();
    if (session == null) {
      state = state.copyWith(loadingMore: false, error: '未登录');
      return;
    }
    final next = state.pageIndex + 1;
    final result = await ref.read(schoolPortalGatewayProvider).queryUserLogs(
          session,
          type: type,
          pageIndex: next,
          pageSize: _pageSize,
        );
    switch (result) {
      case Success(:final data):
        state = state.copyWith(
          items: [...state.items, ...data.items],
          pageIndex: next,
          total: data.total,
          loadingMore: false,
        );
      case FailureResult(:final failure):
        state = state.copyWith(
          loadingMore: false,
          error: failure.message,
        );
    }
  }

  Future<dynamic> _readSession() async {
    final auth = await ref.read(authControllerProvider.future);
    return auth.session;
  }
}

class AuthLogsController extends _BaseLogsController {
  @override
  UserLogType get type => UserLogType.authentication;
}

class AppAccessLogsController extends _BaseLogsController {
  @override
  UserLogType get type => UserLogType.appAccess;
}

class PasswordLogsController extends _BaseLogsController {
  @override
  UserLogType get type => UserLogType.passwordMaintain;
}

final authLogsControllerProvider =
    NotifierProvider<AuthLogsController, PagedLogState>(
        AuthLogsController.new);
final appAccessLogsControllerProvider =
    NotifierProvider<AppAccessLogsController, PagedLogState>(
        AppAccessLogsController.new);
final passwordLogsControllerProvider =
    NotifierProvider<PasswordLogsController, PagedLogState>(
        PasswordLogsController.new);

/// 在线会话不分页，整体拉。
class OnlineSessionsState {
  const OnlineSessionsState({
    this.items = const [],
    this.loading = true,
    this.error,
  });

  final List<OnlineSession> items;
  final bool loading;
  final String? error;

  OnlineSessionsState copyWith({
    List<OnlineSession>? items,
    bool? loading,
    Object? error = _sentinel,
  }) {
    return OnlineSessionsState(
      items: items ?? this.items,
      loading: loading ?? this.loading,
      error: identical(error, _sentinel) ? this.error : error as String?,
    );
  }

  static const _sentinel = Object();
}

final onlineSessionsControllerProvider =
    NotifierProvider<OnlineSessionsController, OnlineSessionsState>(
        OnlineSessionsController.new);

class OnlineSessionsController extends Notifier<OnlineSessionsState> {
  @override
  OnlineSessionsState build() {
    Future.microtask(refresh);
    return const OnlineSessionsState();
  }

  Future<void> refresh() async {
    state = state.copyWith(loading: true, error: null);
    final session = await _readSession();
    if (session == null) {
      state = const OnlineSessionsState(loading: false, error: '未登录');
      return;
    }
    final result =
        await ref.read(schoolPortalGatewayProvider).queryOnlineSessions(session);
    switch (result) {
      case Success(:final data):
        state = OnlineSessionsState(items: data, loading: false);
      case FailureResult(:final failure):
        state = OnlineSessionsState(loading: false, error: failure.message);
    }
  }

  /// 踢出指定 [id] 的在线会话。
  Future<KickOnlineResult> kickOnlineSession(String id) async {
    final session = await _readSession();
    if (session == null) return KickOnlineResult.error;
    final result = await ref
        .read(schoolPortalGatewayProvider)
        .kickOnlineSession(session, id: id);
    if (result == KickOnlineResult.success) {
      await refresh();
    }
    return result;
  }

  Future<dynamic> _readSession() async {
    final auth = await ref.read(authControllerProvider.future);
    return auth.session;
  }
}

/// 简单的 IP → 地点缓存。
final ipLocationLookupProvider =
    FutureProvider.autoDispose.family<String?, String>((ref, ip) async {
  return ref.read(schoolPortalGatewayProvider).lookupIpLocation(ip);
});
