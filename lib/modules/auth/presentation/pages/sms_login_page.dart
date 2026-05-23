import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/design_tokens.dart';
import '../../../../shared/widgets/app_snackbar.dart';
import '../controllers/sms_login_controller.dart';
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

    // 监听错误并以 SnackBar 提示，避免与按钮态打架。
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

    final canSendCode =
        _mobileController.text.trim().length == 11 && state.canSendCode;
    final isLoggingIn = state.phase == SmsLoginPhase.loggingIn;

    return Scaffold(
      appBar: AppBar(title: const Text('短信登录')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: AppSpacing.xxl),
                  Text(
                    '使用手机号验证码登录',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    '需要先在统一身份认证里绑定手机号',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
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
                      counterText: '',
                      prefixIcon: Icon(Icons.smartphone_rounded),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _codeController,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: const InputDecoration(
                            labelText: '验证码',
                            counterText: '',
                            prefixIcon: Icon(Icons.message_rounded),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      SizedBox(
                        height: 56,
                        child: OutlinedButton(
                          onPressed: canSendCode ? _onSendCode : null,
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(AppRadius.md),
                            ),
                          ),
                          child: Text(_sendCodeButtonLabel(state)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  FilledButton(
                    onPressed: isLoggingIn ? null : _onSubmit,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.md,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                    ),
                    child: Text(isLoggingIn ? '登录中…' : '登录'),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Center(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      child: const Text('返回账号密码登录'),
                    ),
                  ),
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
      return '${state.cooldownSeconds}s 后重发';
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
    if (state.challenge == null) {
      // requestSliderChallenge 内部已经把错误回填到 state，由 ref.listen 提示。
      return;
    }

    final passed = await SliderCaptchaSheet.show(context);
    if (passed != true) {
      // 用户主动关闭，或滑块失败后用户放弃（理论上失败会自动换图重试）
      return;
    }

    if (!mounted) return;
    // 滑块通过 → sheet 已关 → 真发短信。
    // 失败时由 ref.listen 弹 SnackBar 提示，状态会回到 idle，用户重发会再次出滑块。
    await notifier.requestDynamicCode();
  }

  Future<void> _onSubmit() async {
    final mobile = _mobileController.text.trim();
    final code = _codeController.text.trim();
    await ref
        .read(smsLoginControllerProvider.notifier)
        .submitLogin(mobile: mobile, code: code);
  }
}
