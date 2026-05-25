// 个人中心相关接口在 Gateway 层就是简单代理，没有额外业务逻辑。
part of '../school_portal_gateway.dart';

mixin _PersonalInfoGateway on _GatewayBase implements SchoolPortalGateway {
  @override
  Future<Result<UserLogPage>> queryUserLogs(
    AppSession session, {
    required UserLogType type,
    int pageIndex = 1,
    int pageSize = 10,
  }) {
    return _portalApi.queryUserLogs(
      session,
      type: type,
      pageIndex: pageIndex,
      pageSize: pageSize,
    );
  }

  @override
  Future<Result<List<OnlineSession>>> queryOnlineSessions(
    AppSession session,
  ) {
    return _portalApi.queryOnlineSessions(session);
  }

  @override
  Future<KickOnlineResult> kickOnlineSession(
    AppSession session, {
    required String id,
  }) {
    return _portalApi.kickOnlineSession(session, id: id);
  }

  @override
  Future<String?> lookupIpLocation(String ip) {
    return _portalApi.lookupIpLocation(ip);
  }
}
