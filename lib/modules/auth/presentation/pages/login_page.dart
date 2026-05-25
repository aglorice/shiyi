import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/di/app_providers.dart';
import '../../../../app/theme/design_tokens.dart';
import '../../../../integrations/school_portal/sso/slider_captcha.dart';
import '../../../../integrations/school_portal/sso/sms_login_session.dart';
import '../../domain/entities/auth_state.dart';
import '../controllers/auth_controller.dart';
import '../widgets/inline_error_banner.dart';
import '../widgets/login_method_switch.dart';
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
    final showFailure = failure != null &&
        authState?.status != AuthStatus.authenticated;
    final isSubmitting = authAsync.isLoading;
    final theme = Theme.of(context);

    return Scaffold(
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
                  const _BrandHeader(
                    title: '欢迎回来',
                    subtitle: '登录五邑大学统一身份认证，继续校园生活',
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  LoginMethodSwitch(
                    current: LoginMethod.password,
                    onChanged: (method) {
                      if (method == LoginMethod.sms) {
                        // 用 pushReplacement 让账号密码页与短信页之间相互替换，
                        // 不在栈里堆出三层登录页。
                        context.pushReplacement('/login/sms');
                      }
                    },
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  TextField(
                    controller: _usernameController,
                    decoration: const InputDecoration(
                      labelText: '学号',
                      hintText: '请输入统一身份认证账号',
                      prefixIcon: Icon(Icons.badge_outlined, size: 20),
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: '密码',
                      hintText: '请输入登录密码',
                      prefixIcon: const Icon(Icons.lock_outline, size: 20),
                      suffixIcon: IconButton(
                        tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 20,
                        ),
                      ),
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                  if (showFailure) ...[
                    const SizedBox(height: AppSpacing.md),
                    InlineErrorBanner(message: failure.message),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  _PrimaryActionButton(
                    label: '登录',
                    busy: isSubmitting,
                    onPressed: isSubmitting ? null : _submit,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Center(
                    child: Text(
                      '账号即学号，密码与教务系统一致',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  const _BrandFooter(),
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

/// 共享的品牌头部：logo + 名字 + 一行欢迎语 + 副标题。
/// 两个登录页共用一个版本，保证从账号密码切到短信时品牌区不抖动。
class _BrandHeader extends StatelessWidget {
  const _BrandHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

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
          title,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _BrandFooter extends StatelessWidget {
  const _BrandFooter();

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

/// 全宽主按钮：高 52 / 圆角 lg / 加粗。busy=true 时显示 spinner。
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
