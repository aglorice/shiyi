// 短信登录五步在 Gateway 层都只是 portalApi 的代理。
part of '../school_portal_gateway.dart';

mixin _SmsLoginGateway on _GatewayBase implements SchoolPortalGateway {
  @override
  Future<Result<SmsLoginSession>> startSmsLogin() {
    return _portalApi.startSmsLogin();
  }

  @override
  Future<Result<SliderCaptchaChallenge>> openSliderCaptcha(
    SmsLoginSession smsSession,
  ) {
    return _portalApi.openSliderCaptcha(smsSession);
  }

  @override
  Future<Result<SliderVerifyResult>> verifySliderCaptcha(
    SmsLoginSession smsSession, {
    required SliderTrackPayload payload,
    required String safeSecure,
  }) {
    return _portalApi.verifySliderCaptcha(
      smsSession,
      payload: payload,
      safeSecure: safeSecure,
    );
  }

  @override
  Future<Result<String>> sendDynamicCode(
    SmsLoginSession smsSession, {
    required String mobile,
  }) {
    return _portalApi.sendDynamicCode(smsSession, mobile: mobile);
  }

  @override
  Future<Result<AppSession>> submitSmsLogin(
    SmsLoginSession smsSession, {
    required String mobile,
    required String dynamicCode,
  }) {
    return _portalApi.submitSmsLogin(
      smsSession,
      mobile: mobile,
      dynamicCode: dynamicCode,
    );
  }
}
