import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di/app_providers.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../../auth/domain/entities/app_session.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../domain/entities/schedule_snapshot.dart';

final scheduleControllerProvider =
    AsyncNotifierProvider<ScheduleController, ScheduleSnapshot>(
      ScheduleController.new,
    );

class ScheduleController extends AsyncNotifier<ScheduleSnapshot> {
  String? _selectedTermId;

  @override
  Future<ScheduleSnapshot> build() async {
    return _load(forceRefresh: false);
  }

  Future<bool> changeTerm(String termId) async {
    if (_selectedTermId == termId && state.value != null) {
      return true;
    }
    final previousTermId = _selectedTermId;
    final previousState = state;
    _selectedTermId = termId;
    state = const AsyncLoading();
    final newState = await AsyncValue.guard(() => _load(forceRefresh: true));
    if (newState is AsyncError &&
        previousState is AsyncData<ScheduleSnapshot>) {
      _selectedTermId = previousTermId;
      state = previousState;
      return false;
    }
    state = newState;
    return true;
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _load(forceRefresh: true));
  }

  Future<ScheduleSnapshot> _load({required bool forceRefresh}) async {
    final authState = await ref.watch(authControllerProvider.future);
    final session = authState.session;
    if (session == null) {
      throw const AuthenticationFailure('当前未登录，无法加载课表。');
    }

    var result = await ref.read(fetchScheduleUseCaseProvider)(
      session: session,
      termId: _selectedTermId,
      forceRefresh: forceRefresh,
    );
    if (result case FailureResult<ScheduleSnapshot>(
      failure: final failure,
    ) when _shouldRetryWithRelogin(failure)) {
      final refreshedSession = await _refreshSessionForRetry(failure);
      if (refreshedSession != null) {
        result = await ref.read(fetchScheduleUseCaseProvider)(
          session: refreshedSession,
          termId: _selectedTermId,
          forceRefresh: true,
        );
      }
    }

    final snapshot = result.requireValue();
    _selectedTermId = snapshot.term.id;
    return snapshot;
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

  bool _shouldRetryWithRelogin(Failure failure) {
    if (failure is SessionExpiredFailure) {
      return true;
    }
    return _looksLikeSessionExpiredMessage(failure.message);
  }

  bool _looksLikeSessionExpiredMessage(String message) {
    return message.contains('尚未登录') ||
        message.contains('请先登录') ||
        message.contains('登录失效') ||
        message.contains('已在别处登录') ||
        message.contains('被迫退出');
  }
}
