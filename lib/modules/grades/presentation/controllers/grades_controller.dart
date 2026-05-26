import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di/app_providers.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../../auth/application/retry_with_relogin.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../domain/entities/grades_snapshot.dart';

final gradesControllerProvider =
    AsyncNotifierProvider<GradesController, GradesSnapshot>(
      GradesController.new,
    );

class GradesController extends AsyncNotifier<GradesSnapshot> {
  String? _selectedTermId;

  @override
  Future<GradesSnapshot> build() async {
    return _load(forceRefresh: false);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _load(forceRefresh: true));
  }

  Future<bool> changeTerm(String termId) async {
    if (_selectedTermId == termId && state.value != null) {
      return true;
    }

    final previousTermId = _selectedTermId;
    final previousState = state;
    _selectedTermId = termId;
    state = const AsyncLoading();
    final newState = await AsyncValue.guard(
      () => _load(forceRefresh: true, termId: termId),
    );
    if (newState is AsyncError && previousState is AsyncData<GradesSnapshot>) {
      _selectedTermId = previousTermId;
      state = previousState;
      return false;
    }
    state = newState;
    return true;
  }

  Future<GradesSnapshot> _load({
    required bool forceRefresh,
    String? termId,
  }) async {
    final authState = await ref.watch(authControllerProvider.future);
    final session = authState.session;
    if (session == null) {
      throw const AuthenticationFailure('当前未登录，无法加载成绩。');
    }

    final effectiveTermId = termId ?? _selectedTermId;
    final result = await RetryWithRelogin<GradesSnapshot>(ref).call(
      session: session,
      request: (s) => ref.read(fetchGradesUseCaseProvider)(
        session: s,
        termId: effectiveTermId,
        forceRefresh: forceRefresh || s != session,
      ),
    );

    final snapshot = result.requireValue();
    _selectedTermId = snapshot.selectedTerm?.id;
    if (effectiveTermId != null &&
        effectiveTermId.isEmpty &&
        snapshot.selectedTerm == null) {
      _selectedTermId = '';
    }
    return snapshot;
  }
}
