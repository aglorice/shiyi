import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di/app_providers.dart';
import '../../../../app/settings/app_preferences_controller.dart';
import '../../../../core/error/error_display.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/models/data_origin.dart';
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
    // Restore persisted term selection.
    final savedTermId = ref.read(appPreferencesControllerProvider).selectedTermId;
    if (savedTermId != null && savedTermId.isNotEmpty) {
      _selectedTermId = savedTermId;
    }
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
    // Persist the selected term.
    ref.read(appPreferencesControllerProvider.notifier).setSelectedTermId(termId);
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

    if (result case Success<ScheduleSnapshot>(data: final snapshot)) {
      _selectedTermId = snapshot.term.id;
      // Auto-sync the week from the server so that the week can
      // auto-advance even if the user never manually picked one.
      if (snapshot.currentWeek != null) {
        ref
            .read(appPreferencesControllerProvider.notifier)
            .syncScheduleWeekFromServer(snapshot.currentWeek!);
      }
      return snapshot;
    }

    // Remote failed and no cache available – return an empty snapshot so the
    // UI can still render the schedule shell (top bar, term picker, etc.)
    // instead of a full-page error.
    final failure = result.failureOrNull!;
    final errorMessage = formatError(failure).message;
    final termId = _selectedTermId ?? '';
    return ScheduleSnapshot(
      term: Term(id: termId, name: '未知学期'),
      availableTerms: termId.isNotEmpty
          ? [Term(id: termId, name: '未知学期')]
          : <Term>[],
      courses: const [],
      fetchedAt: DateTime.now(),
      origin: DataOrigin.cache,
      loadError: errorMessage,
    );
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
