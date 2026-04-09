import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di/app_providers.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/schedule_snapshot.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';

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

  Future<void> changeTerm(String termId) async {
    if (_selectedTermId == termId && state.value != null) {
      return;
    }
    final previousTermId = _selectedTermId;
    final previousState = state;
    _selectedTermId = termId;
    state = const AsyncLoading();
    final newState = await AsyncValue.guard(() => _load(forceRefresh: true));
    if (newState is AsyncError && previousState is AsyncData<ScheduleSnapshot>) {
      _selectedTermId = previousTermId;
      state = previousState;
    } else {
      state = newState;
    }
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

    final result = await ref.read(fetchScheduleUseCaseProvider)(
      session: session,
      termId: _selectedTermId,
      forceRefresh: forceRefresh,
    );

    final snapshot = result.requireValue();
    _selectedTermId = snapshot.term.id;
    return snapshot;
  }
}
