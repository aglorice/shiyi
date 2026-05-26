import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 四张引导页的矢量插图。
///
/// 设计目标：
/// - 主体大、贴边描边、配 accent 渐变与高光，看起来像精修过的插画而不是矢量草图。
/// - 每张围绕"一个主物 + 1~2 个副元素 + 背景弧线/星点"组织，避免堆碎屑。
/// - 动画 6 秒一个循环，幅度尽量小，呼吸感优先。
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
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
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

  // 主体描边色：在 accent 上加一层深沉但不死黑的"墨色"，呼应整套 #1B1B1F。
  static const _ink = Color(0xFF1F2024);
  static const _paper = Color(0xFFFFFAF5);

  @override
  void paint(Canvas canvas, Size size) {
    _paintBackdrop(canvas, size);
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
  // 共用背景：单层 accent radial glow + 3 颗静态星点。
  // 不再画太多东西，把视觉分量留给主体。
  // --------------------------------------------------------
  void _paintBackdrop(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final c = Offset(w * 0.5, h * 0.52);

    canvas.drawCircle(
      c,
      w * 0.46,
      Paint()
        ..shader = RadialGradient(
          colors: [
            accent.withValues(alpha: 0.36),
            accent.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 1.0],
        ).createShader(Rect.fromCircle(center: c, radius: w * 0.46)),
    );

    // 几颗 sparkle 装饰。位置固定，每颗按不同相位呼吸亮度。
    const sparkles = [
      Offset(0.18, 0.20),
      Offset(0.84, 0.16),
      Offset(0.86, 0.78),
      Offset(0.14, 0.82),
    ];
    for (var i = 0; i < sparkles.length; i++) {
      final pos = Offset(sparkles[i].dx * w, sparkles[i].dy * h);
      final blink = (math.sin((t + i * 0.25) * math.pi * 2) + 1) / 2;
      _drawSparkle(canvas, pos, 5 + blink * 3, accent.withValues(alpha: 0.55));
    }
  }

  void _drawSparkle(Canvas canvas, Offset center, double size, Color color) {
    final p = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(center.dx - size, center.dy),
      Offset(center.dx + size, center.dy),
      p,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - size),
      Offset(center.dx, center.dy + size),
      p,
    );
  }

  // --------------------------------------------------------
  // 1) Welcome —— phone 主屏 + 4 服务 tile + 上下浮动两枚 chip
  // --------------------------------------------------------
  void _paintWelcome(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final c = Offset(w * 0.5, h * 0.5);

    // 主体 phone
    final phoneRect = Rect.fromCenter(
      center: c.translate(0, _bob(0.0) * 3),
      width: w * 0.44,
      height: h * 0.62,
    );
    final phoneRRect =
        RRect.fromRectAndRadius(phoneRect, Radius.circular(w * 0.08));

    _drawSoftShadow(canvas, phoneRect.inflate(2), w * 0.08);

    // 机身：深墨色 + 顶部高光线
    canvas.drawRRect(phoneRRect, Paint()..color = _ink);
    canvas.drawRRect(
      phoneRRect.deflate(1.2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.10),
    );

    // 屏幕：暖白渐变
    final screenRect = phoneRect.deflate(w * 0.022);
    final screenRRect =
        RRect.fromRectAndRadius(screenRect, Radius.circular(w * 0.058));
    canvas.drawRRect(
      screenRRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _paper,
            accent.withValues(alpha: 0.06),
          ],
        ).createShader(screenRect),
    );

    // 状态栏（dynamic island）
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(screenRect.center.dx, screenRect.top + w * 0.034),
          width: w * 0.10,
          height: w * 0.022,
        ),
        Radius.circular(w * 0.014),
      ),
      Paint()..color = _ink,
    );

    // 顶部欢迎条（账户卡）
    final welcomeRect = Rect.fromLTWH(
      screenRect.left + w * 0.024,
      screenRect.top + w * 0.075,
      screenRect.width - w * 0.048,
      h * 0.07,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(welcomeRect, Radius.circular(w * 0.022)),
      Paint()..color = accent.withValues(alpha: 0.18),
    );
    // 头像
    canvas.drawCircle(
      Offset(welcomeRect.left + w * 0.04, welcomeRect.center.dy),
      w * 0.022,
      Paint()..color = accent,
    );
    // 两条文字线
    for (var i = 0; i < 2; i++) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            welcomeRect.left + w * 0.085,
            welcomeRect.top + w * 0.022 + i * w * 0.022,
            welcomeRect.width * (0.62 - i * 0.22),
            w * 0.012,
          ),
          Radius.circular(w * 0.006),
        ),
        Paint()..color = accent.withValues(alpha: 0.55 - i * 0.18),
      );
    }

    // 4 张服务 tile（2×2）
    final serviceColors = const [
      Color(0xFF5C8DEF),
      Color(0xFF4FB07A),
      Color(0xFFE8A94C),
      Color(0xFFAA77E0),
    ];
    final tileSize = (welcomeRect.width - w * 0.024) / 2;
    final tilesTop = welcomeRect.bottom + w * 0.026;
    for (var i = 0; i < 4; i++) {
      final col = i % 2;
      final row = i ~/ 2;
      final origin = Offset(
        welcomeRect.left + col * (tileSize + w * 0.024),
        tilesTop + row * (tileSize + w * 0.024),
      );
      final rect = Rect.fromLTWH(origin.dx, origin.dy, tileSize, tileSize);
      final scale = 1 + _bob(0.15 + i * 0.12) * 0.012;
      final scaled = Rect.fromCenter(
        center: rect.center,
        width: rect.width * scale,
        height: rect.height * scale,
      );
      // tile 渐变：主色 → 主色 90%，加内边亮线
      canvas.drawRRect(
        RRect.fromRectAndRadius(scaled, Radius.circular(w * 0.026)),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              serviceColors[i],
              Color.lerp(serviceColors[i], _ink, 0.18)!,
            ],
          ).createShader(scaled),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          scaled.deflate(0.8),
          Radius.circular(w * 0.024),
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = Colors.white.withValues(alpha: 0.25),
      );
      _paintTileGlyph(canvas, scaled, i);
    }

    // home 指示条
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(screenRect.center.dx, screenRect.bottom - w * 0.024),
          width: screenRect.width * 0.35,
          height: w * 0.008,
        ),
        Radius.circular(w * 0.004),
      ),
      Paint()..color = _ink.withValues(alpha: 0.55),
    );

    // 上下两枚漂浮 chip：呼吸 + 微旋转
    _drawFloatingChip(
      canvas,
      Offset(w * 0.18, h * 0.30 + _bob(0.0) * 5),
      const Color(0xFF5C8DEF),
      glyph: _ChipGlyph.calendar,
      angle: -0.10 + _bob(0.4) * 0.05,
    );
    _drawFloatingChip(
      canvas,
      Offset(w * 0.82, h * 0.72 + _bob(0.5) * 5),
      const Color(0xFFE8A94C),
      glyph: _ChipGlyph.bell,
      angle: 0.12 + _bob(0.1) * 0.05,
    );
  }

  void _paintTileGlyph(Canvas canvas, Rect rect, int kind) {
    final glyph = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = Colors.white;
    final c = rect.center;
    final s = rect.width;
    switch (kind) {
      case 0: // 日历
        final body = Rect.fromCenter(center: c, width: s * 0.5, height: s * 0.45);
        canvas.drawRRect(
          RRect.fromRectAndRadius(body, Radius.circular(s * 0.06)),
          glyph,
        );
        canvas.drawLine(
          Offset(body.left, body.top + s * 0.13),
          Offset(body.right, body.top + s * 0.13),
          glyph,
        );
        // 两根 hanger
        canvas.drawLine(
          Offset(body.left + s * 0.10, body.top - s * 0.06),
          Offset(body.left + s * 0.10, body.top + s * 0.04),
          glyph,
        );
        canvas.drawLine(
          Offset(body.right - s * 0.10, body.top - s * 0.06),
          Offset(body.right - s * 0.10, body.top + s * 0.04),
          glyph,
        );
        // 小点
        canvas.drawCircle(
          Offset(c.dx, c.dy + s * 0.05),
          s * 0.025,
          fill,
        );
        break;
      case 1: // 哑铃
        final barY = c.dy;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset(c.dx, barY),
              width: s * 0.42,
              height: s * 0.06,
            ),
            Radius.circular(s * 0.02),
          ),
          fill,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset(c.dx - s * 0.24, barY),
              width: s * 0.10,
              height: s * 0.20,
            ),
            Radius.circular(s * 0.024),
          ),
          fill,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset(c.dx + s * 0.24, barY),
              width: s * 0.10,
              height: s * 0.20,
            ),
            Radius.circular(s * 0.024),
          ),
          fill,
        );
        break;
      case 2: // A+
        final tp = TextPainter(
          text: TextSpan(
            text: 'A+',
            style: TextStyle(
              color: Colors.white,
              fontSize: s * 0.42,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
        break;
      case 3: // 铃铛
        final bell = Path()
          ..moveTo(c.dx - s * 0.18, c.dy + s * 0.10)
          ..quadraticBezierTo(
            c.dx - s * 0.18,
            c.dy - s * 0.20,
            c.dx,
            c.dy - s * 0.22,
          )
          ..quadraticBezierTo(
            c.dx + s * 0.18,
            c.dy - s * 0.20,
            c.dx + s * 0.18,
            c.dy + s * 0.10,
          )
          ..close();
        canvas.drawPath(bell, fill);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset(c.dx, c.dy + s * 0.13),
              width: s * 0.42,
              height: s * 0.05,
            ),
            Radius.circular(s * 0.02),
          ),
          fill,
        );
        canvas.drawCircle(
          Offset(c.dx, c.dy + s * 0.22),
          s * 0.04,
          fill,
        );
        break;
    }
  }

  void _drawFloatingChip(
    Canvas canvas,
    Offset center,
    Color color, {
    required _ChipGlyph glyph,
    required double angle,
  }) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    final size = 56.0;
    final rect = Rect.fromCenter(center: Offset.zero, width: size, height: size);
    // 阴影
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.translate(0, 4), const Radius.circular(16)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.10)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    // 主体渐变
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(16)),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color,
            Color.lerp(color, _ink, 0.20)!,
          ],
        ).createShader(rect),
    );
    // 内描边亮线
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(1), const Radius.circular(15)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.30),
    );
    // glyph
    final p = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final s = size;
    switch (glyph) {
      case _ChipGlyph.calendar:
        final body = Rect.fromCenter(
          center: Offset.zero,
          width: s * 0.50,
          height: s * 0.46,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(body, Radius.circular(s * 0.08)),
          p,
        );
        canvas.drawLine(
          Offset(body.left, body.top + s * 0.14),
          Offset(body.right, body.top + s * 0.14),
          p,
        );
        break;
      case _ChipGlyph.bell:
        final bell = Path()
          ..moveTo(-s * 0.18, s * 0.10)
          ..quadraticBezierTo(-s * 0.18, -s * 0.18, 0, -s * 0.20)
          ..quadraticBezierTo(s * 0.18, -s * 0.18, s * 0.18, s * 0.10)
          ..close();
        canvas.drawPath(bell, p);
        canvas.drawLine(Offset(-s * 0.20, s * 0.14),
            Offset(s * 0.20, s * 0.14), p);
        break;
    }
    canvas.restore();
  }

  // --------------------------------------------------------
  // 2) Login —— 学生证 + 钥匙 + 完成对勾
  // --------------------------------------------------------
  void _paintLogin(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final c = Offset(w * 0.5, h * 0.52);

    // 学生证主体（横）
    final cardRect = Rect.fromCenter(
      center: c.translate(0, _bob(0.0) * 2),
      width: w * 0.66,
      height: h * 0.42,
    );
    final cardRRect =
        RRect.fromRectAndRadius(cardRect, Radius.circular(w * 0.05));
    _drawSoftShadow(canvas, cardRect.inflate(2), w * 0.05);

    // 主体白色卡片，左侧 accent 色 strip
    canvas.drawRRect(cardRRect, Paint()..color = _paper);
    canvas.drawRRect(
      cardRRect.deflate(0.6),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = _ink.withValues(alpha: 0.06),
    );
    // 左侧 strip
    canvas.save();
    canvas.clipRRect(cardRRect);
    canvas.drawRect(
      Rect.fromLTWH(cardRect.left, cardRect.top, w * 0.16, cardRect.height),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [accent, Color.lerp(accent, _ink, 0.30)!],
        ).createShader(
          Rect.fromLTWH(cardRect.left, cardRect.top, w * 0.16, cardRect.height),
        ),
    );
    canvas.restore();

    // strip 上的小 logo（圆角方）
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(cardRect.left + w * 0.08, cardRect.center.dy),
          width: w * 0.08,
          height: w * 0.08,
        ),
        Radius.circular(w * 0.018),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.92),
    );
    // logo 内一个 SSO 字符
    final logo = TextPainter(
      text: TextSpan(
        text: '邑',
        style: TextStyle(
          color: accent,
          fontSize: w * 0.05,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    logo.paint(
      canvas,
      Offset(cardRect.left + w * 0.08, cardRect.center.dy) -
          Offset(logo.width / 2, logo.height / 2),
    );

    // 右侧文字行
    final textLeft = cardRect.left + w * 0.20;
    final textTop = cardRect.top + h * 0.06;
    // 名字（粗）
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(textLeft, textTop, w * 0.30, h * 0.025),
        Radius.circular(h * 0.012),
      ),
      Paint()..color = _ink.withValues(alpha: 0.78),
    );
    // 学号
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(textLeft, textTop + h * 0.05, w * 0.36, h * 0.014),
        Radius.circular(h * 0.007),
      ),
      Paint()..color = _ink.withValues(alpha: 0.30),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(textLeft, textTop + h * 0.08, w * 0.28, h * 0.014),
        Radius.circular(h * 0.007),
      ),
      Paint()..color = _ink.withValues(alpha: 0.20),
    );
    // 条形码
    final barTop = cardRect.bottom - h * 0.07;
    for (var i = 0; i < 14; i++) {
      final wide = i % 3 == 0 ? 1.8 : 1.0;
      canvas.drawRect(
        Rect.fromLTWH(
          textLeft + i * w * 0.018,
          barTop,
          wide,
          h * 0.04,
        ),
        Paint()..color = _ink,
      );
    }

    // 钥匙：从右上插入卡片，锁孔在卡片右下
    final keyholeOffset = Offset(cardRect.right - w * 0.07, cardRect.bottom - w * 0.05);
    canvas.drawCircle(
      keyholeOffset,
      w * 0.018,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = _ink,
    );
    canvas.drawLine(
      Offset(keyholeOffset.dx, keyholeOffset.dy + w * 0.012),
      Offset(keyholeOffset.dx, keyholeOffset.dy + w * 0.04),
      Paint()
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = _ink,
    );

    // 钥匙旋转（随 t 摆动 ±20°）
    final keyAngle = math.sin(t * math.pi * 2) * 0.35;
    canvas.save();
    canvas.translate(keyholeOffset.dx, keyholeOffset.dy);
    canvas.rotate(keyAngle);
    _drawKey(canvas, w);
    canvas.restore();

    // 顶部右侧的对勾 badge（弹出感）
    final badgePop = (math.sin(t * math.pi * 2 - 1.0) * 0.5 + 0.5);
    final badgeCenter =
        Offset(cardRect.right - w * 0.04, cardRect.top - w * 0.02);
    final r = w * 0.05 * (0.85 + badgePop * 0.15);
    canvas.drawCircle(
      badgeCenter,
      r + 4,
      Paint()
        ..color = const Color(0xFF4FB07A).withValues(alpha: 0.18 * badgePop),
    );
    canvas.drawCircle(
      badgeCenter,
      r,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: const [Color(0xFF6CC68F), Color(0xFF4FB07A)],
        ).createShader(Rect.fromCircle(center: badgeCenter, radius: r)),
    );
    final tick = Path()
      ..moveTo(badgeCenter.dx - r * 0.40, badgeCenter.dy + r * 0.02)
      ..lineTo(badgeCenter.dx - r * 0.08, badgeCenter.dy + r * 0.32)
      ..lineTo(badgeCenter.dx + r * 0.42, badgeCenter.dy - r * 0.30);
    canvas.drawPath(
      tick,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // 底部一根光束，呼应 "登一次处处都通"
    final beam = Paint()
      ..shader = LinearGradient(
        colors: [
          accent.withValues(alpha: 0.0),
          accent.withValues(alpha: 0.45),
          accent.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, 6));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(c.dx, cardRect.bottom + w * 0.08),
          width: w * 0.6,
          height: 4,
        ),
        const Radius.circular(2),
      ),
      beam,
    );
  }

  void _drawKey(Canvas canvas, double w) {
    // 钥匙以原点的小锁孔为参考；钥匙整体水平向右伸。
    // 钥匙长度 ~ w*0.22
    final keyColor = const Color(0xFFF5C45B);
    final keyDeep = Color.lerp(keyColor, _ink, 0.30)!;

    // 钥匙杆
    final shaft = Rect.fromLTWH(0, -w * 0.012, w * 0.16, w * 0.024);
    canvas.drawRRect(
      RRect.fromRectAndRadius(shaft, Radius.circular(w * 0.012)),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [keyColor, keyDeep],
        ).createShader(shaft),
    );
    // 齿
    canvas.drawRect(
      Rect.fromLTWH(w * 0.10, w * 0.012, w * 0.018, w * 0.024),
      Paint()..color = keyDeep,
    );
    canvas.drawRect(
      Rect.fromLTWH(w * 0.13, w * 0.012, w * 0.012, w * 0.018),
      Paint()..color = keyDeep,
    );
    // 钥匙环
    canvas.drawCircle(
      Offset(w * 0.18, 0),
      w * 0.038,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.018
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [keyColor, keyDeep],
        ).createShader(
          Rect.fromCircle(center: Offset(w * 0.18, 0), radius: w * 0.038),
        ),
    );
    // 钥匙环高光
    canvas.drawArc(
      Rect.fromCircle(center: Offset(w * 0.18, 0), radius: w * 0.030),
      -math.pi * 0.85,
      math.pi * 0.5,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = Colors.white.withValues(alpha: 0.55),
    );
  }

  // --------------------------------------------------------
  // 3) Privacy —— 真盾 + 中央锁 + 两枚保险插销
  // --------------------------------------------------------
  void _paintPrivacy(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final c = Offset(w * 0.5, h * 0.5);

    // 盾形主体（用真正的盾轮廓：肩部扁平、底部尖收）
    final shieldHalfW = w * 0.30;
    final shieldH = h * 0.62;
    final shieldPath = _shieldPath(c.translate(0, _bob(0.0) * 2),
        shieldHalfW, shieldH * 0.5);

    _drawSoftShadow(canvas, shieldPath.getBounds().inflate(4), w * 0.06);

    // 盾内渐变填色
    canvas.drawPath(
      shieldPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(accent, Colors.white, 0.10)!,
            Color.lerp(accent, _ink, 0.22)!,
          ],
        ).createShader(shieldPath.getBounds()),
    );

    // 内圈描边（金属纹）
    final innerShield =
        _shieldPath(c.translate(0, _bob(0.0) * 2), shieldHalfW * 0.86,
            shieldH * 0.43);
    canvas.drawPath(
      innerShield,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.white.withValues(alpha: 0.45),
    );

    // 顶部小高光
    final highlightPath = Path()
      ..moveTo(c.dx - shieldHalfW * 0.62, c.dy - shieldH * 0.40)
      ..quadraticBezierTo(
        c.dx,
        c.dy - shieldH * 0.50,
        c.dx + shieldHalfW * 0.62,
        c.dy - shieldH * 0.40,
      );
    canvas.drawPath(
      highlightPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.50),
    );

    // 中央锁
    final lockCenter = c.translate(0, _bob(0.0) * 2 + h * 0.02);
    final bodyRect = Rect.fromCenter(
      center: lockCenter.translate(0, h * 0.04),
      width: w * 0.20,
      height: h * 0.16,
    );
    // 锁体阴影
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        bodyRect.translate(0, 4),
        Radius.circular(w * 0.024),
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    // 锁体
    canvas.drawRRect(
      RRect.fromRectAndRadius(bodyRect, Radius.circular(w * 0.024)),
      Paint()..color = _paper,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        bodyRect.deflate(1),
        Radius.circular(w * 0.022),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = _ink.withValues(alpha: 0.10),
    );
    // 锁孔（圆 + 倒三角）
    final keyholeC = bodyRect.center.translate(0, -h * 0.005);
    canvas.drawCircle(keyholeC, w * 0.018, Paint()..color = _ink);
    canvas.drawPath(
      Path()
        ..moveTo(keyholeC.dx - w * 0.012, keyholeC.dy + w * 0.004)
        ..lineTo(keyholeC.dx + w * 0.012, keyholeC.dy + w * 0.004)
        ..lineTo(keyholeC.dx, keyholeC.dy + w * 0.045)
        ..close(),
      Paint()..color = _ink,
    );

    // 锁环
    final shackleRect = Rect.fromCenter(
      center: bodyRect.topCenter.translate(0, -w * 0.018),
      width: bodyRect.width * 0.66,
      height: w * 0.10,
    );
    canvas.drawArc(
      shackleRect,
      math.pi,
      math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.020
        ..strokeCap = StrokeCap.round
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white.withValues(alpha: 0.95), _paper],
        ).createShader(shackleRect),
    );

    // 盾两侧的"保险插销"装饰：左右各一根带圆头的小杆
    for (var side = -1; side <= 1; side += 2) {
      final orbit = _bob(side > 0 ? 0.3 : 0.7) * 3;
      final base = Offset(
        c.dx + side * shieldHalfW * 1.10,
        c.dy + orbit,
      );
      final inner = Offset(
        c.dx + side * shieldHalfW * 0.78,
        c.dy + orbit,
      );
      canvas.drawLine(
        base,
        inner,
        Paint()
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..color = accent.withValues(alpha: 0.55),
      );
      canvas.drawCircle(
        base,
        5.5,
        Paint()..color = accent.withValues(alpha: 0.85),
      );
      canvas.drawCircle(
        base,
        2.4,
        Paint()..color = Colors.white.withValues(alpha: 0.95),
      );
    }

    // 底部的"对勾"小章
    final stamp = Offset(c.dx, c.dy + shieldH * 0.40);
    canvas.drawCircle(
      stamp,
      w * 0.028,
      Paint()..color = Colors.white.withValues(alpha: 0.18),
    );
    final stampTick = Path()
      ..moveTo(stamp.dx - w * 0.014, stamp.dy + w * 0.001)
      ..lineTo(stamp.dx - w * 0.003, stamp.dy + w * 0.012)
      ..lineTo(stamp.dx + w * 0.016, stamp.dy - w * 0.012);
    canvas.drawPath(
      stampTick,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  Path _shieldPath(Offset center, double halfWidth, double halfHeight) {
    // 真正的盾形：肩部宽，向中段微收，底部一个柔和的尖。
    final p = Path();
    final top = center.dy - halfHeight;
    final bottom = center.dy + halfHeight * 1.05;
    p.moveTo(center.dx, top);
    // 右肩
    p.cubicTo(
      center.dx + halfWidth * 0.55, top,
      center.dx + halfWidth, top + halfHeight * 0.10,
      center.dx + halfWidth, top + halfHeight * 0.30,
    );
    // 右侧缓收
    p.cubicTo(
      center.dx + halfWidth, center.dy + halfHeight * 0.55,
      center.dx + halfWidth * 0.85, bottom - halfHeight * 0.20,
      center.dx + halfWidth * 0.30, bottom - halfHeight * 0.05,
    );
    // 底尖
    p.quadraticBezierTo(
      center.dx, bottom + halfHeight * 0.05,
      center.dx - halfWidth * 0.30, bottom - halfHeight * 0.05,
    );
    // 左侧缓收
    p.cubicTo(
      center.dx - halfWidth * 0.85, bottom - halfHeight * 0.20,
      center.dx - halfWidth, center.dy + halfHeight * 0.55,
      center.dx - halfWidth, top + halfHeight * 0.30,
    );
    // 左肩
    p.cubicTo(
      center.dx - halfWidth, top + halfHeight * 0.10,
      center.dx - halfWidth * 0.55, top,
      center.dx, top,
    );
    p.close();
    return p;
  }

  // --------------------------------------------------------
  // 4) Learning —— 翻开的书 + 学士帽 + 一个像素猫 + 漂浮代码
  // --------------------------------------------------------
  void _paintLearning(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final c = Offset(w * 0.5, h * 0.5);

    // 翻开的书
    final bookCenter = Offset(c.dx, c.dy + h * 0.18 + _bob(0.0) * 2);
    final bookHalfW = w * 0.34;
    final bookH = h * 0.30;

    // 阴影
    _drawSoftShadow(
      canvas,
      Rect.fromCenter(
        center: bookCenter,
        width: bookHalfW * 2.1,
        height: bookH * 1.05,
      ),
      w * 0.04,
    );

    // 书脊（最深底色）+ 内侧暗影
    final spineRect = Rect.fromCenter(
      center: bookCenter,
      width: bookHalfW * 2.05,
      height: bookH * 1.05,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(spineRect, Radius.circular(w * 0.024)),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(accent, _ink, 0.45)!,
            Color.lerp(accent, _ink, 0.15)!,
          ],
        ).createShader(spineRect),
    );

    // 左右两页
    for (var side = -1; side <= 1; side += 2) {
      final pageRect = Rect.fromCenter(
        center: Offset(bookCenter.dx + side * bookHalfW * 0.51, bookCenter.dy),
        width: bookHalfW * 0.97,
        height: bookH * 0.94,
      );
      // 翻页阴影：靠近书脊一侧颜色更深
      canvas.drawRRect(
        RRect.fromRectAndRadius(pageRect, Radius.circular(w * 0.014)),
        Paint()
          ..shader = LinearGradient(
            begin: side > 0 ? Alignment.centerLeft : Alignment.centerRight,
            end: side > 0 ? Alignment.centerRight : Alignment.centerLeft,
            colors: [
              const Color(0xFFEFE8DA),
              _paper,
            ],
            stops: const [0.0, 0.35],
          ).createShader(pageRect),
      );
      // 标题条 (accent)
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            pageRect.left + w * 0.03,
            pageRect.top + w * 0.025,
            pageRect.width * 0.45,
            w * 0.013,
          ),
          Radius.circular(w * 0.008),
        ),
        Paint()..color = accent,
      );
      // 文字行
      for (var i = 0; i < 5; i++) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              pageRect.left + w * 0.03,
              pageRect.top + w * 0.06 + i * w * 0.022,
              pageRect.width * (0.78 - (i % 3) * 0.10),
              w * 0.008,
            ),
            Radius.circular(w * 0.004),
          ),
          Paint()..color = _ink.withValues(alpha: 0.20 - (i % 3) * 0.02),
        );
      }
    }
    // 中央分隔线
    canvas.drawLine(
      Offset(bookCenter.dx, bookCenter.dy - bookH * 0.42),
      Offset(bookCenter.dx, bookCenter.dy + bookH * 0.42),
      Paint()
        ..color = Color.lerp(accent, _ink, 0.55)!.withValues(alpha: 0.55)
        ..strokeWidth = 1.4,
    );

    // 学士帽（书的上方）
    final capCenter = Offset(c.dx, c.dy - h * 0.04 + _bob(0.2) * 3);
    _drawCap(canvas, capCenter, w);

    // 帽穗动画：跟着 t 摆
    final tasselRoot = Offset(capCenter.dx + w * 0.10, capCenter.dy);
    final swing = math.sin(t * math.pi * 2) * 0.45;
    final tEnd = tasselRoot.translate(
      math.sin(swing) * w * 0.05,
      math.cos(swing) * w * 0.10,
    );
    canvas.drawLine(
      tasselRoot,
      tEnd,
      Paint()
        ..color = const Color(0xFFE8A94C)
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round,
    );
    // 流苏
    for (var i = 0; i < 5; i++) {
      final off = Offset(
        tEnd.dx + (i - 2) * 1.2,
        tEnd.dy + 4 + i % 2 * 2,
      );
      canvas.drawLine(
        tEnd,
        off,
        Paint()
          ..color = const Color(0xFFE8A94C)
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round,
      );
    }
    canvas.drawCircle(
      tEnd,
      w * 0.014,
      Paint()..color = const Color(0xFFE8A94C),
    );

    // 左上角：像素猫小图（呼应品牌 logo）
    _drawPixelCat(canvas, Offset(w * 0.20, h * 0.22 + _bob(0.4) * 3), w * 0.10);

    // 右上角：代码符号 </>
    _drawCodeBracket(
      canvas,
      Offset(w * 0.82, h * 0.22 + _bob(0.6) * 3),
      const Color(0xFF5C8DEF),
      w * 0.06,
    );
  }

  void _drawCap(Canvas canvas, Offset center, double w) {
    // 帽顶（菱形板）
    final top = Path()
      ..moveTo(center.dx, center.dy - w * 0.10)
      ..lineTo(center.dx + w * 0.18, center.dy)
      ..lineTo(center.dx, center.dy + w * 0.06)
      ..lineTo(center.dx - w * 0.18, center.dy)
      ..close();
    canvas.drawPath(
      top,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_ink, const Color(0xFF34343A)],
        ).createShader(top.getBounds()),
    );
    // 顶板高光线
    canvas.drawLine(
      Offset(center.dx - w * 0.12, center.dy - w * 0.012),
      Offset(center.dx, center.dy - w * 0.07),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.20)
        ..strokeWidth = 1.4,
    );
    // 帽座
    final base = Path()
      ..moveTo(center.dx - w * 0.10, center.dy + w * 0.02)
      ..lineTo(center.dx - w * 0.10, center.dy + w * 0.06)
      ..quadraticBezierTo(
        center.dx,
        center.dy + w * 0.10,
        center.dx + w * 0.10,
        center.dy + w * 0.06,
      )
      ..lineTo(center.dx + w * 0.10, center.dy + w * 0.02)
      ..close();
    canvas.drawPath(base, Paint()..color = const Color(0xFF24242A));
    // 中央纽扣
    canvas.drawCircle(
      center,
      w * 0.012,
      Paint()..color = const Color(0xFFE8A94C),
    );
  }

  void _drawPixelCat(Canvas canvas, Offset center, double size) {
    // 极简的像素猫头：圆角矩形脸 + 两个三角耳 + 两眼一鼻
    final faceRect = Rect.fromCenter(
      center: center,
      width: size * 1.0,
      height: size * 0.95,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(faceRect, Radius.circular(size * 0.30)),
      Paint()..color = _paper,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(faceRect, Radius.circular(size * 0.30)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = _ink,
    );
    // 耳朵
    final earL = Path()
      ..moveTo(faceRect.left + size * 0.05, faceRect.top + size * 0.04)
      ..lineTo(faceRect.left + size * 0.20, faceRect.top - size * 0.18)
      ..lineTo(faceRect.left + size * 0.34, faceRect.top + size * 0.10)
      ..close();
    final earR = Path()
      ..moveTo(faceRect.right - size * 0.05, faceRect.top + size * 0.04)
      ..lineTo(faceRect.right - size * 0.20, faceRect.top - size * 0.18)
      ..lineTo(faceRect.right - size * 0.34, faceRect.top + size * 0.10)
      ..close();
    canvas.drawPath(earL, Paint()..color = _paper);
    canvas.drawPath(earR, Paint()..color = _paper);
    canvas.drawPath(
      earL,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = _ink,
    );
    canvas.drawPath(
      earR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = _ink,
    );
    // 眼
    canvas.drawCircle(
      Offset(faceRect.center.dx - size * 0.18, faceRect.center.dy - size * 0.04),
      size * 0.06,
      Paint()..color = _ink,
    );
    canvas.drawCircle(
      Offset(faceRect.center.dx + size * 0.18, faceRect.center.dy - size * 0.04),
      size * 0.06,
      Paint()..color = _ink,
    );
    // 鼻子
    final nose = Path()
      ..moveTo(faceRect.center.dx - size * 0.05, faceRect.center.dy + size * 0.10)
      ..lineTo(faceRect.center.dx + size * 0.05, faceRect.center.dy + size * 0.10)
      ..lineTo(faceRect.center.dx, faceRect.center.dy + size * 0.18)
      ..close();
    canvas.drawPath(nose, Paint()..color = accent);
  }

  void _drawCodeBracket(Canvas canvas, Offset center, Color color, double size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final s = size;
    final path = Path()
      // <
      ..moveTo(center.dx - s * 0.55, center.dy - s * 0.55)
      ..lineTo(center.dx - s * 1.05, center.dy)
      ..lineTo(center.dx - s * 0.55, center.dy + s * 0.55)
      // /
      ..moveTo(center.dx - s * 0.20, center.dy + s * 0.55)
      ..lineTo(center.dx + s * 0.20, center.dy - s * 0.55)
      // >
      ..moveTo(center.dx + s * 0.55, center.dy - s * 0.55)
      ..lineTo(center.dx + s * 1.05, center.dy)
      ..lineTo(center.dx + s * 0.55, center.dy + s * 0.55);
    canvas.drawPath(path, p);
  }

  // --------------------------------------------------------
  // 工具
  // --------------------------------------------------------
  double _bob(double phase) => math.sin((t + phase) * math.pi * 2);

  void _drawSoftShadow(Canvas canvas, Rect rect, double radius) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.translate(0, 8), Radius.circular(radius)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.12)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
  }

  @override
  bool shouldRepaint(covariant _IllustrationPainter old) =>
      old.t != t || old.kind != kind || old.accent != accent;
}

enum _ChipGlyph { calendar, bell }
