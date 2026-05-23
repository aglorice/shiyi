import '../../../core/result/result.dart';
import '../../../integrations/school_portal/sso/sms_login_session.dart';
import '../domain/entities/app_session.dart';
import '../domain/entities/school_credential.dart';
import '../domain/repositories/auth_repository.dart';

class LoginWithSchoolPortalUseCase {
  const LoginWithSchoolPortalUseCase(this._repository);

  final AuthRepository _repository;

  Future<Result<AppSession>> call(
    SchoolCredential credential, {
    Future<bool> Function(SmsLoginSession session)? solveCaptcha,
  }) {
    return _repository.login(credential, solveCaptcha: solveCaptcha);
  }
}
