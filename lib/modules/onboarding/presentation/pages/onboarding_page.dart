import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
      illustration: _IllustrationKind.welcome,
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
      illustration: _IllustrationKind.login,
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
      illustration: _IllustrationKind.privacy,
    ),
    _OnboardingSlide(
      title: '只用于学习交流',
      subtitle: '使用前请知悉以下内容',
      bullets: [
        '本应用与五邑大学官方无关，仅做技术学习',
        '所有功能均为对公开门户的封装，不绕过任何鉴权',
        '后续接入的接口若学校认为不合适会随时下线',
      ],
      gradient: _SlideGradient(
        primary: Color(0xFFFFD3DD),
        secondary: Color(0xFFFFE0C2),
        background: Color(0xFFFAF3F4),
      ),
      illustration: _IllustrationKind.handshake,
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
    required this.illustration,
  });

  final String title;
  final String subtitle;
  final List<String> bullets;
  final _SlideGradient gradient;
  final _IllustrationKind illustration;
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

enum _IllustrationKind { welcome, login, privacy, handshake }

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
                child: _Illustration(
                  kind: slide.illustration,
                  gradient: slide.gradient,
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

// =====================================================================
// 矢量插图：每张 slide 一组手绘元素，全部 CustomPainter，不需要图片资源
// =====================================================================

class _Illustration extends StatelessWidget {
  const _Illustration({required this.kind, required this.gradient});

  final _IllustrationKind kind;
  final _SlideGradient gradient;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _IllustrationPainter(kind: kind, gradient: gradient),
      child: const SizedBox.expand(),
    );
  }
}

class _IllustrationPainter extends CustomPainter {
  _IllustrationPainter({required this.kind, required this.gradient});

  final _IllustrationKind kind;
  final _SlideGradient gradient;

  @override
  void paint(Canvas canvas, Size size) {
    switch (kind) {
      case _IllustrationKind.welcome:
        _paintWelcome(canvas, size);
        break;
      case _IllustrationKind.login:
        _paintLogin(canvas, size);
        break;
      case _IllustrationKind.privacy:
        _paintPrivacy(canvas, size);
        break;
      case _IllustrationKind.handshake:
        _paintHandshake(canvas, size);
        break;
    }
  }

  // -------- 1) 欢迎：堆叠的 mini App 卡片 --------
  void _paintWelcome(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cardWidth = w * 0.7;
    final cardHeight = h * 0.32;

    // 远端两张装饰卡（底层）
    _drawCard(
      canvas,
      Rect.fromCenter(
        center: Offset(w * 0.36, h * 0.42),
        width: cardWidth * 0.92,
        height: cardHeight * 0.92,
      ),
      color: gradient.primary.withValues(alpha: 0.85),
      rotation: -0.06,
    );
    _drawCard(
      canvas,
      Rect.fromCenter(
        center: Offset(w * 0.66, h * 0.46),
        width: cardWidth * 0.96,
        height: cardHeight * 0.96,
      ),
      color: gradient.secondary,
      rotation: 0.05,
    );

    // 主卡：最前面，画一些假课程行
    final mainRect = Rect.fromCenter(
      center: Offset(w * 0.5, h * 0.55),
      width: cardWidth,
      height: cardHeight * 1.2,
    );
    _drawCard(
      canvas,
      mainRect,
      color: Colors.white,
      shadow: true,
    );

    final padding = mainRect.width * 0.08;
    final inner = mainRect.deflate(padding);
    final lineHeight = inner.height / 4.5;

    // 顶部小标题条
    _drawPill(
      canvas,
      Rect.fromLTWH(
        inner.left,
        inner.top,
        inner.width * 0.34,
        lineHeight * 0.5,
      ),
      const Color(0xFF1A1A1A),
    );
    _drawPill(
      canvas,
      Rect.fromLTWH(
        inner.left,
        inner.top + lineHeight * 0.7,
        inner.width * 0.5,
        lineHeight * 0.32,
      ),
      const Color(0xFFAAAAAA),
    );
    // 假课程条目
    for (var i = 0; i < 2; i++) {
      final base = inner.top + lineHeight * 1.5 + i * lineHeight * 1.05;
      _drawPill(
        canvas,
        Rect.fromLTWH(
          inner.left,
          base,
          lineHeight * 0.4,
          lineHeight * 0.7,
        ),
        i == 0 ? const Color(0xFF1C8C6E) : const Color(0xFFE8A838),
      );
      _drawPill(
        canvas,
        Rect.fromLTWH(
          inner.left + lineHeight * 0.6,
          base,
          inner.width * 0.55,
          lineHeight * 0.35,
        ),
        const Color(0xFF222222),
      );
      _drawPill(
        canvas,
        Rect.fromLTWH(
          inner.left + lineHeight * 0.6,
          base + lineHeight * 0.4,
          inner.width * 0.4,
          lineHeight * 0.28,
        ),
        const Color(0xFFAAAAAA),
      );
    }

    // 几颗装饰点
    _drawDot(canvas, Offset(w * 0.18, h * 0.22), 6, gradient.primary);
    _drawDot(canvas, Offset(w * 0.86, h * 0.22), 4, gradient.secondary);
    _drawDot(canvas, Offset(w * 0.82, h * 0.85), 8,
        gradient.primary.withValues(alpha: 0.8));
  }

  // -------- 2) 登录：盾牌 + 钥匙 + 一根光线 --------
  void _paintLogin(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w * 0.5, h * 0.5);

    // 圆环
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.018
      ..color = gradient.primary;
    canvas.drawCircle(center, w * 0.34, ringPaint);

    final ring2Paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.01
      ..color = gradient.secondary;
    canvas.drawCircle(center, w * 0.42, ring2Paint);

    // 中间圆形卡片
    final cardCircle = Rect.fromCircle(center: center, radius: w * 0.22);
    canvas.drawCircle(center, w * 0.22,
        Paint()..color = Colors.white);
    canvas.drawCircle(
      center,
      w * 0.22,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = const Color(0x22000000),
    );

    // 钥匙图标（手绘）
    final keyPaint = Paint()
      ..color = const Color(0xFF1A1A1A)
      ..style = PaintingStyle.fill;

    final keyRing = Rect.fromCircle(
      center: Offset(cardCircle.center.dx - w * 0.05, cardCircle.center.dy),
      radius: w * 0.05,
    );
    canvas.drawCircle(
      keyRing.center,
      w * 0.05,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.015
        ..color = const Color(0xFF1A1A1A),
    );

    // 钥匙杆
    final shaftRect = Rect.fromLTWH(
      keyRing.right - w * 0.005,
      keyRing.center.dy - w * 0.012,
      w * 0.13,
      w * 0.024,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(shaftRect, Radius.circular(w * 0.012)),
      keyPaint,
    );
    // 齿
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          shaftRect.right - w * 0.018,
          shaftRect.bottom - w * 0.005,
          w * 0.018,
          w * 0.04,
        ),
        Radius.circular(w * 0.005),
      ),
      keyPaint,
    );

    // 一道光线
    final ray = Path();
    ray.moveTo(w * 0.78, h * 0.18);
    ray.lineTo(w * 0.92, h * 0.06);
    canvas.drawPath(
      ray,
      Paint()
        ..color = const Color(0xFF1A1A1A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.012
        ..strokeCap = StrokeCap.round,
    );
    _drawDot(canvas, Offset(w * 0.92, h * 0.06), 5, const Color(0xFF1A1A1A));

    // 装饰星点
    _drawSpark(canvas, Offset(w * 0.18, h * 0.30), w * 0.04);
    _drawSpark(canvas, Offset(w * 0.82, h * 0.78), w * 0.05);
  }

  // -------- 3) 隐私：大锁 + 周围浮起的圈 --------
  void _paintPrivacy(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w * 0.5, h * 0.5);

    // 后面三圈
    for (var i = 0; i < 3; i++) {
      final r = w * 0.2 + i * w * 0.07;
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.008
          ..color = (i.isEven ? gradient.primary : gradient.secondary)
              .withValues(alpha: 0.65 - i * 0.18),
      );
    }

    // 锁体
    final lockBody = Rect.fromCenter(
      center: Offset(center.dx, center.dy + h * 0.05),
      width: w * 0.32,
      height: w * 0.26,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(lockBody, Radius.circular(w * 0.04)),
      Paint()..color = Colors.white,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(lockBody, Radius.circular(w * 0.04)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.008
        ..color = const Color(0xFF1A1A1A),
    );

    // 锁口（弧形）
    final shacklePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.018
      ..color = const Color(0xFF1A1A1A)
      ..strokeCap = StrokeCap.round;
    final shackleRect = Rect.fromCenter(
      center: Offset(lockBody.center.dx, lockBody.top),
      width: lockBody.width * 0.6,
      height: lockBody.height * 0.9,
    );
    canvas.drawArc(shackleRect, math.pi, math.pi, false, shacklePaint);

    // 中心钥匙孔
    canvas.drawCircle(
      Offset(lockBody.center.dx, lockBody.center.dy - w * 0.005),
      w * 0.014,
      Paint()..color = const Color(0xFF1A1A1A),
    );
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(lockBody.center.dx, lockBody.center.dy + w * 0.018),
        width: w * 0.012,
        height: w * 0.04,
      ),
      Paint()..color = const Color(0xFF1A1A1A),
    );

    _drawSpark(canvas, Offset(w * 0.2, h * 0.25), w * 0.045);
    _drawSpark(canvas, Offset(w * 0.78, h * 0.18), w * 0.035);
  }

  // -------- 4) 握手 / 学习交流：两个错位卡片 + 心形点 --------
  void _paintHandshake(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 两叠卡片
    _drawCard(
      canvas,
      Rect.fromCenter(
        center: Offset(w * 0.36, h * 0.5),
        width: w * 0.42,
        height: h * 0.4,
      ),
      color: gradient.primary,
      rotation: -0.08,
    );
    _drawCard(
      canvas,
      Rect.fromCenter(
        center: Offset(w * 0.62, h * 0.52),
        width: w * 0.42,
        height: h * 0.4,
      ),
      color: gradient.secondary,
      rotation: 0.08,
    );

    // 中间一颗心
    final heartCenter = Offset(w * 0.5, h * 0.5);
    final heartSize = w * 0.16;
    final heartPath = Path();
    heartPath.moveTo(heartCenter.dx, heartCenter.dy + heartSize * 0.35);
    heartPath.cubicTo(
      heartCenter.dx - heartSize * 0.85,
      heartCenter.dy - heartSize * 0.2,
      heartCenter.dx - heartSize * 0.55,
      heartCenter.dy - heartSize * 0.85,
      heartCenter.dx,
      heartCenter.dy - heartSize * 0.35,
    );
    heartPath.cubicTo(
      heartCenter.dx + heartSize * 0.55,
      heartCenter.dy - heartSize * 0.85,
      heartCenter.dx + heartSize * 0.85,
      heartCenter.dy - heartSize * 0.2,
      heartCenter.dx,
      heartCenter.dy + heartSize * 0.35,
    );
    canvas.drawPath(
      heartPath,
      Paint()..color = const Color(0xFFE57373),
    );

    // 装饰点
    _drawDot(canvas, Offset(w * 0.2, h * 0.2), 6, const Color(0xFF1A1A1A));
    _drawDot(canvas, Offset(w * 0.82, h * 0.18), 5, const Color(0xFF1A1A1A));
    _drawDot(canvas, Offset(w * 0.82, h * 0.82), 8, gradient.primary);
  }

  // -------------------- 工具 --------------------

  void _drawCard(
    Canvas canvas,
    Rect rect, {
    required Color color,
    double rotation = 0,
    bool shadow = false,
  }) {
    canvas.save();
    canvas.translate(rect.center.dx, rect.center.dy);
    canvas.rotate(rotation);
    canvas.translate(-rect.center.dx, -rect.center.dy);
    if (shadow) {
      final shadowPath = Path()
        ..addRRect(
          RRect.fromRectAndRadius(
            rect.shift(const Offset(0, 8)),
            const Radius.circular(20),
          ),
        );
      canvas.drawShadow(shadowPath, Colors.black.withValues(alpha: 0.18), 16, true);
    }
    final r = RRect.fromRectAndRadius(rect, const Radius.circular(20));
    canvas.drawRRect(r, Paint()..color = color);
    canvas.drawRRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.6
        ..color = const Color(0x22000000),
    );
    canvas.restore();
  }

  void _drawPill(Canvas canvas, Rect rect, Color color) {
    final r = RRect.fromRectAndRadius(
      rect,
      Radius.circular(rect.height * 0.45),
    );
    canvas.drawRRect(r, Paint()..color = color.withValues(alpha: 0.85));
  }

  void _drawDot(Canvas canvas, Offset center, double radius, Color color) {
    canvas.drawCircle(center, radius, Paint()..color = color);
  }

  void _drawSpark(Canvas canvas, Offset center, double size) {
    final paint = Paint()
      ..color = const Color(0xFF1A1A1A)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = size * 0.18;
    canvas.drawLine(
      Offset(center.dx - size, center.dy),
      Offset(center.dx + size, center.dy),
      paint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - size),
      Offset(center.dx, center.dy + size),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _IllustrationPainter old) {
    return old.kind != kind || old.gradient != gradient;
  }
}
