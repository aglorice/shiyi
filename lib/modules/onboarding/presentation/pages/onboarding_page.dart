import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';

import '../../../../app/settings/app_preferences_controller.dart';

/// 首次启动引导页。
///
/// 设计取向：editorial / Linear / Headspace 风。每张 slide 一个 Lottie 主视觉
/// + 大字标题 + 一行简短正文，舍弃 bullet list 与玻璃卡片，让动画呼吸。
///
/// - 顶部 4 段 progress segments + 跳过；底部宽按钮带箭头。
/// - 背景跟随当前 slide 的色调染色，整体由柔光 vignette 而不是多 blob 堆叠。
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
      caption: '欢迎',
      title: '把校园生活，\n折叠到一处。',
      body: '课表、成绩、电费、体育馆，一个 App 把它们装进口袋。',
      tone: _SlideTone(
        accent: Color(0xFFE38B5C),
        wash: Color(0xFFFAF1E8),
      ),
      lottiePath: 'assets/lottie/onboarding_welcome.json',
    ),
    _OnboardingSlide(
      caption: '登录',
      title: '登一次，\n处处都通。',
      body: '学号密码或短信验证码均可，遇到滑块直接弹出，会话过期主动续签。',
      tone: _SlideTone(
        accent: Color(0xFF6E83C7),
        wash: Color(0xFFEFF2FA),
      ),
      lottiePath: 'assets/lottie/onboarding_login.json',
    ),
    _OnboardingSlide(
      caption: '隐私',
      title: '你的数据，\n只属于你。',
      body: '凭证仅保存在本机，没有云端、没有上报。完全开源，每一行代码都可查。',
      tone: _SlideTone(
        accent: Color(0xFF4FAE7F),
        wash: Color(0xFFEDF6F0),
      ),
      lottiePath: 'assets/lottie/onboarding_privacy.json',
    ),
    _OnboardingSlide(
      caption: '说明',
      title: '请知悉这点。',
      body: '本应用由学生独立开发，与五邑大学官方无关，仅做技术学习。',
      tone: _SlideTone(
        accent: Color(0xFFD06684),
        wash: Color(0xFFFAF0F2),
      ),
      lottiePath: 'assets/lottie/onboarding_handshake.json',
    ),
  ];

  bool get _isLast => _index == _slides.length - 1;
  _OnboardingSlide get _current => _slides[_index];

  Future<void> _finish() async {
    await ref
        .read(appPreferencesControllerProvider.notifier)
        .markOnboardingCompleted();
    if (!mounted) return;
    context.go('/login');
  }

  void _next() {
    if (_isLast) {
      _finish();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 360),
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
    final tone = _current.tone;
    return Scaffold(
      // 整页 wash 跟随当前 slide 主色，配合 BackdropFilter 般的柔光感。
      // AnimatedContainer 让色彩切换平滑而不抖。
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        color: tone.wash,
        child: Stack(
          children: [
            // 单层柔光：当前 slide 的 accent 在右上角扩散，避免多 blob 视觉杂乱。
            Positioned(
              top: -120,
              right: -100,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 420),
                child: _AccentGlow(
                  key: ValueKey(_index),
                  color: tone.accent,
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  _TopBar(
                    total: _slides.length,
                    current: _index,
                    accent: tone.accent,
                    onSkip: _finish,
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
                  _BottomBar(
                    accent: tone.accent,
                    isLast: _isLast,
                    onContinue: _next,
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

class _OnboardingSlide {
  const _OnboardingSlide({
    required this.caption,
    required this.title,
    required this.body,
    required this.tone,
    required this.lottiePath,
  });

  final String caption;
  final String title;
  final String body;
  final _SlideTone tone;
  final String lottiePath;
}

class _SlideTone {
  const _SlideTone({required this.accent, required this.wash});

  /// slide 的强调色，用在 progress 当前段、按钮、caption tag。
  final Color accent;

  /// 整页的浅色 wash，与暖白 #FAF8F6 同调。
  final Color wash;
}

/// 单层柔光：一个大圆形 RadialGradient，呼应当前 slide 的 accent。
class _AccentGlow extends StatelessWidget {
  const _AccentGlow({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: 420,
        height: 420,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: 0.42),
              color.withValues(alpha: 0.0),
            ],
            stops: const [0.0, 1.0],
          ),
        ),
      ),
    );
  }
}

/// 顶部条：左侧 4 段细 progress（已完成段填 accent，未完成段为半透明 outline），
/// 右侧"跳过"。代替底部圆点能让"还有几步"的预期更明确。
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.total,
    required this.current,
    required this.accent,
    required this.onSkip,
  });

  final int total;
  final int current;
  final Color accent;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 14, 12, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Row(
              children: [
                for (var i = 0; i < total; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 320),
                      curve: Curves.easeOut,
                      height: 3,
                      decoration: BoxDecoration(
                        color: i <= current
                            ? accent
                            : theme.colorScheme.outlineVariant
                                  .withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 16),
          TextButton(
            onPressed: onSkip,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              foregroundColor: theme.colorScheme.onSurfaceVariant,
            ),
            child: const Text(
              '跳过',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
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
          // Lottie 视觉占主区，独占大块视觉权重。
          Expanded(
            flex: 6,
            child: Center(
              child: Lottie.asset(
                slide.lottiePath,
                repeat: true,
                fit: BoxFit.contain,
                options: LottieOptions(enableMergePaths: true),
                // 任何 JSON 解析异常 / 渲染异常都不要再让整页变红。
                // 退化成一个柔色的 accent 圆点占位，文字部分仍可读。
                errorBuilder: (context, error, stack) {
                  return Center(
                    child: Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: slide.tone.accent.withValues(alpha: 0.18),
                      ),
                      child: Center(
                        child: Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: slide.tone.accent.withValues(alpha: 0.42),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CaptionTag(text: slide.caption, accent: slide.tone.accent),
                const SizedBox(height: 14),
                // 标题：大字、紧凑行高、负字距，向 magazine cover 靠。
                Text(
                  slide.title,
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.6,
                    height: 1.12,
                    color: const Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 14),
                // 正文：克制不堆砌，一行能完成最有力。
                Text(
                  slide.body,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: const Color(0xFF555555),
                    fontSize: 15,
                    height: 1.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// caption 标签：左侧一根 accent 色短杠 + 大写字符的标签文字，
/// 像编辑设计里的 section 题头。比"第 1 步 · 共 4 步"更轻、更图形化。
class _CaptionTag extends StatelessWidget {
  const _CaptionTag({required this.text, required this.accent});

  final String text;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 18,
          height: 2,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(
            color: accent,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
          ),
        ),
      ],
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.accent,
    required this.isLast,
    required this.onContinue,
  });

  final Color accent;
  final bool isLast;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: SizedBox(
        width: double.infinity,
        height: 54,
        child: FilledButton(
          onPressed: onContinue,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF1A1A1A),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              letterSpacing: 0.3,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(isLast ? '开始使用' : '继续'),
              const SizedBox(width: 8),
              Icon(
                isLast
                    ? Icons.arrow_forward_rounded
                    : Icons.arrow_forward_rounded,
                size: 18,
                color: accent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
