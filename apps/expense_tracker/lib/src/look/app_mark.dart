import 'package:flutter/widgets.dart';

/// The app icon drawn in place: three rising bars and a growth arrow on
/// misty blue, the same shapes as `tool/app_icon.svg` (its visible 300
/// units).
class AppMark extends StatelessWidget {
  const AppMark({super.key, this.size = 96});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: const CustomPaint(painter: _MarkPainter()),
  );
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 300);
    const square = Rect.fromLTWH(0, 0, 300, 300);
    canvas.drawRRect(
      RRect.fromRectAndRadius(square, const Radius.circular(66)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment(-0.2, 1),
          colors: [Color(0xFF4A7E92), Color(0xFF2E5A6C)],
        ).createShader(square),
    );
    // From the drawing's 432-unit canvas, as the SVG places the artwork.
    canvas
      ..translate(-66, -66)
      ..translate(216, 222)
      ..scale(0.9)
      ..translate(-216, -214);
    for (final (left, top, color) in const [
      (126.0, 246.0, Color(0xFFCAD6D8)),
      (194.0, 208.0, Color(0xFFF3F4F1)),
      (262.0, 168.0, Color(0xFFC9A34A)),
    ]) {
      canvas.drawRRect(
        RRect.fromLTRBR(left, top, left + 44, 310, const Radius.circular(22)),
        Paint()..color = color,
      );
    }
    final line = Paint()
      ..color = const Color(0xFFF3F4F1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 15
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas
      ..drawPath(
        Path()
          ..moveTo(118, 206)
          ..lineTo(182, 160)
          ..lineTo(224, 182)
          ..lineTo(292, 118),
        line,
      )
      ..drawPath(
        Path()
          ..moveTo(256, 114)
          ..lineTo(298, 112)
          ..lineTo(296, 154),
        line,
      );
  }

  @override
  bool shouldRepaint(_MarkPainter oldDelegate) => false;
}
