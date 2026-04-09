import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di/app_providers.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../domain/entities/electricity_dashboard.dart';

final electricityControllerProvider =
    AsyncNotifierProvider<ElectricityController, ElectricityDashboard>(
      ElectricityController.new,
      retry: (_, __) => null,
    );

class ElectricityController extends AsyncNotifier<ElectricityDashboard> {
  ElectricityChargePeriod _currentPeriod = ElectricityChargePeriod.oneYear;

  @override
  Future<ElectricityDashboard> build() async {
    return _load(forceRefresh: false);
  }

  Future<void> refresh({bool forceRefresh = true}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _load(forceRefresh: forceRefresh));
  }

  Future<void> selectPeriod(ElectricityChargePeriod period) async {
    if (_currentPeriod == period) {
      return;
    }
    _currentPeriod = period;
    await refresh();
  }

  Future<void> updateBinding({
    required String building,
    required String roomNumber,
  }) async {
    final normalizedBuilding = building.trim().toUpperCase();
    final normalizedRoom = roomNumber.trim().toUpperCase();
    if (normalizedBuilding.isEmpty || normalizedRoom.isEmpty) {
      throw const BusinessFailure('楼栋和房号不能为空。');
    }

    await ref
        .read(electricityRepositoryProvider)
        .saveBinding(
          ElectricityRoomBinding(
            building: normalizedBuilding,
            roomNumber: normalizedRoom,
          ),
        );

    state = const AsyncLoading();
    final nextState = await AsyncValue.guard(() => _load(forceRefresh: true));
    state = nextState;
    if (nextState case AsyncError(:final error)) {
      throw error;
    }
  }

  Future<ElectricityDashboard> _load({required bool forceRefresh}) async {
    final authState = await ref.watch(authControllerProvider.future);
    final session = authState.session;
    if (session == null) {
      throw const AuthenticationFailure('当前未登录，无法加载电费信息。');
    }

    final result = await ref.read(fetchElectricityDashboardUseCaseProvider)(
      session: session,
      period: _currentPeriod,
      forceRefresh: forceRefresh,
    );

    return result.requireValue();
  }
}
