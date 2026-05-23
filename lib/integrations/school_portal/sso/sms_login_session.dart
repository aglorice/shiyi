import '../../../modules/auth/domain/entities/app_session.dart';

/// 短信登录流程内部使用的"挑战上下文"。
///
/// 整个 SMS 登录流（开页 → 滑块 → 发短信 → 提交）需要在多次请求之间
/// 共享同一份 cookies 与表单字段。这里把它打成一个不透明的句柄，
/// 由 gateway 创建并在控制器层透传，避免直接暴露内部 cookie store。
class SmsLoginSession {
  SmsLoginSession({
    required this.pwdEncryptSalt,
    required this.lt,
    required this.execution,
    required this.cookies,
  });

  final String pwdEncryptSalt;
  final String lt;
  final String execution;

  /// 当前已经累计到的服务端 cookies。每次后续请求会再 absorb 进去。
  List<PortalCookie> cookies;
}
