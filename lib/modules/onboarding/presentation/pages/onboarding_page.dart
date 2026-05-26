import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';

import '../../../../app/settings/app_preferences_controller.dart';
import '../../../../app/theme/design_tokens.dart';

/// 首次启动引导页。
///
/// 4 张 slide 介绍：欢迎、能做什么、如何登录、隐私承诺。
/// 完成后写入 `preferences.onboardingCompleted=true`，router 不再把用户
/// 引到这里。每张 slide 各自配一对柔和渐变色 + 矢量插图，
/// 与 Apple/Notion 那种引导页的"轻插画 + 大字"风格靠拢。
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final _controller = PageController();
  int _index = 0;

  static const _slides = <_OnboardingSlide>[
    _OnboardingSlide(
      title: '欢迎来到拾邑',
      subtitle: '五邑大学非官方校园助手，把零散系统整合到一处',
      bullets: [
        '课表 / 成绩 / 考试，从教务系统一次取齐',
        '宿舍电费 / 体育馆预约，无需切换浏览器',
        '校园通知 / 要闻，自动同步到本地',
      ],
      gradient: _SlideGradient(
        primary: Color(0xFFFFD7C2),
        secondary: Color(0xFFFFE9B0),
        background: Color(0xFFFAF5F0),
      ),
      lottiePath: 'assets/lottie/onboarding_welcome.json',
    ),
    _OnboardingSlide(
      title: '一次登录，处处可用',
      subtitle: '基于学校统一身份认证（SSO），凭证持有者只有你',
      bullets: [
        '支持学号密码、手机号验证码两种登录',
        '需要滑块时会自动弹出，不需要切到浏览器',
        '会话过期会主动重新登录，不打断你的浏览',
      ],
      gradient: _SlideGradient(
        primary: Color(0xFFC9E4FF),
        secondary: Color(0xFFE6D7FF),
        background: Color(0xFFF4F7FB),
      ),
      lottiePath: 'assets/lottie/onboarding_login.json',
    ),
    _OnboardingSlide(
      title: '凭证只属于你',
      subtitle: '应用没有任何后端，所有数据都在你手机里',
      bullets: [
        '学号 / 密码加密存储在本机，不会上传',
        '请求日志只保留在内存里，可在设置中查看',
        '完全开源，可在 GitHub 上验证我们说的一切',
      ],
      gradient: _SlideGradient(
        primary: Color(0xFFC8EAD2),
        secondary: Color(0xFFD8F1E5),
        background: Color(0xFFF1F8F4),
      ),
      lottiePath: 'assets/lottie/onboarding_privacy.json',
    ),
    _OnboardingSlide(
      title: '只用于学习交流',
      subtitle: '使用前请知悉以下内容',
      bullets: [
        '本应用与五邑大学官方无关，仅做技术学习',
        '所有功能均为对公开门户的封装，不绕过任何鉴权',
      ],
      gradient: _SlideGradient(
        primary: Color(0xFFFFD3DD),
        secondary: Color(0xFFFFE0C2),
        background: Color(0xFFFAF3F4),
      ),
      lottiePath: 'assets/lottie/onboarding_handshake.json',
    ),
  ];

  bool get _isLast => _index == _slides.length - 1;

  Future<void> _finish() async {
    await ref
        .read(appPreferencesControllerProvider.notifier)
        .markOnboardingCompleted();
    if (!mounted) return;
    // router 的 redirect 会把已完成 onboarding 的用户引到登录页或主页。
    context.go('/login');
  }

  void _next() {
    if (_isLast) {
      _finish();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = _slides[_index];

    return Scaffold(
      // 让 slide 自己填充背景色（per-slide），整体 Scaffold 用透明。
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(color: current.gradient.background),
        child: Stack(
          children: [
            // 背景柔光（两个大色块 + 模糊 + 偏移），跟随当前 slide 渐变。
            Positioned.fill(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 380),
                child: _GradientBackdrop(
                  key: ValueKey(_index),
                  gradient: current.gradient,
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  // 顶部跳过按钮，避免新用户被锁在引导里。
                  Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8, right: 12),
                      child: TextButton(
                        onPressed: _finish,
                        child: Text(
                          '跳过',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF555555),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: PageView.builder(
                      controller: _controller,
                      itemCount: _slides.length,
                      onPageChanged: (i) => setState(() => _index = i),
                      itemBuilder: (_, index) =>
                          _SlideView(slide: _slides[index]),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _Dots(count: _slides.length, current: _index),
                  const SizedBox(height: 24),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
                    child: SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: FilledButton(
                        onPressed: _next,
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
                        child: Text(_isLast ? '开始使用' : '下一步'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 每张 slide 的元数据。
class _OnboardingSlide {
  const _OnboardingSlide({
    required this.title,
    required this.subtitle,
    required this.bullets,
    required this.gradient,
    required this.lottiePath,
  });

  final String title;
  final String subtitle;
  final List<String> bullets;
  final _SlideGradient gradient;
  final String lottiePath;
}

class _SlideGradient {
  const _SlideGradient({
    required this.primary,
    required this.secondary,
    required this.background,
  });

  final Color primary;
  final Color secondary;
  final Color background;
}

/// 背景：两个大圆形高斯模糊色块，呼应小红书 / Apple 的"光感"风。
class _GradientBackdrop extends StatelessWidget {
  const _GradientBackdrop({super.key, required this.gradient});

  final _SlideGradient gradient;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: -120,
            left: -80,
            child: _Blob(color: gradient.primary, size: 320),
          ),
          Positioned(
            top: 200,
            right: -100,
            child: _Blob(color: gradient.secondary, size: 360),
          ),
          Positioned(
            bottom: -160,
            left: 40,
            child: _Blob(
              color: gradient.primary.withValues(alpha: 0.6),
              size: 280,
            ),
          ),
        ],
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withValues(alpha: 0.85),
            color.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 1.0],
        ),
      ),
    );
  }
}

class _SlideView extends StatelessWidget {
  const _SlideView({required this.slide});

  final _OnboardingSlide slide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          // 大插图区，视觉重心
          Expanded(
            flex: 5,
            child: Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: Lottie.asset(
                  slide.lottiePath,
                  // Lottie 自带循环，repeat: true 让动画一直跑。
                  repeat: true,
                  // 关闭 frameRate 限制让运动更顺滑。
                  options: LottieOptions(enableMergePaths: true),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // 文字 + bullet 卡片，玻璃磨砂感
          Expanded(
            flex: 4,
            child: _TextCard(slide: slide, theme: theme),
          ),
        ],
      ),
    );
  }
}

class _TextCard extends StatelessWidget {
  const _TextCard({required this.slide, required this.theme});

  final _OnboardingSlide slide;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.55),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.6),
              width: 0.5,
            ),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                slide.title,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  height: 1.1,
                  color: const Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                slide.subtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF555555),
                  height: 1.45,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              ...slide.bullets.map(
                (bullet) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          bullet,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF222222),
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final selected = i == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: selected ? 18 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFF1A1A1A)
                : const Color(0x331A1A1A),
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }
}

