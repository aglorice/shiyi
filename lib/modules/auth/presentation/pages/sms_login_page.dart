import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/di/app_providers.dart';
import '../../../../app/theme/design_tokens.dart';
import '../../../../integrations/school_portal/sso/slider_captcha.dart';
import '../../../../shared/widgets/app_snackbar.dart';
import '../controllers/sms_login_controller.dart';
import '../widgets/inline_error_banner.dart';
import '../widgets/login_method_switch.dart';
import '../widgets/slider_captcha_sheet.dart';

class SmsLoginPage extends ConsumerStatefulWidget {
  const SmsLoginPage({super.key});

  @override
  ConsumerState<SmsLoginPage> createState() => _SmsLoginPageState();
}

class _SmsLoginPageState extends ConsumerState<SmsLoginPage> {
  final _mobileController = TextEditingController();
  final _codeController = TextEditingController();

  @override
  void dispose() {
    _mobileController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(smsLoginControllerProvider);
    final theme = Theme.of(context);

    // 错误用 SnackBar 给一次反馈，再用页内 banner 持续显示，
    // 防止用户错过短暂的 SnackBar 之后不知道为什么按钮还在 disable。
    ref.listen<SmsLoginState>(smsLoginControllerProvider, (prev, next) {
      final msg = next.errorMessage;
      if (msg != null && msg.isNotEmpty && msg != prev?.errorMessage) {
        AppSnackBar.show(
          context,
          message: msg,
          tone: AppSnackBarTone.error,
        );
      }
    });

    final mobileLooksValid = _mobileController.text.trim().length == 11;
    final canSendCode = mobileLooksValid && state.canSendCode;
    final isLoggingIn = state.phase == SmsLoginPhase.loggingIn;
    final canSubmit = state.smsSession != null &&
        _codeController.text.trim().length == 6 &&
        !isLoggingIn;

    return Scaffold(
      // 自带返回，不再额外画一个 AppBar 让品牌区被压扁。
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 56),
                  const _SmsBrandHeader(),
                  const SizedBox(height: AppSpacing.xl),
                  LoginMethodSwitch(
                    current: LoginMethod.sms,
                    onChanged: (method) {
                      if (method == LoginMethod.password) {
                        // 在两个登录页之间互换，不堆栈。
                        if (context.canPop()) {
                          context.pop();
                        } else {
                          context.pushReplacement('/login');
                        }
                      }
                    },
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  TextField(
                    controller: _mobileController,
                    keyboardType: TextInputType.phone,
                    maxLength: 11,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    decoration: const InputDecoration(
                      labelText: '手机号',
                      hintText: '统一身份认证绑定的 11 位手机号',
                      counterText: '',
                      prefixIcon: Icon(Icons.smartphone_rounded, size: 20),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: _codeController,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    decoration: InputDecoration(
                      labelText: '验证码',
                      hintText: '请输入收到的 6 位验证码',
                      counterText: '',
                      prefixIcon: const Icon(
                        Icons.message_rounded,
                        size: 20,
                      ),
                      // 把"获取验证码"做成输入框尾部的 chip-style 按钮，
                      // 比并排放一个 56 高的 OutlinedButton 看起来更整。
                      suffixIcon: _SendCodeChip(
                        label: _sendCodeButtonLabel(state),
                        enabled: canSendCode,
                        loading: state.phase == SmsLoginPhase.awaitingSlider ||
                            state.phase == SmsLoginPhase.sendingSms,
                        onTap: _onSendCode,
                      ),
                      suffixIconConstraints: const BoxConstraints(
                        minWidth: 0,
                        minHeight: 0,
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  if (state.errorMessage != null &&
                      state.errorMessage!.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.md),
                    InlineErrorBanner(message: state.errorMessage!),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  _PrimaryActionButton(
                    label: '登录',
                    busy: isLoggingIn,
                    onPressed: canSubmit ? _onSubmit : null,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Center(
                    child: Text(
                      '验证码 60s 内有效，过期后可重新获取',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  const _SmsBrandFooter(),
                  const SizedBox(height: AppSpacing.lg),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _sendCodeButtonLabel(SmsLoginState state) {
    if (state.cooldownSeconds > 0) {
      return '${state.cooldownSeconds}s';
    }
    if (state.phase == SmsLoginPhase.awaitingSlider) {
      return '验证中…';
    }
    if (state.phase == SmsLoginPhase.sendingSms) {
      return '发送中…';
    }
    return '获取验证码';
  }

  Future<void> _onSendCode() async {
    final mobile = _mobileController.text.trim();
    final notifier = ref.read(smsLoginControllerProvider.notifier);

    await notifier.requestSliderChallenge(mobile: mobile);

    if (!mounted) return;
    final state = ref.read(smsLoginControllerProvider);
    final challenge = state.challenge;
    if (challenge == null) {
      // requestSliderChallenge 内部已经把错误回填到 state，由 ref.listen 提示。
      return;
    }

    final gateway = ref.read(schoolPortalGatewayProvider);
    final passed = await SliderCaptchaSheet.show(
      context,
      initialChallenge: challenge,
      onVerify: (challenge, payload) async {
        final session = ref.read(smsLoginControllerProvider).smsSession;
        if (session == null) {
          return const SliderVerifyResult(
            passed: false,
            message: '会话已失效',
          );
        }
        final result = await gateway.verifySliderCaptcha(
          session,
          payload: payload,
          safeSecure: challenge.safeSecure,
        );
        return result.dataOrNull ??
            SliderVerifyResult(
              passed: false,
              message: result.failureOrNull?.message,
            );
      },
      onRefresh: () async {
        final session = ref.read(smsLoginControllerProvider).smsSession;
        if (session == null) return null;
        final result = await gateway.openSliderCaptcha(session);
        return result.dataOrNull;
      },
    );

    if (!mounted || passed != true) return;
    // 滑块通过 → sheet 已关 → 真发短信。
    await notifier.requestDynamicCode();
  }

  Future<void> _onSubmit() async {
    final mobile = _mobileController.text.trim();
    final code = _codeController.text.trim();
    final ok = await ref
        .read(smsLoginControllerProvider.notifier)
        .submitLogin(mobile: mobile, code: code);
    if (!mounted || !ok) return;
    // 登录成功；router 的 redirect 会把已认证用户从 /login/sms 拉回到 '/'。
    // 兜底主动 go('/')，避免有些情况下 redirect 没及时跑。
    context.go('/');
  }
}

class _SendCodeChip extends StatelessWidget {
  const _SendCodeChip({
    required this.label,
    required this.enabled,
    required this.loading,
    required this.onTap,
  });

  final String label;
  final bool enabled;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = enabled
        ? theme.colorScheme.primary
        : theme.colorScheme.outline.withValues(alpha: 0.6);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          onTap: enabled && !loading ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 6,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (loading) ...[
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.6,
                      color: tone,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: tone,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SmsBrandHeader extends StatelessWidget {
  const _SmsBrandHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(64 * 0.225),
              child: Image.asset(
                'assets/logo/pixel_cat_logo_1024.png',
                width: 64,
                height: 64,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '拾邑',
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                      height: 1.05,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '拾取校园点滴 邑你相伴同行',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          '欢迎回来',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '使用统一身份认证绑定的手机号 + 验证码登录',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _SmsBrandFooter extends StatelessWidget {
  const _SmsBrandFooter();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Text(
        '本应用仅用于学习交流，凭证仅保留在本机',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.outline,
          height: 1.4,
        ),
      ),
    );
  }
}

/// 与账号密码页一致的全宽主按钮。
class _PrimaryActionButton extends StatelessWidget {
  const _PrimaryActionButton({
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
        child: busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: Colors.white,
                ),
              )
            : Text(label),
      ),
    );
  }
}
