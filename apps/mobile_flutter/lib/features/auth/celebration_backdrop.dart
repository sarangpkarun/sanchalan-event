import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Soft celebration scenery for the welcome screen: a marigold garland and
/// bunting across the top, balloons at the sides, and a glow of diyas and
/// confetti near the bottom. Purely decorative.
class CelebrationBackdrop extends StatelessWidget {
  const CelebrationBackdrop({super.key});

  @override
  Widget build(BuildContext context) => const ExcludeSemantics(
        child: SizedBox.expand(child: CustomPaint(painter: _BackdropPainter())),
      );
}

class _BackdropPainter extends CustomPainter {
  const _BackdropPainter();

  static const _marigold = [Color(0xFFF2A81D), Color(0xFFE0780C), Color(0xFFF7C948)];
  static const _flagColors = [AppColors.maroon, AppColors.gold, AppColors.primary, Color(0xFFE8A0A8)];

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;

    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFF3E2), AppColors.background, Color(0xFFFFE9D2)],
        ).createShader(Offset.zero & size),
    );

    // Warm glow rising from the bottom, like lamplight.
    canvas.drawCircle(
      Offset(w / 2, h * 1.02),
      w * 0.85,
      Paint()
        ..shader = RadialGradient(colors: [
          AppColors.gold.withValues(alpha: 0.35),
          AppColors.gold.withValues(alpha: 0),
        ]).createShader(Rect.fromCircle(center: Offset(w / 2, h * 1.02), radius: w * 0.85)),
    );

    _garland(canvas, size, y0: 0, sag: h * 0.07);
    _garland(canvas, size, y0: h * 0.03, sag: h * 0.05, scale: 0.75);
    _bunting(canvas, size);

    _balloon(canvas, Offset(w * 0.1, h * 0.62), 26, AppColors.maroon);
    _balloon(canvas, Offset(w * 0.2, h * 0.7), 20, AppColors.gold);
    _balloon(canvas, Offset(w * 0.9, h * 0.58), 28, AppColors.primary);
    _balloon(canvas, Offset(w * 0.8, h * 0.68), 20, const Color(0xFFE8A0A8));

    final rnd = math.Random(7);
    for (var i = 0; i < 46; i++) {
      final p = Offset(rnd.nextDouble() * w, h * (0.22 + rnd.nextDouble() * 0.7));
      final c = _flagColors[i % _flagColors.length].withValues(alpha: 0.5);
      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.rotate(rnd.nextDouble() * math.pi);
      canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(-4, -1.5, 8, 3), const Radius.circular(1.5)),
        Paint()..color = c,
      );
      canvas.restore();
    }

    for (final x in [0.22, 0.5, 0.78]) {
      _diya(canvas, Offset(w * x, h * 0.955), w * (x == 0.5 ? 0.075 : 0.055));
    }
  }

  void _garland(Canvas canvas, Size size, {required double y0, required double sag, double scale = 1}) {
    final w = size.width;
    final path = Path()..moveTo(-10, y0 + 6);
    path.quadraticBezierTo(w / 2, y0 + 6 + sag * 2, w + 10, y0 + 6);
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF3D7A3A).withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    final metrics = path.computeMetrics().first;
    final count = (metrics.length / (15 * scale)).floor();
    for (var i = 0; i <= count; i++) {
      final t = metrics.getTangentForOffset(metrics.length * i / count)!;
      final c = _marigold[i % _marigold.length];
      canvas.drawCircle(t.position, 8 * scale, Paint()..color = c);
      canvas.drawCircle(t.position, 3.2 * scale, Paint()..color = Colors.white.withValues(alpha: 0.35));
    }
  }

  void _bunting(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final y0 = h * 0.075;
    final line = Path()..moveTo(-10, y0);
    line.quadraticBezierTo(w / 2, y0 + h * 0.1, w + 10, y0);
    final m = line.computeMetrics().first;
    const n = 9;
    for (var i = 1; i < n; i++) {
      final t = m.getTangentForOffset(m.length * i / n)!;
      final p = t.position;
      canvas.drawPath(
        Path()
          ..moveTo(p.dx - 11, p.dy)
          ..lineTo(p.dx + 11, p.dy)
          ..lineTo(p.dx, p.dy + 26)
          ..close(),
        Paint()..color = _flagColors[i % _flagColors.length].withValues(alpha: 0.85),
      );
    }
  }

  void _balloon(Canvas canvas, Offset c, double r, Color color) {
    canvas.drawLine(
      c + Offset(0, r * 1.2),
      c + Offset(r * 0.3, r * 3.2),
      Paint()
        ..color = AppColors.outlineStrong.withValues(alpha: 0.5)
        ..strokeWidth = 1.2,
    );
    canvas.drawOval(
      Rect.fromCenter(center: c, width: r * 1.7, height: r * 2.1),
      Paint()..color = color.withValues(alpha: 0.78),
    );
    canvas.drawCircle(c + Offset(-r * 0.3, -r * 0.4), r * 0.2, Paint()..color = Colors.white.withValues(alpha: 0.45));
  }

  void _diya(Canvas canvas, Offset base, double w) {
    final bowl = Path()
      ..moveTo(base.dx - w, base.dy - w * 0.25)
      ..lineTo(base.dx + w, base.dy - w * 0.25)
      ..cubicTo(base.dx + w, base.dy + w * 0.45, base.dx + w * 0.5, base.dy + w * 0.6, base.dx, base.dy + w * 0.6)
      ..cubicTo(base.dx - w * 0.5, base.dy + w * 0.6, base.dx - w, base.dy + w * 0.45, base.dx - w, base.dy - w * 0.25)
      ..close();
    canvas.drawPath(bowl, Paint()..color = AppColors.maroon.withValues(alpha: 0.85));
    final fx = base.dx, fy = base.dy - w * 0.25;
    canvas.drawPath(
      Path()
        ..moveTo(fx, fy - w * 0.95)
        ..cubicTo(fx + w * 0.4, fy - w * 0.45, fx + w * 0.3, fy - w * 0.1, fx, fy)
        ..cubicTo(fx - w * 0.3, fy - w * 0.1, fx - w * 0.4, fy - w * 0.45, fx, fy - w * 0.95)
        ..close(),
      Paint()..color = AppColors.gold,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
