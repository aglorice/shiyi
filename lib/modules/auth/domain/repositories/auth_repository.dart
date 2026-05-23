import '../../../../core/result/result.dart';
import '../entities/app_session.dart';
import '../entities/school_credential.dart';

abstract class AuthRepository {
  Future<Result<AppSession>> login(SchoolCredential credential);
  Future<Result<AppSession?>> restoreSession();
  Future<Result<AppSession>> refreshSession();
  Future<void> logout();

  /// 持久化一个已经在外部（如短信登录）拿到的完整 [AppSession]。
  /// 不会保存任何 [SchoolCredential]，因为短信流没有可重用的密码。
  Future<void> saveSession(AppSession session);

  /// 是否本地保存了可用于自动 relogin 的账号密码。
  /// 短信登录的用户不会保存凭证，过期后只能引导重新走登录流。
  Future<bool> hasSavedCredential();
}
