import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// The app icon drawn in place: three rising bars and a growth arrow on
/// misty blue, the same shapes as `tool/app_icon.svg` (its visible 300
/// units).
///
/// [bars] and [arrow] draw it part way, for the opening animation: how
/// tall each bar has grown (1 is its full height; a little over 1
/// overshoots) and how much of the arrow is drawn, from 0 to 1.
class AppMark extends StatelessWidget {
  const AppMark({
    super.key,
    this.size = 96,
    this.bars = (1, 1, 1),
    this.arrow = 1,
  });

  final double size;
  final (double, double, double) bars;
  final double arrow;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _MarkPainter(bars, arrow)),
  );
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter(this.bars, this.arrow);

  final (double, double, double) bars;
  final double arrow;

  /// The arrow's line, then its head: the head is drawn in the last
  /// quarter.
  static final _line = Path()
    ..moveTo(118, 206)
    ..lineTo(182, 160)
    ..lineTo(224, 182)
    ..lineTo(292, 118);
  static final _head = Path()
    ..moveTo(256, 114)
    ..lineTo(298, 112)
    ..lineTo(296, 154);

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
    final (first, second, third) = bars;
    for (final (left, top, color, grown) in [
      (126.0, 246.0, const Color(0xFFCAD6D8), first),
      (194.0, 208.0, const Color(0xFFF3F4F1), second),
      (262.0, 168.0, const Color(0xFFC9A34A), third),
    ]) {
      final height = (310 - top) * math.max(0.0, grown);
      if (height <= 0) continue;
      canvas.drawRRect(
        RRect.fromLTRBR(
          left,
          310 - height,
          left + 44,
          310,
          Radius.circular(math.min(22.0, height / 2)),
        ),
        Paint()..color = color,
      );
    }
    final pen = Paint()
      ..color = const Color(0xFFF3F4F1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 15
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    _drawPart(canvas, _line, (arrow / 0.75).clamp(0.0, 1.0), pen);
    _drawPart(canvas, _head, ((arrow - 0.75) / 0.25).clamp(0.0, 1.0), pen);
  }

  static void _drawPart(Canvas canvas, Path path, double drawn, Paint pen) {
    if (drawn <= 0) return;
    if (drawn >= 1) {
      canvas.drawPath(path, pen);
      return;
    }
    for (final metric in path.computeMetrics()) {
      canvas.drawPath(metric.extractPath(0, metric.length * drawn), pen);
    }
  }

  @override
  bool shouldRepaint(_MarkPainter oldDelegate) =>
      oldDelegate.bars != bars || oldDelegate.arrow != arrow;
}
