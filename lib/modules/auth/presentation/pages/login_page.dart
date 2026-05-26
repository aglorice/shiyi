import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/di/app_providers.dart';
import '../../../../app/theme/design_tokens.dart';
import '../../../../integrations/school_portal/sso/slider_captcha.dart';
import '../../../../integrations/school_portal/sso/sms_login_session.dart';
import '../../../../shared/widgets/app_snackbar.dart';
import '../../../../shared/widgets/pixel_pet.dart';
import '../../../../shared/widgets/surface_card.dart';
import '../../domain/entities/auth_state.dart';
import '../controllers/auth_controller.dart';
import '../controllers/sms_login_controller.dart';
import '../widgets/slider_captcha_sheet.dart';

/// 登录页。
///
/// 设计语言上和应用首页对齐：上方是渐变 hero（呼应 `_HomeHero`），
/// 下方是白色 SurfaceCard 装表单。这样 onboarding → 登录 → 首页一脉相承，
/// 不再让登录页看起来像被空降进来的"系统页面"。
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

enum _LoginMode { password, sms }

class _LoginPageState extends ConsumerState<LoginPage> {
  _LoginMode _mode = _LoginMode.password;

  // 账号密码模式的字段
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  // 短信模式的字段
  final _mobileController = TextEditingController();
  final _codeController = TextEditingController();

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _mobileController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 短信流的错误用顶部 SnackBar 反馈，避免和账号密码的错误源 UI 打架。
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

    return Scaffold(
      // 用 LayoutBuilder + ConstrainedBox(minHeight) + SingleChildScrollView：
      // 不弹键盘时整页占满；弹了键盘时 Hero 自然被滚走，按钮不被压扁。
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
            return SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: _LoginBody(
                        mode: _mode,
                        usernameController: _usernameController,
                        passwordController: _passwordController,
                        obscurePassword: _obscurePassword,
                        mobileController: _mobileController,
                        codeController: _codeController,
                        isBusy: _isBusy(),
                        isPrimaryEnabled: _isPrimaryEnabled(),
                        onSwitchMode: () {
                          setState(() {
                            _mode = _mode == _LoginMode.password
                                ? _LoginMode.sms
                                : _LoginMode.password;
                          });
                          FocusScope.of(context).unfocus();
                        },
                        onToggleObscure: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                        onFormChanged: () => setState(() {}),
                        onSubmitPassword: _submitPassword,
                        onSendCode: _onSendCode,
                        onPrimary: _onPrimary,
                        compact: keyboardOpen,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ---------------- 主按钮调度 ----------------

  bool _isBusy() {
    if (_mode == _LoginMode.password) {
      return ref.watch(authControllerProvider).isLoading;
    }
    return ref.watch(smsLoginControllerProvider).phase ==
        SmsLoginPhase.loggingIn;
  }

  bool _isPrimaryEnabled() {
    if (_isBusy()) return false;
    if (_mode == _LoginMode.password) {
      return _usernameController.text.trim().isNotEmpty &&
          _passwordController.text.isNotEmpty;
    }
    final smsState = ref.watch(smsLoginControllerProvider);
    return smsState.smsSession != null &&
        _codeController.text.trim().length == 6;
  }

  void _onPrimary() {
    if (_mode == _LoginMode.password) {
      _submitPassword();
    } else {
      _submitSms();
    }
  }

  // ---------------- 账号密码 ----------------

  void _submitPassword() {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty || password.isEmpty) return;
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

  // ---------------- 短信 ----------------

  Future<void> _onSendCode() async {
    final mobile = _mobileController.text.trim();
    final notifier = ref.read(smsLoginControllerProvider.notifier);
    await notifier.requestSliderChallenge(mobile: mobile);

    if (!mounted) return;
    final state = ref.read(smsLoginControllerProvider);
    final challenge = state.challenge;
    if (challenge == null) return;

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
    await notifier.requestDynamicCode();
  }

  Future<void> _submitSms() async {
    final mobile = _mobileController.text.trim();
    final code = _codeController.text.trim();
    final ok = await ref
        .read(smsLoginControllerProvider.notifier)
        .submitLogin(mobile: mobile, code: code);
    if (!mounted || !ok) return;
    context.go('/');
  }
}

/// 主体：上方 Hero 渐变区 + 中段表单卡片 + 底部按钮。
///
/// 整页 padding 用 `AppSpacing.pageH`（20）和应用其他页面统一。
class _LoginBody extends ConsumerWidget {
  const _LoginBody({
    required this.mode,
    required this.usernameController,
    required this.passwordController,
    required this.obscurePassword,
    required this.mobileController,
    required this.codeController,
    required this.isBusy,
    required this.isPrimaryEnabled,
    required this.onSwitchMode,
    required this.onToggleObscure,
    required this.onFormChanged,
    required this.onSubmitPassword,
    required this.onSendCode,
    required this.onPrimary,
    required this.compact,
  });

  final _LoginMode mode;
  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final bool obscurePassword;
  final TextEditingController mobileController;
  final TextEditingController codeController;
  final bool isBusy;
  final bool isPrimaryEnabled;
  final VoidCallback onSwitchMode;
  final VoidCallback onToggleObscure;
  final VoidCallback onFormChanged;
  final VoidCallback onSubmitPassword;
  final Future<void> Function() onSendCode;
  final VoidCallback onPrimary;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final form = mode == _LoginMode.password
        ? _PasswordForm(
            usernameController: usernameController,
            passwordController: passwordController,
            obscurePassword: obscurePassword,
            onToggleObscure: onToggleObscure,
            onChanged: onFormChanged,
            onSubmit: onSubmitPassword,
          )
        : _SmsForm(
            mobileController: mobileController,
            codeController: codeController,
            onChanged: onFormChanged,
            onSendCode: onSendCode,
          );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pageH),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: compact ? AppSpacing.sm : AppSpacing.lg),

          // 1. Hero —— 与首页 _HomeHero 同款渐变 + 像素猫，建立品牌延续性
          if (!compact) const _LoginHero(),
          if (compact) const _LoginHeroCompact(),

          SizedBox(height: compact ? AppSpacing.md : AppSpacing.lg),

          // 2. 表单卡片 —— 与全 app 卡片体系一致
          SurfaceCard(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 模式切换 segmented 行：当前模式深色字、另一段淡色 + accent dot
                _ModeRow(mode: mode, onSwitch: onSwitchMode),
                const SizedBox(height: AppSpacing.lg),
                AnimatedSize(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: form,
                ),
                const SizedBox(height: AppSpacing.sm),
                _MaybeError(mode: mode),
              ],
            ),
          ),

          SizedBox(height: compact ? AppSpacing.md : AppSpacing.lg),

          // 3. 主按钮：渐变填充呼应 hero
          _GradientPrimaryButton(
            busy: isBusy,
            onPressed: isPrimaryEnabled ? onPrimary : null,
          ),

          const SizedBox(height: AppSpacing.md),

          // 4. 底部提示行：根据模式给一行场景说明
          _BottomHint(mode: mode),

          SizedBox(height: compact ? AppSpacing.xs : AppSpacing.lg),
        ],
      ),
    );
  }
}

// ============================================================
// Hero 区：与首页 _HomeHero 同款语言
// ============================================================

class _LoginHero extends StatelessWidget {
  const _LoginHero();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.md),
        gradient: LinearGradient(
          colors: [
            colorScheme.primary,
            Color.lerp(colorScheme.primary, colorScheme.tertiary, 0.52) ??
                colorScheme.tertiary,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.xl,
          AppSpacing.md,
          AppSpacing.lg,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 应用 logo 小章
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.school_rounded,
                          size: 13,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '拾邑',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    '欢迎回来',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      height: 1.05,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '登录五邑大学统一身份认证，把校园生活折叠到一处',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.86),
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            // 右下角放品牌像素猫
            const SizedBox(width: AppSpacing.sm),
            const PixelPet(type: PixelPetType.cat),
          ],
        ),
      ),
    );
  }
}

/// 键盘弹起时的紧凑 Hero：去掉副标题，缩小 padding 和字号。
class _LoginHeroCompact extends StatelessWidget {
  const _LoginHeroCompact();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.md),
        gradient: LinearGradient(
          colors: [
            colorScheme.primary,
            Color.lerp(colorScheme.primary, colorScheme.tertiary, 0.52) ??
                colorScheme.tertiary,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '欢迎回来',
              style: theme.textTheme.titleLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.3,
              ),
            ),
          ),
          Transform.scale(
            scale: 0.7,
            child: const PixelPet(type: PixelPetType.cat),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 模式切换：表单卡片顶部一行，比独立 segmented control 视觉权重轻
// ============================================================

class _ModeRow extends StatelessWidget {
  const _ModeRow({required this.mode, required this.onSwitch});

  final _LoginMode mode;
  final VoidCallback onSwitch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeLabel = mode == _LoginMode.password ? '账号密码登录' : '短信验证码登录';
    final altLabel = mode == _LoginMode.password ? '改用短信' : '改用账号';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 当前模式：accent 色圆点 + 加粗标题
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            activeLabel,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: -0.2,
            ),
          ),
        ),
        // 切换链接：outlined pill chip 风格，符合 app 的 chip 体系
        InkWell(
          onTap: onSwitch,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
              ),
            ),
            child: Text(
              altLabel,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// 表单：用 Theme.inputDecorationTheme 自带的 OutlineInputBorder
// （filled 白底 + 圆角 20 + 描边 0.6 outlineVariant），
// 不再自己手搓下划线/胶囊样式。
// ============================================================

class _PasswordForm extends StatelessWidget {
  const _PasswordForm({
    required this.usernameController,
    required this.passwordController,
    required this.obscurePassword,
    required this.onToggleObscure,
    required this.onChanged,
    required this.onSubmit,
  });

  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final bool obscurePassword;
  final VoidCallback onToggleObscure;
  final VoidCallback onChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        TextField(
          controller: usernameController,
          textInputAction: TextInputAction.next,
          onChanged: (_) => onChanged(),
          decoration: InputDecoration(
            hintText: '请输入学号',
            labelText: '学号',
            prefixIcon: Icon(
              Icons.person_outline_rounded,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: passwordController,
          obscureText: obscurePassword,
          textInputAction: TextInputAction.done,
          onChanged: (_) => onChanged(),
          onSubmitted: (_) => onSubmit(),
          decoration: InputDecoration(
            hintText: '请输入教务系统密码',
            labelText: '密码',
            prefixIcon: Icon(
              Icons.lock_outline_rounded,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            suffixIcon: IconButton(
              onPressed: onToggleObscure,
              splashRadius: 20,
              icon: Icon(
                obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SmsForm extends ConsumerWidget {
  const _SmsForm({
    required this.mobileController,
    required this.codeController,
    required this.onChanged,
    required this.onSendCode,
  });

  final TextEditingController mobileController;
  final TextEditingController codeController;
  final VoidCallback onChanged;
  final Future<void> Function() onSendCode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final smsState = ref.watch(smsLoginControllerProvider);
    final mobileLooksValid = mobileController.text.trim().length == 11;
    final canSend = mobileLooksValid && smsState.canSendCode;
    final loading = smsState.phase == SmsLoginPhase.awaitingSlider ||
        smsState.phase == SmsLoginPhase.sendingSms;

    String label;
    if (smsState.cooldownSeconds > 0) {
      label = '${smsState.cooldownSeconds}s';
    } else if (loading) {
      label = '发送中…';
    } else {
      label = '获取验证码';
    }

    return Column(
      children: [
        TextField(
          controller: mobileController,
          keyboardType: TextInputType.phone,
          maxLength: 11,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (_) => onChanged(),
          decoration: InputDecoration(
            hintText: '11 位手机号',
            labelText: '手机号',
            counterText: '',
            prefixIcon: Icon(
              Icons.smartphone_rounded,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: codeController,
          keyboardType: TextInputType.number,
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (_) => onChanged(),
          decoration: InputDecoration(
            hintText: '6 位验证码',
            labelText: '验证码',
            counterText: '',
            prefixIcon: Icon(
              Icons.password_rounded,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            suffixIcon: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton(
                onPressed: canSend && !loading ? onSendCode : null,
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.primary,
                  disabledForegroundColor: theme.colorScheme.outline,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
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
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(label),
                  ],
                ),
              ),
            ),
            suffixIconConstraints: const BoxConstraints(minWidth: 0),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// 错误提示：纯文字 + 图标，不挤进表单本身
// ============================================================

class _MaybeError extends ConsumerWidget {
  const _MaybeError({required this.mode});

  final _LoginMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    String? message;
    if (mode == _LoginMode.password) {
      final auth = ref.watch(authControllerProvider).value;
      if (auth != null && auth.status != AuthStatus.authenticated) {
        message = auth.failure?.message;
      }
    } else {
      message = ref.watch(smsLoginControllerProvider).errorMessage;
    }

    if (message == null || message.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 14,
            color: theme.colorScheme.error,
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 主按钮：渐变填充按钮，呼应 Hero 配色，圆角 20、字重 w900
// ============================================================

class _GradientPrimaryButton extends StatelessWidget {
  const _GradientPrimaryButton({required this.busy, required this.onPressed});

  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final enabled = onPressed != null && !busy;

    final gradient = enabled
        ? LinearGradient(
            colors: [
              colorScheme.primary,
              Color.lerp(colorScheme.primary, colorScheme.tertiary, 0.52) ??
                  colorScheme.tertiary,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
        : LinearGradient(
            colors: [
              colorScheme.primary.withValues(alpha: 0.30),
              colorScheme.primary.withValues(alpha: 0.30),
            ],
          );

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Ink(
          height: 54,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            gradient: gradient,
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: colorScheme.primary.withValues(alpha: 0.28),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.6,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    '登录',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.4,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// 底部提示
// ============================================================

class _BottomHint extends StatelessWidget {
  const _BottomHint({required this.mode});

  final _LoginMode mode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hint = mode == _LoginMode.password
        ? '账号即学号，密码与教务系统一致'
        : '统一身份认证绑定的手机号才能收到验证码';
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 13,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              hint,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
