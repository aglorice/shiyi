// 学号密码登录、刷新 session、session 校验、注销。
// 这一组方法本质上是把 [SsoLoginOrchestrator] / [SessionValidator] / [WyuPortalApi]
// 的能力通过 Gateway 接口暴露出去。
part of '../school_portal_gateway.dart';

mixin _AuthGateway on _GatewayBase implements SchoolPortalGateway {
  @override
  Future<Result<AppSession>> login(
    SchoolCredential credential, {
    Future<bool> Function(SmsLoginSession session)? solveCaptcha,
  }) {
    return _loginOrchestrator.login(credential, solveCaptcha: solveCaptcha);
  }

  @override
  Future<Result<AppSession>> refreshSession(SchoolCredential credential) {
    return _loginOrchestrator.login(credential);
  }

  @override
  Future<Result<void>> validateSession(AppSession session) {
    return _sessionValidator.validate(session);
  }

  @override
  Future<Result<void>> logout(AppSession session) {
    return _portalApi.logout(session);
  }
}
