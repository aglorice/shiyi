// 电费接入还没做，先保留占位。
part of '../school_portal_gateway.dart';

mixin _ElectricityGateway on _GatewayBase implements SchoolPortalGateway {
  @override
  Future<Result<ElectricityDashboard>> fetchElectricityDashboard(
    AppSession session,
  ) async {
    return const FailureResult(BusinessFailure('电费查询将在后续接入。'));
  }
}
