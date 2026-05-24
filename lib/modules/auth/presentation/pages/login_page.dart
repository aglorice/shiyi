import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/di/app_providers.dart';
import '../../../../app/theme/design_tokens.dart';
import '../../../../integrations/school_portal/sso/slider_captcha.dart';
import '../../../../integrations/school_portal/sso/sms_login_session.dart';
import '../../domain/entities/auth_state.dart';
import '../controllers/auth_controller.dart';
import '../widgets/slider_captcha_sheet.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authAsync = ref.watch(authControllerProvider);
    final authState = authAsync.value;
    final failure = authState?.failure;
    final isSubmitting = authAsync.isLoading;
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 64),
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(56 * 0.225),
                        child: Image.asset(
                          'assets/logo/pixel_cat_logo_1024.png',
                          width: 56,
                          height: 56,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Text(
                        '拾邑',
                        style: theme.textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    '欢迎回来',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '登录五邑大学统一身份认证',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  TextField(
                    controller: _usernameController,
                    decoration: const InputDecoration(
                      labelText: '学号',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: '密码',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                  if (failure != null &&
                      authState?.status != AuthStatus.authenticated) ...[
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          size: 16,
                          color: theme.colorScheme.error,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            failure.message,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: isSubmitting ? null : _submit,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppRadius.md),
                        ),
                      ),
                      child: isSubmitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              '登录',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Center(
                    child: TextButton.icon(
                      onPressed: isSubmitting
                          ? null
                          : () => context.push('/login/sms'),
                      icon: const Icon(Icons.smartphone_rounded, size: 18),
                      label: const Text('使用手机号验证码登录'),
                      style: TextButton.styleFrom(
                        foregroundColor: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Center(
                    child: Text(
                      '拾取校园点滴，邑你相伴同行',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _submit() {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    ref.read(authControllerProvider.notifier).login(
          username: username,
          password: password,
          solveCaptcha: (session) => _solveCaptcha(session),
        );
  }

  /// 当服务端要求滑块时被调用：拉一张挑战 → 弹 sheet → 用户拖通过返回 true。
  Future<bool> _solveCaptcha(SmsLoginSession session) async {
    if (!mounted) return false;
    final gateway = ref.read(schoolPortalGatewayProvider);
    final challengeResult = await gateway.openSliderCaptcha(session);
    final challenge = challengeResult.dataOrNull;
    if (!mounted || challenge == null) return false;

    final passed = await SliderCaptchaSheet.show(
      context,
      initialChallenge: challenge,
      onVerify: (challenge, payload) async {
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
        final result = await gateway.openSliderCaptcha(session);
        return result.dataOrNull;
      },
    );
    return passed == true;
  }
}
