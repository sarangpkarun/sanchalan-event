import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

/// SetzO symbol with an optional wordmark. Drawn in code so it needs no asset.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 72, this.wordmark = false, this.wordmarkColor});

  final double size;
  final bool wordmark;
  final Color? wordmarkColor;

  @override
  Widget build(BuildContext context) {
    final mark = SizedBox.square(
      dimension: size,
      child: const CustomPaint(painter: _SymbolPainter()),
    );
    return Semantics(
      label: 'SetzO',
      image: true,
      child: ExcludeSemantics(
        child: wordmark
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  mark,
                  SizedBox(height: size * 0.18),
                  Text(
                    'SetzO',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontFamily: AppFonts.display,
                          color: wordmarkColor ?? AppColors.maroon,
                          fontSize: size * 0.42,
                          height: 1.1,
                        ),
                  ),
                ],
              )
            : mark,
      ),
    );
  }
}

/// The SetzO symbol: a bold Z (a plan taking shape, step by step) with a gold
/// spark at its shoulder, the moment the celebration begins.
class _SymbolPainter extends CustomPainter {
  const _SymbolPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 100;
    canvas.save();
    canvas.scale(s);

    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, 100, 100), const Radius.circular(28)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.maroon],
        ).createShader(const Rect.fromLTWH(0, 0, 100, 100)),
    );

    // The Z
    final z = Path()
      ..moveTo(28, 32)
      ..lineTo(68, 32)
      ..lineTo(30, 68)
      ..lineTo(72, 68);
    canvas.drawPath(
      z,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 11
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Spark: a four-point star above the top bar's end.
    const c = Offset(76, 22);
    const r = 11.0, w = 2.6;
    final star = Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx + w, c.dy - w, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx + w, c.dy + w, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx - w, c.dy + w, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx - w, c.dy - w, c.dx, c.dy - r)
      ..close();
    canvas.drawPath(star, Paint()..color = AppColors.gold);
    canvas.drawCircle(const Offset(22, 76), 3.2, Paint()..color = AppColors.goldContainer);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
