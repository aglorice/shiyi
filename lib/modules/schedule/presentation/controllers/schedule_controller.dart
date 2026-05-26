import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di/app_providers.dart';
import '../../../../app/settings/app_preferences_controller.dart';
import '../../../../core/error/error_display.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/models/data_origin.dart';
import '../../../../core/result/result.dart';
import '../../../auth/application/retry_with_relogin.dart';
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

    final result = await RetryWithRelogin<ScheduleSnapshot>(ref).call(
      session: session,
      request: (s) => ref.read(fetchScheduleUseCaseProvider)(
        session: s,
        termId: _selectedTermId,
        // 重试那一次必须强刷新，避免又命中第一次失败前写入的脏缓存。
        forceRefresh: forceRefresh || s != session,
      ),
    );

    if (result.isSuccess) {
      final snapshot = result.requireValue();
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
}
