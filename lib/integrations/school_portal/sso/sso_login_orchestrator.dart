import '../../../core/result/result.dart';
import '../../../modules/auth/domain/entities/app_session.dart';
import '../../../modules/auth/domain/entities/school_credential.dart';
import '../wyu_portal_api.dart';
import 'sms_login_session.dart';

class SsoLoginOrchestrator {
  const SsoLoginOrchestrator({required WyuPortalApi portalApi})
    : _portalApi = portalApi;

  final WyuPortalApi _portalApi;

  Future<Result<AppSession>> login(
    SchoolCredential credential, {
    Future<bool> Function(SmsLoginSession session)? solveCaptcha,
  }) {
    return _portalApi.login(credential, solveCaptcha: solveCaptcha);
  }
}
