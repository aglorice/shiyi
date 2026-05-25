import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/di/app_providers.dart';
import '../../../../integrations/school_portal/sso/slider_captcha.dart';
import '../../../../integrations/school_portal/sso/sms_login_session.dart';
import '../../../../shared/widgets/app_snackbar.dart';
import '../../domain/entities/auth_state.dart';
import '../controllers/auth_controller.dart';
import '../controllers/sms_login_controller.dart';
import '../widgets/slider_captcha_sheet.dart';

/// 仿苹果系统设置/AppleID 风格的单页登录。
///
/// 一切都在一张页面里：顶部分段控件切换"账号 / 短信"，下方共用同一个
/// 圆角分组卡片。两条流程的状态分别在 [AuthController] 与
/// [SmsLoginController] 里独立维护，UI 按当前模式调度对应控制器。
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
    final theme = Theme.of(context);

    // 短信流的错误也用顶部 SnackBar 反馈，避免和账号密码的错误源 UI 打架。
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
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 56),
                  const _LoginHero(),
                  const SizedBox(height: 36),
                  _ModeSegmented(
                    current: _mode,
                    onChanged: (mode) {
                      if (mode == _mode) return;
                      setState(() => _mode = mode);
                      // 切走前清掉两条流的报错和上一种模式残留的输入焦点。
                      FocusScope.of(context).unfocus();
                      if (mode == _LoginMode.sms) {
                        // 进入短信模式时把账号密码错误清掉。
                        // AuthController 没有"清错误"接口，
                        // 视觉上由 _maybeFailureForMode 控制即可。
                      }
                    },
                  ),
                  const SizedBox(height: 24),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: _mode == _LoginMode.password
                        ? _PasswordForm(
                            usernameController: _usernameController,
                            passwordController: _passwordController,
                            obscurePassword: _obscurePassword,
                            onToggleObscure: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                            onChanged: () => setState(() {}),
                            onSubmit: _submitPassword,
                          )
                        : _SmsForm(
                            mobileController: _mobileController,
                            codeController: _codeController,
                            onChanged: () => setState(() {}),
                            onSendCode: _onSendCode,
                          ),
                  ),
                  const SizedBox(height: 12),
                  _MaybeError(mode: _mode),
                  const SizedBox(height: 28),
                  _PrimaryButton(
                    label: _primaryLabel(),
                    busy: _isBusy(),
                    onPressed: _isPrimaryEnabled() ? _onPrimary : null,
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: Text(
                      _mode == _LoginMode.password
                          ? '账号即学号，密码与教务系统一致'
                          : '统一身份认证绑定的手机号才能收到验证码',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Center(
                    child: Text(
                      '本应用仅用于学习交流，凭证仅保留在本机',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---------------- 主按钮调度 ----------------

  String _primaryLabel() {
    switch (_mode) {
      case _LoginMode.password:
        return '登录';
      case _LoginMode.sms:
        return '登录';
    }
  }

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

/// 顶部品牌区：小尺寸 logo + 大标题 + 短副标题，向 Apple ID 那种"轻品牌、
/// 重排版"的层级靠齐——logo 不抢戏，标题字够大。
class _LoginHero extends StatelessWidget {
  const _LoginHero();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
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
        const SizedBox(height: 18),
        Text(
          '登录拾邑',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '使用五邑大学统一身份认证',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// 与 iOS 13+ 设置里的分段控件视觉一致：浅灰底胶囊，选中段白底 + 软阴影。
class _ModeSegmented extends StatelessWidget {
  const _ModeSegmented({required this.current, required this.onChanged});

  final _LoginMode current;
  final ValueChanged<_LoginMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _segment(context, _LoginMode.password, '账号'),
          _segment(context, _LoginMode.sms, '短信'),
        ],
      ),
    );
  }

  Widget _segment(BuildContext context, _LoginMode mode, String label) {
    final theme = Theme.of(context);
    final selected = current == mode;
    return Expanded(
      child: GestureDetector(
        onTap: selected ? null : () => onChanged(mode),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? theme.brightness == Brightness.light
                    ? Colors.white
                    : theme.colorScheme.surfaceContainerHigh
                : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

/// iOS 风格的"分组卡片"：一张白色圆角卡片里放多个 row，row 之间用 hairline
/// 分隔。比每个字段独立一个 OutlineInputBorder 看起来更"系统级"。
class _GroupedCard extends StatelessWidget {
  const _GroupedCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final divider = Divider(
      height: 0.6,
      thickness: 0.6,
      indent: 16,
      endIndent: 16,
      color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
    );

    final laidOut = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      laidOut.add(children[i]);
      if (i != children.length - 1) {
        laidOut.add(divider);
      }
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.light
            ? Colors.white
            : theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
          width: 0.5,
        ),
      ),
      child: Column(children: laidOut),
    );
  }
}

/// 分组卡片里的一行：左侧 18px 图标 + 右侧 borderless TextField。
class _GroupedRow extends StatelessWidget {
  const _GroupedRow({
    required this.icon,
    required this.child,
  });

  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// 用 InputDecoration.collapsed 让 TextField 看起来无边框、和 iOS 设置里的
/// 分组单行输入对齐。
InputDecoration _flatField({String? hintText, Widget? suffixIcon}) {
  return InputDecoration(
    border: InputBorder.none,
    enabledBorder: InputBorder.none,
    focusedBorder: InputBorder.none,
    disabledBorder: InputBorder.none,
    errorBorder: InputBorder.none,
    focusedErrorBorder: InputBorder.none,
    filled: false,
    contentPadding: const EdgeInsets.symmetric(vertical: 14),
    hintText: hintText,
    counterText: '',
    suffixIcon: suffixIcon,
    suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
    isDense: true,
  );
}

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
    return _GroupedCard(
      children: [
        _GroupedRow(
          icon: Icons.person_outline_rounded,
          child: TextField(
            controller: usernameController,
            decoration: _flatField(hintText: '学号'),
            textInputAction: TextInputAction.next,
            keyboardType: TextInputType.text,
            onChanged: (_) => onChanged(),
          ),
        ),
        _GroupedRow(
          icon: Icons.lock_outline_rounded,
          child: TextField(
            controller: passwordController,
            obscureText: obscurePassword,
            decoration: _flatField(
              hintText: '密码',
              suffixIcon: GestureDetector(
                onTap: onToggleObscure,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8, right: 4),
                  child: Icon(
                    obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            onChanged: (_) => onChanged(),
            onSubmitted: (_) => onSubmit(),
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

    return _GroupedCard(
      children: [
        _GroupedRow(
          icon: Icons.smartphone_rounded,
          child: TextField(
            controller: mobileController,
            keyboardType: TextInputType.phone,
            maxLength: 11,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: _flatField(hintText: '11 位手机号'),
            onChanged: (_) => onChanged(),
          ),
        ),
        _GroupedRow(
          icon: Icons.message_rounded,
          child: TextField(
            controller: codeController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: _flatField(
              hintText: '6 位验证码',
              suffixIcon: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: canSend && !loading ? onSendCode : null,
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
                      Text(
                        label,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: canSend
                              ? theme.colorScheme.primary
                              : theme.colorScheme.outline,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            onChanged: (_) => onChanged(),
          ),
        ),
      ],
    );
  }
}

/// 综合两条流的错误，按当前模式选择性显示。
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
      padding: const EdgeInsets.only(top: 8),
      child: Row(
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

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
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
      height: 50,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 16,
            letterSpacing: 0.2,
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
