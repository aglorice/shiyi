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

/// 单页登录。
///
/// 设计取向：Notion / Stripe 极简风。
///   - 顶部：小 logo + 短标题 + 一行副标题。
///   - 中段：默认账号密码登录，输入框是下划线极简款。
///   - 底部：纯黑按钮 + "用短信验证码登录"文字链接（不再用 Tab）。
///
/// 短信模式由内部布尔标志切换，渐变到同一组下划线输入框，避免 Tab 那种
/// 重型导航控件出现在登录页这种轻量场景。
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
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
            return SingleChildScrollView(
              physics: keyboardOpen
                  ? const ClampingScrollPhysics()
                  : const NeverScrollableScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 380),
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

/// 登录主体。一段式 Column，从上往下：
///   - 顶部 spacer（约 18% 屏高）
///   - logo + 标题 + 副标题
///   - 间距
///   - 表单（下划线输入）
///   - 错误（如有）
///   - 按钮
///   - 底部链接：切换模式 + 密码与教务系统一致提示
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

    final modeHint = mode == _LoginMode.password ? '改用短信验证码' : '改用账号密码';

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: compact ? 16 : 64),

          // —— 品牌区：左对齐
          _BrandHeader(compact: compact),

          SizedBox(height: compact ? 28 : 44),

          // —— 表单
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: form,
          ),

          const SizedBox(height: 16),
          _MaybeError(mode: mode),

          SizedBox(height: compact ? 28 : 36),

          // —— 主按钮：纯黑
          _PrimaryButton(
            busy: isBusy,
            onPressed: isPrimaryEnabled ? onPrimary : null,
          ),

          const SizedBox(height: 18),

          // —— 切换模式（文字链接，不抢戏）
          _TextLink(
            label: modeHint,
            onTap: onSwitchMode,
          ),

          // 让上半内容不至于撑到底部，剩余空间留给键盘弹起
          SizedBox(height: compact ? 8 : 56),
        ],
      ),
    );
  }
}

/// 品牌区：左对齐 logo + 大标题 + 副标题。
///
/// 标题改成两个字"登录"，配合 displayMedium 看得清却不挤行；副标题给场景。
class _BrandHeader extends StatelessWidget {
  const _BrandHeader({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final logoSize = compact ? 44.0 : 56.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: logoSize,
          height: logoSize,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(logoSize * 0.225),
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(logoSize * 0.225),
            child: Image.asset(
              'assets/logo/pixel_cat_logo_1024.png',
              width: logoSize,
              height: logoSize,
              fit: BoxFit.cover,
            ),
          ),
        ),
        SizedBox(height: compact ? 16 : 28),
        Text(
          '登录',
          style: (compact
                  ? theme.textTheme.headlineLarge
                  : theme.textTheme.displayMedium)
              ?.copyWith(
            fontWeight: FontWeight.w900,
            letterSpacing: -1.0,
            height: 1.0,
            color: const Color(0xFF111111),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '欢迎回来，使用五邑大学统一身份认证继续',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: const Color(0xFF666666),
            height: 1.5,
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}

/// 下划线极简输入框：左图标 + 文字 + 底部 1px 横线。
/// focus 时横线变 accent + 加粗到 1.6px，hint 文字色淡，字段本身字号 16。
class _UnderlineField extends StatefulWidget {
  const _UnderlineField({
    required this.controller,
    required this.icon,
    required this.hint,
    this.obscureText = false,
    this.keyboardType,
    this.maxLength,
    this.inputFormatters,
    this.suffix,
    this.onChanged,
    this.onSubmitted,
    this.textInputAction,
  });

  final TextEditingController controller;
  final IconData icon;
  final String hint;
  final bool obscureText;
  final TextInputType? keyboardType;
  final int? maxLength;
  final List<TextInputFormatter>? inputFormatters;
  final Widget? suffix;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction? textInputAction;

  @override
  State<_UnderlineField> createState() => _UnderlineFieldState();
}

class _UnderlineFieldState extends State<_UnderlineField> {
  final _focusNode = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (_focused != _focusNode.hasFocus) {
        setState(() => _focused = _focusNode.hasFocus);
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              widget.icon,
              size: 18,
              color: _focused
                  ? accent
                  : const Color(0xFF999999),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: widget.controller,
                focusNode: _focusNode,
                obscureText: widget.obscureText,
                keyboardType: widget.keyboardType,
                maxLength: widget.maxLength,
                inputFormatters: widget.inputFormatters,
                onChanged: widget.onChanged,
                onSubmitted: widget.onSubmitted,
                textInputAction: widget.textInputAction,
                cursorColor: accent,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF111111),
                  letterSpacing: 0.2,
                ),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  hintText: widget.hint,
                  hintStyle: const TextStyle(
                    fontSize: 16,
                    color: Color(0xFFAAAAAA),
                    fontWeight: FontWeight.w500,
                  ),
                  counterText: '',
                  isDense: true,
                ),
              ),
            ),
            if (widget.suffix != null) widget.suffix!,
          ],
        ),
        // 下划线：未聚焦淡灰，聚焦 accent 加粗
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          height: _focused ? 1.6 : 1,
          decoration: BoxDecoration(
            color: _focused
                ? accent
                : const Color(0xFFE5E5E5),
          ),
        ),
      ],
    );
  }
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
    return Column(
      children: [
        _UnderlineField(
          controller: usernameController,
          icon: Icons.person_outline_rounded,
          hint: '学号',
          textInputAction: TextInputAction.next,
          onChanged: (_) => onChanged(),
        ),
        const SizedBox(height: 8),
        _UnderlineField(
          controller: passwordController,
          icon: Icons.lock_outline_rounded,
          hint: '密码',
          obscureText: obscurePassword,
          textInputAction: TextInputAction.done,
          onChanged: (_) => onChanged(),
          onSubmitted: (_) => onSubmit(),
          suffix: GestureDetector(
            onTap: onToggleObscure,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
              child: Icon(
                obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 18,
                color: const Color(0xFF999999),
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
    final accent = theme.colorScheme.primary;
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
        _UnderlineField(
          controller: mobileController,
          icon: Icons.smartphone_rounded,
          hint: '11 位手机号',
          keyboardType: TextInputType.phone,
          maxLength: 11,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (_) => onChanged(),
        ),
        const SizedBox(height: 8),
        _UnderlineField(
          controller: codeController,
          icon: Icons.password_rounded,
          hint: '6 位验证码',
          keyboardType: TextInputType.number,
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (_) => onChanged(),
          suffix: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: canSend && !loading ? onSendCode : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (loading) ...[
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.6,
                        color: accent,
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      color: canSend
                          ? accent
                          : const Color(0xFF999999),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
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

    return Row(
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
    );
  }
}

/// 主按钮：纯黑实心。disabled 时切到 8% 黑底 + 35% 黑字，永远不会出现"病号绿"。
class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.busy,
    required this.onPressed,
  });

  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF111111),
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFF111111).withValues(alpha: 0.08),
          disabledForegroundColor: const Color(0xFF111111).withValues(alpha: 0.35),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 16,
            letterSpacing: 0.2,
          ),
          elevation: 0,
        ),
        child: busy
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.6,
                  color: Colors.white,
                ),
              )
            : const Text('登录'),
      ),
    );
  }
}

/// 文字链接：切换模式或其他次级动作。淡灰主体 + accent 强调动词。
class _TextLink extends StatelessWidget {
  const _TextLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.primary,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }
}
