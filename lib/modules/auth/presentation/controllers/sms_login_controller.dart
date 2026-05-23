import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di/app_providers.dart';
import '../../../../core/result/result.dart';
import '../../../../integrations/school_portal/sso/slider_captcha.dart';
import '../../../../integrations/school_portal/sso/sms_login_session.dart';
import '../../domain/entities/app_session.dart';
import 'auth_controller.dart';

/// 短信登录页的整体阶段。
enum SmsLoginPhase {
  /// 初始空白：未做任何动作。
  idle,

  /// 已经请求"获取验证码"，但还未通过滑块。
  /// 滑块 sheet 此时应当展示，用户在拖。
  awaitingSlider,

  /// 滑块已通过，正在向服务端请求发短信。
  sendingSms,

  /// 短信已发出，进入 60s 倒计时；用户填验证码。
  smsSent,

  /// 用户点了"登录"，正在提交。
  loggingIn,
}

/// 短信登录页的对外状态。
class SmsLoginState {
  const SmsLoginState({
    this.phase = SmsLoginPhase.idle,
    this.smsSession,
    this.challenge,
    this.mobile,
    this.errorMessage,
    this.cooldownSeconds = 0,
  });

  final SmsLoginPhase phase;
  final SmsLoginSession? smsSession;
  final SliderCaptchaChallenge? challenge;
  final String? mobile;
  final String? errorMessage;

  /// 距离下一次可重发短信的秒数；0 表示可发。
  final int cooldownSeconds;

  bool get canSendCode =>
      cooldownSeconds == 0 &&
      phase != SmsLoginPhase.awaitingSlider &&
      phase != SmsLoginPhase.sendingSms;

  SmsLoginState copyWith({
    SmsLoginPhase? phase,
    SmsLoginSession? smsSession,
    bool clearChallenge = false,
    SliderCaptchaChallenge? challenge,
    String? mobile,
    bool clearError = false,
    String? errorMessage,
    int? cooldownSeconds,
  }) {
    return SmsLoginState(
      phase: phase ?? this.phase,
      smsSession: smsSession ?? this.smsSession,
      challenge: clearChallenge ? null : (challenge ?? this.challenge),
      mobile: mobile ?? this.mobile,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      cooldownSeconds: cooldownSeconds ?? this.cooldownSeconds,
    );
  }
}

final smsLoginControllerProvider =
    NotifierProvider<SmsLoginController, SmsLoginState>(SmsLoginController.new);

class SmsLoginController extends Notifier<SmsLoginState> {
  @override
  SmsLoginState build() => const SmsLoginState();

  /// 用户点"获取验证码"。
  ///
  /// 流程：startSmsLogin → openSliderCaptcha → 进入 awaitingSlider 阶段，
  /// 由 UI 层弹滑块 sheet 让用户拖。
  Future<void> requestSliderChallenge({required String mobile}) async {
    if (mobile.trim().length != 11) {
      state = state.copyWith(errorMessage: '请输入 11 位手机号');
      return;
    }
    if (state.phase == SmsLoginPhase.awaitingSlider ||
        state.phase == SmsLoginPhase.sendingSms) {
      return;
    }

    state = state.copyWith(
      phase: SmsLoginPhase.awaitingSlider,
      mobile: mobile.trim(),
      clearError: true,
    );

    final gateway = ref.read(schoolPortalGatewayProvider);
    final startResult = await gateway.startSmsLogin();
    if (startResult case FailureResult<SmsLoginSession>(failure: final f)) {
      state = state.copyWith(
        phase: SmsLoginPhase.idle,
        errorMessage: f.message,
      );
      return;
    }

    final smsSession = startResult.requireValue();
    final challengeResult = await gateway.openSliderCaptcha(smsSession);
    if (challengeResult
        case FailureResult<SliderCaptchaChallenge>(failure: final f)) {
      state = state.copyWith(
        phase: SmsLoginPhase.idle,
        smsSession: smsSession,
        errorMessage: f.message,
      );
      return;
    }

    state = state.copyWith(
      phase: SmsLoginPhase.awaitingSlider,
      smsSession: smsSession,
      challenge: challengeResult.requireValue(),
    );
  }

  /// 用户在滑块上松手时调用：仅做滑块 verify，不发短信。
  /// 返回 true 即滑块校验通过；调用方拿到 true 之后才去发短信。
  Future<bool> verifySliderOnly({
    required SliderTrackPayload payload,
  }) async {
    final session = state.smsSession;
    final challenge = state.challenge;
    if (session == null || challenge == null) {
      state = state.copyWith(errorMessage: '滑块挑战已失效，请重试。');
      return false;
    }
    final gateway = ref.read(schoolPortalGatewayProvider);
    final verify = await gateway.verifySliderCaptcha(
      session,
      payload: payload,
      safeSecure: challenge.safeSecure,
    );
    if (verify case FailureResult<SliderVerifyResult>(failure: final f)) {
      state = state.copyWith(errorMessage: f.message);
      return false;
    }
    final result = verify.requireValue();
    if (!result.passed) {
      // 拖错或被风控：换张图给用户重试，sheet 不关。
      await refreshChallenge();
      return false;
    }
    return true;
  }

  /// 滑块通过、sheet 已经关闭后，由页面层调用一次发短信。
  /// 不进入 awaitingSlider 阶段，直接 sendingSms → smsSent 或回到 idle。
  Future<void> requestDynamicCode() async {
    final session = state.smsSession;
    final mobile = state.mobile;
    if (session == null || mobile == null) {
      state = state.copyWith(errorMessage: '会话已失效，请重试。');
      return;
    }
    state = state.copyWith(
      phase: SmsLoginPhase.sendingSms,
      clearChallenge: true,
      clearError: true,
    );
    final gateway = ref.read(schoolPortalGatewayProvider);
    final sendResult = await gateway.sendDynamicCode(
      session,
      mobile: mobile,
    );
    if (sendResult case FailureResult<String>(failure: final f)) {
      // 短信发送失败：回到 idle 让用户改号或重新点获取验证码（会重新出滑块）
      state = state.copyWith(
        phase: SmsLoginPhase.idle,
        errorMessage: f.message,
      );
      return;
    }
    state = state.copyWith(
      phase: SmsLoginPhase.smsSent,
      cooldownSeconds: 60,
    );
    _runCooldown();
  }

  /// 用户在滑块 sheet 里点"换一张"，或滑块校验失败后自动调。
  Future<void> refreshChallenge() async {
    final session = state.smsSession;
    if (session == null) return;
    final gateway = ref.read(schoolPortalGatewayProvider);
    final challengeResult = await gateway.openSliderCaptcha(session);
    if (challengeResult
        case FailureResult<SliderCaptchaChallenge>(failure: final f)) {
      state = state.copyWith(errorMessage: f.message);
      return;
    }
    state = state.copyWith(
      challenge: challengeResult.requireValue(),
      clearError: true,
    );
  }

  /// 用户在滑块 sheet 上点关闭。
  void cancelSlider() {
    state = state.copyWith(
      phase: SmsLoginPhase.idle,
      clearChallenge: true,
    );
  }

  /// 用户最终点"登录"。
  Future<bool> submitLogin({
    required String mobile,
    required String code,
  }) async {
    final session = state.smsSession;
    if (session == null) {
      state = state.copyWith(errorMessage: '请先获取验证码。');
      return false;
    }
    if (code.trim().length != 6) {
      state = state.copyWith(errorMessage: '请输入 6 位验证码。');
      return false;
    }
    state = state.copyWith(phase: SmsLoginPhase.loggingIn, clearError: true);

    final gateway = ref.read(schoolPortalGatewayProvider);
    final result = await gateway.submitSmsLogin(
      session,
      mobile: mobile.trim(),
      dynamicCode: code.trim(),
    );
    if (result case FailureResult<AppSession>(failure: final f)) {
      state = state.copyWith(
        phase: SmsLoginPhase.smsSent,
        errorMessage: f.message,
      );
      return false;
    }

    final appSession = result.requireValue();
    // 持久化 + 把 authController 的 state 切到 authenticated。
    // 注意：短信流没有可重用的 password，所以不会进 credentialVault。
    // 下次 cold start 走 restoreSession，session 还在；
    // 一旦过期且没有 credential，就会被引导回登录页（其实可以再次走短信流）。
    await ref.read(authRepositoryProvider).saveSession(appSession);
    ref
        .read(authControllerProvider.notifier)
        .replaceSession(appSession);

    // 重置自身状态，便于下次进入。
    state = const SmsLoginState();
    return true;
  }

  void _runCooldown() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      final remaining = state.cooldownSeconds - 1;
      if (remaining <= 0) {
        state = state.copyWith(cooldownSeconds: 0);
        return false;
      }
      state = state.copyWith(cooldownSeconds: remaining);
      return true;
    });
  }
}
