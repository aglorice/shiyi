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
/// 设计取向：现代移动端登录页（Notion / 小红书 / Linear），三段式：
///   1. 顶部品牌区：左对齐 60px logo + 大标题 + 副标题，不再居中堆叠。
///   2. 中部表单区：下划线 Tab 切换"账号 / 短信"，下面是 pill 形输入框。
///   3. 底部行动区：主按钮锚定在底部安全区，方便单手按下。
///
/// 两条流程的状态分别由 [AuthController] 和 [SmsLoginController] 维护。
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
      // SafeArea + LayoutBuilder：键盘弹起时退化成滚动布局避免溢出，
      // 否则用 Column + Spacer 让按钮锚定在底部 24px。
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
            final body = ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: _LoginBody(
                mode: _mode,
                usernameController: _usernameController,
                passwordController: _passwordController,
                obscurePassword: _obscurePassword,
                mobileController: _mobileController,
                codeController: _codeController,
                isBusy: _isBusy(),
                isPrimaryEnabled: _isPrimaryEnabled(),
                onModeChanged: (m) {
                  if (m == _mode) return;
                  setState(() => _mode = m);
                  FocusScope.of(context).unfocus();
                },
                onToggleObscure: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
                onFormChanged: () => setState(() {}),
                onSubmitPassword: _submitPassword,
                onSendCode: _onSendCode,
                onPrimary: _onPrimary,
                compact: keyboardOpen,
              ),
            );

            if (keyboardOpen) {
              return SingleChildScrollView(
                child: Center(child: body),
              );
            }
            return Center(child: body);
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

/// 主体 column。键盘没弹时用 Spacer 把按钮挤到底；键盘弹了由父级降级成滚动。
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
    required this.onModeChanged,
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
  final ValueChanged<_LoginMode> onModeChanged;
  final VoidCallback onToggleObscure;
  final VoidCallback onFormChanged;
  final VoidCallback onSubmitPassword;
  final Future<void> Function() onSendCode;
  final VoidCallback onPrimary;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    final hint = mode == _LoginMode.password
        ? '账号即学号，密码与教务系统一致'
        : '统一身份认证绑定的手机号才能收到验证码';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: compact ? 16 : 56),
          // 1. 品牌：左对齐顶部，logo + 大标题 + 副标题
          _BrandHeader(compact: compact),
          SizedBox(height: compact ? 24 : 40),
          // 2. 模式切换：下划线 Tab，比分段控件轻
          _UnderlineTabs(
            current: mode,
            onChanged: onModeChanged,
          ),
          const SizedBox(height: 28),
          // 3. 表单：pill 形输入框
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: mode == _LoginMode.password
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
                  ),
          ),
          const SizedBox(height: 12),
          _MaybeError(mode: mode),
          // 4. 用 Spacer 把按钮挤到底，行动区始终在拇指热区。
          if (!compact) const Spacer(),
          if (compact) const SizedBox(height: 28),
          _PrimaryButton(
            busy: isBusy,
            onPressed: isPrimaryEnabled ? onPrimary : null,
          ),
          const SizedBox(height: 14),
          Text(
            hint,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
              height: 1.4,
            ),
          ),
          SizedBox(height: compact ? 8 : 24),
        ],
      ),
    );
  }
}

/// 品牌区：左对齐 60px logo + 大标题 + 副标题。
///
/// 一改之前居中堆叠的"罗列式"，对齐到内容左边缘（与表单同列），整页有清晰
/// 的左对齐 grid，看起来像 Notion / Linear / 小红书的入口页。
class _BrandHeader extends StatelessWidget {
  const _BrandHeader({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final logoSize = compact ? 48.0 : 60.0;

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
                blurRadius: 14,
                offset: const Offset(0, 6),
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
        SizedBox(height: compact ? 16 : 24),
        Text(
          '嗨，欢迎回来',
          textAlign: TextAlign.left,
          style: (compact
                  ? theme.textTheme.headlineMedium
                  : theme.textTheme.displaySmall)
              ?.copyWith(
            fontWeight: FontWeight.w900,
            letterSpacing: -0.6,
            height: 1.05,
            color: const Color(0xFF1A1A1A),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '使用学号或手机号登录五邑大学统一身份认证',
          textAlign: TextAlign.left,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

/// 下划线 Tab：左对齐两个文字按钮，下方滑动一段 accent 色短横线指示当前。
/// 比胶囊状的 segmented control 视觉重量轻，留白更多，符合现代登录页风格。
class _UnderlineTabs extends StatelessWidget {
  const _UnderlineTabs({required this.current, required this.onChanged});

  final _LoginMode current;
  final ValueChanged<_LoginMode> onChanged;

  static const _items = [
    (_LoginMode.password, '账号密码'),
    (_LoginMode.sms, '短信验证码'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (final item in _items) ...[
              _Tab(
                label: item.$2,
                selected: current == item.$1,
                onTap: () => onChanged(item.$1),
              ),
              const SizedBox(width: 24),
            ],
          ],
        ),
        const SizedBox(height: 12),
        // 底部 hairline + accent 短横线
        SizedBox(
          height: 2,
          child: LayoutBuilder(
            builder: (ctx, constraints) {
              final theme = Theme.of(ctx);
              return Stack(
                children: [
                  Positioned.fill(
                    child: Container(
                      color: theme.colorScheme.outlineVariant
                          .withValues(alpha: 0.40),
                    ),
                  ),
                  AnimatedAlign(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    alignment: current == _LoginMode.password
                        ? Alignment.centerLeft
                        : Alignment.centerLeft +
                            const Alignment(0.45, 0), // 偏右一点
                    child: Container(
                      // 第二段宽一点对应"短信验证码"5 个字
                      width: current == _LoginMode.password ? 64 : 90,
                      height: 2,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          label,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: selected
                ? theme.colorScheme.onSurface
                : theme.colorScheme.outline,
            letterSpacing: -0.2,
          ),
        ),
      ),
    );
  }
}

/// 单个 pill 输入框：圆角 14、surfaceContainerHighest 浅灰填充、无描边。
/// 关注就把填充色加深一点点，配合柔光圈边作为聚焦反馈，比改边框颜色更细腻。
class _PillField extends StatefulWidget {
  const _PillField({
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
  State<_PillField> createState() => _PillFieldState();
}

class _PillFieldState extends State<_PillField> {
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

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: _focused
            ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.95)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _focused
              ? accent.withValues(alpha: 0.55)
              : Colors.transparent,
          width: 1.4,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Icon(
              widget.icon,
              size: 18,
              color: _focused
                  ? accent
                  : theme.colorScheme.onSurfaceVariant
                      .withValues(alpha: 0.85),
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
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  contentPadding: const EdgeInsets.symmetric(vertical: 16),
                  hintText: widget.hint,
                  hintStyle: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.outline,
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
      ),
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
    final theme = Theme.of(context);
    return Column(
      children: [
        _PillField(
          controller: usernameController,
          icon: Icons.person_outline_rounded,
          hint: '学号',
          textInputAction: TextInputAction.next,
          onChanged: (_) => onChanged(),
        ),
        const SizedBox(height: 12),
        _PillField(
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
              padding: const EdgeInsets.only(left: 8),
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
        _PillField(
          controller: mobileController,
          icon: Icons.smartphone_rounded,
          hint: '11 位手机号',
          keyboardType: TextInputType.phone,
          maxLength: 11,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (_) => onChanged(),
        ),
        const SizedBox(height: 12),
        _PillField(
          controller: codeController,
          icon: Icons.message_rounded,
          hint: '6 位验证码',
          keyboardType: TextInputType.number,
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (_) => onChanged(),
          suffix: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: canSend && !loading ? onSendCode : null,
            child: Padding(
              padding: const EdgeInsets.only(left: 8),
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

    return Padding(
      padding: const EdgeInsets.only(top: 4),
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

/// 主按钮：disabled 时保留品牌色但降低饱和度，不再死灰。
/// busy 时换成圈圈但保留按钮形状不抖动。
class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.busy,
    required this.onPressed,
  });

  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final disabled = onPressed == null && !busy;

    return SizedBox(
      height: 54,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: theme.colorScheme.onPrimary,
          // disabled 时降低透明度而不是切灰色，保留品牌质感
          disabledBackgroundColor: accent.withValues(alpha: 0.32),
          disabledForegroundColor: Colors.white.withValues(alpha: 0.85),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 16,
            letterSpacing: 0.2,
          ),
          elevation: disabled ? 0 : 0,
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
