import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 四张引导页的矢量插图。
///
/// 之前手写的 Lottie 在某些 JSON 字段上踩到了 lottie-flutter 的解析坑，
/// 直接落到 errorBuilder 的兜底圆点上。换成 CustomPainter 后：
/// - 100% 受控、跨设备一致；
/// - 每张独立故事、独立色板；
/// - 可以在外面套 AnimationController 加动效，与正在用的卡片切换过渡协调。
enum OnboardingIllustrationKind { welcome, login, privacy, learning }

class OnboardingIllustration extends StatefulWidget {
  const OnboardingIllustration({
    super.key,
    required this.kind,
    required this.accent,
  });

  final OnboardingIllustrationKind kind;
  final Color accent;

  @override
  State<OnboardingIllustration> createState() => _OnboardingIllustrationState();
}

class _OnboardingIllustrationState extends State<OnboardingIllustration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // 4s 一个循环，每张插图按 controller.value (0..1) 自己决定怎么动。
    _controller =
        AnimationController(vsync: this, duration: const Duration(seconds: 4))
          ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _IllustrationPainter(
              kind: widget.kind,
              accent: widget.accent,
              t: _controller.value,
            ),
            child: const SizedBox.expand(),
          );
        },
      ),
    );
  }
}

class _IllustrationPainter extends CustomPainter {
  _IllustrationPainter({
    required this.kind,
    required this.accent,
    required this.t,
  });

  final OnboardingIllustrationKind kind;
  final Color accent;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    switch (kind) {
      case OnboardingIllustrationKind.welcome:
        _paintWelcome(canvas, size);
        break;
      case OnboardingIllustrationKind.login:
        _paintLogin(canvas, size);
        break;
      case OnboardingIllustrationKind.privacy:
        _paintPrivacy(canvas, size);
        break;
      case OnboardingIllustrationKind.learning:
        _paintLearning(canvas, size);
        break;
    }
  }

  // --------------------------------------------------------
  // 1) Welcome —— 中央 phone + 漂浮的 4 张服务卡片做"装进口袋"
  // --------------------------------------------------------
  void _paintWelcome(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final c = Offset(w * 0.5, h * 0.5);

    // 背景柔光
    final glow = RadialGradient(
      colors: [
        accent.withValues(alpha: 0.32),
        accent.withValues(alpha: 0),
      ],
    ).createShader(Rect.fromCircle(center: c, radius: w * 0.45));
    canvas.drawCircle(c, w * 0.45, Paint()..shader = glow);

    // 手机机身
    final phoneRect = Rect.fromCenter(
      center: c.translate(0, _bob(0.3) * 4),
      width: w * 0.34,
      height: w * 0.54,
    );
    final phoneRRect = RRect.fromRectAndRadius(phoneRect, Radius.circular(w * 0.06));
    _drawShadow(canvas, phoneRect.inflate(2));
    canvas.drawRRect(
      phoneRRect,
      Paint()..color = const Color(0xFF1B1B1F),
    );
    final screen = phoneRRect.deflate(w * 0.018);
    canvas.drawRRect(screen, Paint()..color = Colors.white);

    // 状态栏小条
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          screen.left + w * 0.04,
          screen.top + w * 0.025,
          w * 0.06,
          w * 0.012,
        ),
        Radius.circular(w * 0.006),
      ),
      Paint()..color = const Color(0xFF333333),
    );

    // 屏幕里的四张服务图标，各自小幅呼吸
    final serviceColors = const [
      Color(0xFF5C8DEF), // schedule
      Color(0xFF4FB07A), // gym
      Color(0xFFE8A94C), // grades
      Color(0xFFAA77E0), // notice
    ];
    for (var i = 0; i < 4; i++) {
      final col = i % 2;
      final row = i ~/ 2;
      final pop = _pop(0.1 + i * 0.06);
      final tileSize = screen.width * 0.32;
      final origin = Offset(
        screen.left + screen.width * 0.13 + col * (tileSize + screen.width * 0.06),
        screen.top + screen.height * 0.18 + row * (tileSize + screen.width * 0.04),
      );
      final tileRect = Rect.fromLTWH(
        origin.dx,
        origin.dy,
        tileSize,
        tileSize,
      );
      final scaled = Rect.fromCenter(
        center: tileRect.center,
        width: tileRect.width * pop,
        height: tileRect.height * pop,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(scaled, Radius.circular(tileSize * 0.24)),
        Paint()..color = serviceColors[i],
      );
      // 图标内的小符号
      _paintTileGlyph(canvas, scaled, i);
    }

    // 屏幕底部 home 指示条
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(screen.center.dx, screen.bottom - w * 0.022),
          width: screen.width * 0.4,
          height: w * 0.008,
        ),
        Radius.circular(w * 0.004),
      ),
      Paint()..color = const Color(0xFF999999),
    );

    // 周围漂浮的小元素，呼应"零散的服务"
    _drawFloatingChip(
      canvas,
      Offset(w * 0.16, h * 0.22 + _bob(0.1) * 6),
      Color(0xFF5C8DEF),
      angle: -0.2,
    );
    _drawFloatingChip(
      canvas,
      Offset(w * 0.86, h * 0.30 + _bob(0.4) * 6),
      Color(0xFFE8A94C),
      angle: 0.18,
    );
    _drawFloatingChip(
      canvas,
      Offset(w * 0.84, h * 0.78 + _bob(0.2) * 6),
      Color(0xFF4FB07A),
      angle: -0.15,
    );
    _drawFloatingChip(
      canvas,
      Offset(w * 0.14, h * 0.78 + _bob(0.6) * 6),
      Color(0xFFAA77E0),
      angle: 0.12,
    );
  }

  void _paintTileGlyph(Canvas canvas, Rect rect, int kind) {
    final glyph = Paint()
      ..color = Colors.white
      ..strokeCap = StrokeCap.round;
    final c = rect.center;
    final s = rect.width;
    switch (kind) {
      case 0: // schedule grid
        for (var i = 0; i < 3; i++) {
          for (var j = 0; j < 3; j++) {
            canvas.drawCircle(
              Offset(
                c.dx + (j - 1) * s * 0.18,
                c.dy + (i - 1) * s * 0.18,
              ),
              s * 0.04,
              glyph,
            );
          }
        }
        break;
      case 1: // dumbbell
        final barY = c.dy;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset(c.dx, barY),
              width: s * 0.5,
              height: s * 0.07,
            ),
            Radius.circular(s * 0.02),
          ),
          glyph,
        );
        canvas.drawCircle(Offset(c.dx - s * 0.28, barY), s * 0.09, glyph);
        canvas.drawCircle(Offset(c.dx + s * 0.28, barY), s * 0.09, glyph);
        break;
      case 2: // grades = 'A+'
        final tp = TextPainter(
          text: TextSpan(
            text: 'A+',
            style: TextStyle(
              color: Colors.white,
              fontSize: s * 0.45,
              fontWeight: FontWeight.w800,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
        break;
      case 3: // bell
        final bell = Path()
          ..moveTo(c.dx - s * 0.22, c.dy + s * 0.12)
          ..quadraticBezierTo(
            c.dx,
            c.dy - s * 0.32,
            c.dx + s * 0.22,
            c.dy + s * 0.12,
          )
          ..close();
        canvas.drawPath(bell, glyph);
        canvas.drawCircle(Offset(c.dx, c.dy + s * 0.22), s * 0.05, glyph);
        break;
    }
  }

  void _drawFloatingChip(
    Canvas canvas,
    Offset center,
    Color color, {
    required double angle,
  }) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    canvas.translate(-center.dx, -center.dy);
    final rect = Rect.fromCenter(
      center: center,
      width: 56,
      height: 56,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(14)),
      Paint()..color = color.withValues(alpha: 0.95),
    );
    canvas.drawCircle(
      center,
      14,
      Paint()..color = Colors.white.withValues(alpha: 0.85),
    );
    canvas.restore();
  }

  // --------------------------------------------------------
  // 2) Login —— 中央 SSO Key + 4 个服务节点 + 扫描线
  // --------------------------------------------------------
  void _paintLogin(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final c = Offset(w * 0.5, h * 0.5);
    final r = w * 0.32;

    // 背景柔光
    canvas.drawCircle(
      c,
      r * 1.5,
      Paint()
        ..shader = RadialGradient(colors: [
          accent.withValues(alpha: 0.3),
          accent.withValues(alpha: 0),
        ]).createShader(Rect.fromCircle(center: c, radius: r * 1.5)),
    );

    // 虚线轨道
    _drawDashedCircle(
      canvas,
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = accent.withValues(alpha: 0.45),
      dashLen: 6,
      gapLen: 8,
    );

    // 扫描线
    final scanAngle = t * math.pi * 2;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(scanAngle);
    final scanPaint = Paint()
      ..shader = LinearGradient(
        colors: [accent.withValues(alpha: 0.0), accent.withValues(alpha: 0.7)],
      ).createShader(Rect.fromLTWH(0, -2, r, 4));
    canvas.drawRRect(
      RRect.fromLTRBR(0, -2.5, r, 2.5, const Radius.circular(2)),
      scanPaint,
    );
    canvas.restore();

    // 4 个服务节点
    const nodeAngles = [-math.pi / 2, 0.0, math.pi / 2, math.pi];
    final nodeColors = [
      const Color(0xFF5C8DEF),
      const Color(0xFF4FB07A),
      const Color(0xFFE8A94C),
      const Color(0xFFAA77E0),
    ];
    for (var i = 0; i < 4; i++) {
      final angle = nodeAngles[i];
      final pos = c + Offset(math.cos(angle), math.sin(angle)) * r;
      final glow = (((t * 4) - i) % 4).clamp(0.0, 1.0);
      final glowPaint = Paint()..color = nodeColors[i].withValues(alpha: 0.25 * (1 - glow));
      canvas.drawCircle(pos, 28 + 16 * glow, glowPaint);

      canvas.drawCircle(pos, 22, Paint()..color = Colors.white);
      canvas.drawCircle(
        pos,
        22,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = nodeColors[i],
      );
      // 节点内部 mini-icon
      _paintNodeGlyph(canvas, pos, 22, i, nodeColors[i]);
    }

    // 中心大圆
    final coreShadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.12)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(c.translate(0, 4), 38, coreShadow);
    canvas.drawCircle(c, 38, Paint()..color = const Color(0xFF1B1B1F));

    // 钥匙
    final keyOffset = c;
    canvas.drawCircle(
      keyOffset.translate(-8, 0),
      11,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = const Color(0xFFFFD972),
    );
    canvas.drawRRect(
      RRect.fromLTRBR(
        keyOffset.dx + 0,
        keyOffset.dy - 3,
        keyOffset.dx + 18,
        keyOffset.dy + 3,
        const Radius.circular(2),
      ),
      Paint()..color = const Color(0xFFFFD972),
    );
    canvas.drawRect(
      Rect.fromLTWH(
        keyOffset.dx + 14,
        keyOffset.dy + 3,
        4,
        6,
      ),
      Paint()..color = const Color(0xFFFFD972),
    );
  }

  void _paintNodeGlyph(
    Canvas canvas,
    Offset center,
    double size,
    int index,
    Color color,
  ) {
    final p = Paint()..color = color;
    switch (index) {
      case 0: // calendar
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: center, width: 16, height: 12),
            const Radius.circular(2),
          ),
          p,
        );
        canvas.drawRect(
          Rect.fromCenter(
            center: center.translate(0, -7),
            width: 16,
            height: 4,
          ),
          p,
        );
        break;
      case 1: // user
        canvas.drawCircle(center.translate(0, -3), 4, p);
        canvas.drawArc(
          Rect.fromCenter(
            center: center.translate(0, 5),
            width: 14,
            height: 10,
          ),
          math.pi,
          math.pi,
          true,
          p,
        );
        break;
      case 2: // shape "doc"
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: center, width: 12, height: 16),
            const Radius.circular(2),
          ),
          p,
        );
        for (var i = 0; i < 3; i++) {
          canvas.drawRect(
            Rect.fromCenter(
              center: Offset(center.dx, center.dy - 3 + i * 3),
              width: 8,
              height: 1.4,
            ),
            Paint()..color = Colors.white.withValues(alpha: 0.7),
          );
        }
        break;
      case 3: // bell mini
        final path = Path()
          ..moveTo(center.dx - 7, center.dy + 4)
          ..quadraticBezierTo(center.dx, center.dy - 9, center.dx + 7, center.dy + 4)
          ..close();
        canvas.drawPath(path, p);
        canvas.drawCircle(Offset(center.dx, center.dy + 8), 1.8, p);
        break;
    }
  }

  // --------------------------------------------------------
  // 3) Privacy —— 盾内嵌 phone，外有阻挡
  // --------------------------------------------------------
  void _paintPrivacy(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final c = Offset(w * 0.5, h * 0.5);

    // 背景柔光
    canvas.drawCircle(
      c,
      w * 0.42,
      Paint()
        ..shader = RadialGradient(colors: [
          accent.withValues(alpha: 0.28),
          accent.withValues(alpha: 0),
        ]).createShader(Rect.fromCircle(center: c, radius: w * 0.42)),
    );

    // ripple 三圈
    for (var i = 0; i < 3; i++) {
      final phase = (t + i * 0.33) % 1.0;
      final r = w * 0.18 + phase * w * 0.22;
      final opacity = (1 - phase) * 0.55;
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = accent.withValues(alpha: opacity),
      );
    }

    // 盾外形
    final shieldPath = _shieldPath(c, w * 0.30, h * 0.40);
    final shieldFill = Paint()..color = accent;
    _drawShadow(canvas, shieldPath.getBounds().inflate(4));
    canvas.drawPath(shieldPath, shieldFill);

    final innerShield = _shieldPath(c, w * 0.24, h * 0.32);
    canvas.drawPath(
      innerShield,
      Paint()..color = const Color(0xFFF5FBF6),
    );

    // 盾内 phone
    final phoneRect = Rect.fromCenter(
      center: c,
      width: w * 0.22,
      height: w * 0.32,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(phoneRect, Radius.circular(w * 0.04)),
      Paint()..color = const Color(0xFF1B1B1F),
    );
    final screen = RRect.fromRectAndRadius(
      phoneRect.deflate(w * 0.012),
      Radius.circular(w * 0.025),
    );
    canvas.drawRRect(screen, Paint()..color = accent);

    // phone 内文字条 + 头像
    canvas.drawCircle(
      Offset(screen.center.dx - w * 0.04, screen.center.dy - w * 0.05),
      w * 0.022,
      Paint()..color = Colors.white,
    );
    for (var i = 0; i < 4; i++) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            screen.left + w * 0.022,
            screen.center.dy - w * 0.005 + i * w * 0.026,
            w * 0.18 - i * w * 0.025,
            w * 0.012,
          ),
          Radius.circular(w * 0.004),
        ),
        Paint()..color = Colors.white.withValues(alpha: 0.7 - i * 0.12),
      );
    }

    // 阻挡：四个角的红色 ✕
    final crossPositions = [
      Offset(w * 0.18, h * 0.18),
      Offset(w * 0.82, h * 0.20),
      Offset(w * 0.84, h * 0.82),
      Offset(w * 0.16, h * 0.80),
    ];
    for (var i = 0; i < 4; i++) {
      final pulse = (((t * 2) - i * 0.25) % 2).toDouble();
      final double visible =
          pulse < 0.4 ? pulse / 0.4 : (pulse < 0.6 ? 1.0 : 0.0);
      if (visible <= 0) continue;
      _drawCross(
        canvas,
        crossPositions[i],
        12 * visible,
        Paint()
          ..color = const Color(0xFFE86969).withValues(alpha: 0.85 * visible)
          ..strokeWidth = 4 * visible
          ..strokeCap = StrokeCap.round,
      );
    }

    // 中央底部锁芯（蜜蜂 / 锁的小细节）
    canvas.drawCircle(
      Offset(c.dx, c.dy + w * 0.12),
      w * 0.018,
      Paint()..color = Colors.white,
    );
  }

  Path _shieldPath(Offset center, double halfWidth, double halfHeight) {
    final p = Path();
    p.moveTo(center.dx, center.dy - halfHeight);
    p.cubicTo(
      center.dx + halfWidth * 0.7, center.dy - halfHeight,
      center.dx + halfWidth, center.dy - halfHeight * 0.8,
      center.dx + halfWidth, center.dy - halfHeight * 0.3,
    );
    p.cubicTo(
      center.dx + halfWidth, center.dy + halfHeight * 0.5,
      center.dx + halfWidth * 0.6, center.dy + halfHeight * 0.92,
      center.dx, center.dy + halfHeight,
    );
    p.cubicTo(
      center.dx - halfWidth * 0.6, center.dy + halfHeight * 0.92,
      center.dx - halfWidth, center.dy + halfHeight * 0.5,
      center.dx - halfWidth, center.dy - halfHeight * 0.3,
    );
    p.cubicTo(
      center.dx - halfWidth, center.dy - halfHeight * 0.8,
      center.dx - halfWidth * 0.7, center.dy - halfHeight,
      center.dx, center.dy - halfHeight,
    );
    p.close();
    return p;
  }

  void _drawCross(Canvas canvas, Offset center, double size, Paint paint) {
    paint.style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(center.dx - size, center.dy - size),
      Offset(center.dx + size, center.dy + size),
      paint,
    );
    canvas.drawLine(
      Offset(center.dx + size, center.dy - size),
      Offset(center.dx - size, center.dy + size),
      paint,
    );
  }

  // --------------------------------------------------------
  // 4) Learning —— 翻开的书 + 学士帽 + 漂浮代码
  // --------------------------------------------------------
  void _paintLearning(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final c = Offset(w * 0.5, h * 0.5);

    // 背景柔光
    canvas.drawCircle(
      c,
      w * 0.45,
      Paint()
        ..shader = RadialGradient(colors: [
          accent.withValues(alpha: 0.30),
          accent.withValues(alpha: 0),
        ]).createShader(Rect.fromCircle(center: c, radius: w * 0.45)),
    );

    // 翻开的书
    final bookCenter = Offset(c.dx, c.dy + h * 0.12 + _bob(0.5) * 3);
    final bookHalfW = w * 0.30;
    final bookH = h * 0.28;

    // 书脊（最深底）
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: bookCenter,
          width: bookHalfW * 2,
          height: bookH * 1.05,
        ),
        Radius.circular(w * 0.025),
      ),
      Paint()..color = const Color(0xFF8C3A4F),
    );

    // 左右两页
    for (var side = -1; side <= 1; side += 2) {
      final pageRect = Rect.fromCenter(
        center: Offset(bookCenter.dx + side * bookHalfW * 0.51, bookCenter.dy),
        width: bookHalfW * 0.97,
        height: bookH * 0.95,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(pageRect, const Radius.circular(8)),
        Paint()..color = const Color(0xFFFFFAF1),
      );
      // 标题条
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            pageRect.left + 14,
            pageRect.top + 14,
            pageRect.width * 0.5,
            5,
          ),
          const Radius.circular(2),
        ),
        Paint()..color = const Color(0xFFC97A8C),
      );
      // 文字行
      for (var i = 0; i < 6; i++) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              pageRect.left + 14,
              pageRect.top + 30 + i * 12,
              pageRect.width * (0.78 - (i % 3) * 0.07),
              3,
            ),
            const Radius.circular(1.5),
          ),
          Paint()..color = const Color(0xFFD8AFB7),
        );
      }
    }

    // 书脊中间分隔线
    canvas.drawLine(
      Offset(bookCenter.dx, bookCenter.dy - bookH * 0.45),
      Offset(bookCenter.dx, bookCenter.dy + bookH * 0.45),
      Paint()
        ..color = const Color(0xFF8C3A4F).withValues(alpha: 0.5)
        ..strokeWidth = 1.5,
    );

    // 学士帽
    final capCenter = Offset(c.dx, c.dy - h * 0.05 + _bob(0.2) * 4);
    final capPath = Path()
      ..moveTo(capCenter.dx - w * 0.16, capCenter.dy)
      ..lineTo(capCenter.dx, capCenter.dy - w * 0.10)
      ..lineTo(capCenter.dx + w * 0.16, capCenter.dy)
      ..lineTo(capCenter.dx, capCenter.dy + w * 0.04)
      ..close();
    canvas.drawPath(capPath, Paint()..color = const Color(0xFF1B1B1F));
    // 帽座
    final basePath = Path()
      ..moveTo(capCenter.dx - w * 0.10, capCenter.dy + w * 0.025)
      ..lineTo(capCenter.dx - w * 0.10, capCenter.dy + w * 0.06)
      ..quadraticBezierTo(
        capCenter.dx,
        capCenter.dy + w * 0.10,
        capCenter.dx + w * 0.10,
        capCenter.dy + w * 0.06,
      )
      ..lineTo(capCenter.dx + w * 0.10, capCenter.dy + w * 0.025)
      ..close();
    canvas.drawPath(basePath, Paint()..color = const Color(0xFF24242A));

    // 帽穗（钟摆）
    final tasselTop = Offset(capCenter.dx + w * 0.10, capCenter.dy);
    final tasselAngle = math.sin(t * math.pi * 2) * 0.4;
    final tasselEnd = tasselTop.translate(
      math.sin(tasselAngle) * w * 0.05,
      math.cos(tasselAngle) * w * 0.08,
    );
    canvas.drawLine(
      tasselTop,
      tasselEnd,
      Paint()
        ..color = const Color(0xFFE8A94C)
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(tasselEnd, w * 0.02, Paint()..color = const Color(0xFFE8A94C));

    // 漂浮代码符号
    _drawCodeTag(
      canvas,
      Offset(w * 0.18, h * 0.22 + _bob(0.0) * 6),
      const Color(0xFF5C8DEF),
      isOpen: true,
    );
    _drawSlash(
      canvas,
      Offset(w * 0.5, h * 0.16 + _bob(0.3) * 6),
      const Color(0xFFE8A94C),
    );
    _drawCodeTag(
      canvas,
      Offset(w * 0.84, h * 0.24 + _bob(0.6) * 6),
      const Color(0xFFAA77E0),
      isOpen: false,
    );
  }

  void _drawCodeTag(Canvas canvas, Offset center, Color color,
      {required bool isOpen}) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final p = Path();
    final s = 12.0;
    if (isOpen) {
      p.moveTo(center.dx + s, center.dy - s);
      p.lineTo(center.dx - s, center.dy);
      p.lineTo(center.dx + s, center.dy + s);
    } else {
      p.moveTo(center.dx - s, center.dy - s);
      p.lineTo(center.dx + s, center.dy);
      p.lineTo(center.dx - s, center.dy + s);
    }
    canvas.drawPath(p, paint);
  }

  void _drawSlash(Canvas canvas, Offset center, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(center.dx - 6, center.dy + 12),
      Offset(center.dx + 6, center.dy - 12),
      paint,
    );
  }

  // --------------------------------------------------------
  // 共用工具
  // --------------------------------------------------------

  /// 一个 0..1 → -1..1 的连续呼吸函数。phase 用来让多个元素错峰。
  double _bob(double phase) => math.sin((t + phase) * math.pi * 2);

  /// 0..1 → 0.92..1.06 的脉冲，用来给"卡片冒出来"的弹性效果。
  double _pop(double phase) {
    final v = math.sin((t + phase) * math.pi * 2);
    return 1.0 + v * 0.05;
  }

  void _drawShadow(Canvas canvas, Rect rect) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.translate(0, 6), const Radius.circular(20)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.10)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
  }

  /// 沿圆周画虚线。
  void _drawDashedCircle(
    Canvas canvas,
    Offset center,
    double radius,
    Paint paint, {
    required double dashLen,
    required double gapLen,
  }) {
    final circumference = 2 * math.pi * radius;
    final dashCount = (circumference / (dashLen + gapLen)).floor();
    final anglePerDash = (math.pi * 2) / dashCount;
    for (var i = 0; i < dashCount; i++) {
      final start = i * anglePerDash;
      final sweep = anglePerDash * (dashLen / (dashLen + gapLen));
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        sweep,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _IllustrationPainter old) =>
      old.t != t || old.kind != kind || old.accent != accent;
}
