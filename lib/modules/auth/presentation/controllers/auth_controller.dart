import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di/app_providers.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../../../integrations/school_portal/sso/sms_login_session.dart';
import '../../domain/entities/app_session.dart';
import '../../domain/entities/auth_state.dart';
import '../../domain/entities/school_credential.dart';

final authControllerProvider = AsyncNotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

class AuthController extends AsyncNotifier<AuthState> {
  @override
  Future<AuthState> build() async {
    return _restore();
  }

  Future<void> login({
    required String username,
    required String password,
    Future<bool> Function(SmsLoginSession session)? solveCaptcha,
  }) async {
    state = const AsyncLoading();

    final result = await ref.read(loginWithSchoolPortalUseCaseProvider)(
      SchoolCredential(username: username.trim(), password: password),
      solveCaptcha: solveCaptcha,
    );

    state = AsyncData(_mapSessionResult(result));
  }

  Future<void> logout() async {
    await ref.read(logoutUseCaseProvider)();
    state = const AsyncData(AuthState.unauthenticated());
  }

  Future<void> restore() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_restore);
  }

  /// Uses saved credentials to re-login. Returns `true` on success.
  Future<bool> relogin() async {
    final result = await ref.read(refreshSessionUseCaseProvider)();
    if (result case Success<AppSession>(data: final session)) {
      state = AsyncData(AuthState.authenticated(session));
      return true;
    }
    return false;
  }

  /// Replace the current session with a freshly refreshed one.
  void replaceSession(AppSession session) {
    state = AsyncData(AuthState.authenticated(session));
  }

  /// Force the UI into the re-authentication flow.
  void requireReauth(Failure failure) {
    state = AsyncData(AuthState.reauthRequired(failure));
  }

  AuthState _mapSessionResult(Result<AppSession> result) {
    if (result case Success<AppSession>(data: final session)) {
      return AuthState.authenticated(session);
    }

    return AuthState.reauthRequired(result.failureOrNull!);
  }

  Future<AuthState> _restore() async {
    final result = await ref.read(restoreSessionUseCaseProvider)();
    return switch (result) {
      Success<AppSession?>(data: final session?) => AuthState.authenticated(
        session,
      ),
      Success<AppSession?>(data: null) => const AuthState.unauthenticated(),
      FailureResult<AppSession?>(failure: final failure) =>
        AuthState.reauthRequired(failure),
    };
  }
}
