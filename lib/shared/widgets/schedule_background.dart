import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/settings/app_preferences.dart';

class ScheduleBackground extends StatelessWidget {
  const ScheduleBackground({
    super.key,
    required this.style,
    required this.opacity,
    this.borderRadius = BorderRadius.zero,
  });

  final ScheduleBackgroundStyle style;
  final double opacity;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    if (style == ScheduleBackgroundStyle.clean || opacity <= 0) {
      return const SizedBox.expand();
    }

    return IgnorePointer(
      child: ClipRRect(
        borderRadius: borderRadius,
        child: CustomPaint(
          painter: _ScheduleBackgroundPainter(
            style: style,
            opacity: opacity,
            colorScheme: Theme.of(context).colorScheme,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _ScheduleBackgroundPainter extends CustomPainter {
  const _ScheduleBackgroundPainter({
    required this.style,
    required this.opacity,
    required this.colorScheme,
  });

  final ScheduleBackgroundStyle style;
  final double opacity;
  final ColorScheme colorScheme;

  @override
  void paint(Canvas canvas, Size size) {
    final strength = opacity.clamp(0.0, 0.5);
    switch (style) {
      case ScheduleBackgroundStyle.clean:
        return;
      case ScheduleBackgroundStyle.paper:
        _paintPaper(canvas, size, strength);
      case ScheduleBackgroundStyle.doodle:
        _paintDoodle(canvas, size, strength);
      case ScheduleBackgroundStyle.linen:
        _paintLinen(canvas, size, strength);
      case ScheduleBackgroundStyle.aurora:
        _paintAurora(canvas, size, strength);
      case ScheduleBackgroundStyle.graph:
        _paintGraph(canvas, size, strength);
    }
  }

  void _paintPaper(Canvas canvas, Size size, double strength) {
    final warm = Color.lerp(
      colorScheme.surface,
      const Color(0xFFFFE6C8),
      0.42,
    )!;
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = warm.withValues(alpha: strength * 0.72),
    );

    final linePaint = Paint()
      ..color = const Color(0xFF8AB1C7).withValues(alpha: strength * 0.34)
      ..strokeWidth = 1;
    for (var y = 28.0; y < size.height; y += 24) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }

    final marginPaint = Paint()
      ..color = const Color(0xFFD77A7A).withValues(alpha: strength * 0.45)
      ..strokeWidth = 1.4;
    canvas.drawLine(const Offset(36, 0), Offset(36, size.height), marginPaint);

    final dotPaint = Paint()
      ..color = const Color(0xFFB97834).withValues(alpha: strength * 0.18);
    for (var y = 20.0; y < size.height; y += 76) {
      canvas.drawCircle(Offset(18, y), 2.4, dotPaint);
    }
  }

  void _paintDoodle(Canvas canvas, Size size, double strength) {
    final fill = Color.lerp(
      colorScheme.surface,
      const Color(0xFFFFDDE6),
      0.36,
    )!;
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = fill.withValues(alpha: strength * 0.58),
    );

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 2
      ..color = const Color(0xFFE07A8A).withValues(alpha: strength * 0.7);
    _drawSpark(canvas, const Offset(28, 28), 8, stroke);
    _drawSpark(canvas, Offset(size.width - 34, 64), 10, stroke);
    _drawHeart(canvas, Offset(size.width - 44, size.height - 38), 9, stroke);
    _drawWavyLine(canvas, Offset(22, size.height - 42), 48, stroke);

    final teal = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF2F8C72).withValues(alpha: strength * 0.44);
    _drawWavyLine(canvas, const Offset(58, 44), 42, teal);
    _drawSpark(canvas, Offset(size.width - 80, size.height - 68), 6, teal);
  }

  void _paintLinen(Canvas canvas, Size size, double strength) {
    final base = Color.lerp(colorScheme.surface, const Color(0xFFD8C6B0), 0.3)!;
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = base.withValues(alpha: strength * 0.55),
    );

    final vertical = Paint()
      ..color = const Color(0xFF7C6655).withValues(alpha: strength * 0.18)
      ..strokeWidth = 1;
    final horizontal = Paint()
      ..color = Colors.white.withValues(alpha: strength * 0.22)
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 7) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), vertical);
    }
    for (var y = 0.0; y < size.height; y += 5) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), horizontal);
    }
  }

  void _paintAurora(Canvas canvas, Size size, double strength) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFFB8E8E1).withValues(alpha: strength * 0.44),
            const Color(0xFFFFD7A8).withValues(alpha: strength * 0.34),
            const Color(0xFFC7D7FF).withValues(alpha: strength * 0.38),
          ],
        ).createShader(Offset.zero & size),
    );
    _drawGlow(
      canvas,
      Offset(size.width * 0.18, size.height * 0.2),
      size.shortestSide * 0.56,
      const Color(0xFF2F8C72),
      strength,
    );
    _drawGlow(
      canvas,
      Offset(size.width * 0.82, size.height * 0.72),
      size.shortestSide * 0.66,
      const Color(0xFFB97834),
      strength,
    );
  }

  void _paintGraph(Canvas canvas, Size size, double strength) {
    final fill = Color.lerp(
      colorScheme.surface,
      const Color(0xFFCDECE3),
      0.34,
    )!;
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = fill.withValues(alpha: strength * 0.5),
    );

    final major = Paint()
      ..color = const Color(0xFF2F8C72).withValues(alpha: strength * 0.32)
      ..strokeWidth = 1.2;
    final minor = Paint()
      ..color = const Color(0xFF2F8C72).withValues(alpha: strength * 0.16)
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 18) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        x % 72 == 0 ? major : minor,
      );
    }
    for (var y = 0.0; y < size.height; y += 18) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        y % 72 == 0 ? major : minor,
      );
    }
  }

  void _drawGlow(
    Canvas canvas,
    Offset center,
    double radius,
    Color color,
    double strength,
  ) {
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: strength * 0.28),
            color.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  void _drawSpark(Canvas canvas, Offset center, double radius, Paint paint) {
    canvas.drawLine(
      center.translate(-radius, 0),
      center.translate(radius, 0),
      paint,
    );
    canvas.drawLine(
      center.translate(0, -radius),
      center.translate(0, radius),
      paint,
    );
    canvas.drawCircle(center, radius * 0.32, paint);
  }

  void _drawHeart(Canvas canvas, Offset center, double radius, Paint paint) {
    final path = Path();
    for (var i = 0; i <= 48; i++) {
      final t = math.pi * 2 * i / 48;
      final x = 16 * math.pow(math.sin(t), 3).toDouble();
      final y =
          -(13 * math.cos(t) -
              5 * math.cos(2 * t) -
              2 * math.cos(3 * t) -
              math.cos(4 * t));
      final point = center + Offset(x, y) * (radius / 18);
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    canvas.drawPath(path, paint);
  }

  void _drawWavyLine(Canvas canvas, Offset start, double width, Paint paint) {
    final path = Path()..moveTo(start.dx, start.dy);
    for (var i = 1; i <= 12; i++) {
      final x = start.dx + width * i / 12;
      final y = start.dy + math.sin(i * math.pi / 2) * 4;
      path.lineTo(x, y);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ScheduleBackgroundPainter oldDelegate) {
    return oldDelegate.style != style ||
        oldDelegate.opacity != opacity ||
        oldDelegate.colorScheme != colorScheme;
  }
}
