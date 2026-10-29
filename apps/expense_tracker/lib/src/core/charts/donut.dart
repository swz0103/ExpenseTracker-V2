import 'dart:math';

import 'package:flutter/material.dart';

import '../look/theme.dart';

/// A ring cut into [slices], each its value's share of the whole and in
/// its own colour, clockwise from the top; [center] sits in the hole.
class Donut extends StatelessWidget {
  const Donut({
    super.key,
    required this.slices,
    this.size = 132,
    this.thickness = 18,
    this.center,
  });

  final List<(int, Color)> slices;
  final double size;
  final double thickness;
  final Widget? center;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _DonutPainter(slices, thickness),
        child: Center(
          child: Padding(padding: EdgeInsets.all(thickness + 4), child: center),
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.slices, this.thickness);

  final List<(int, Color)> slices;
  final double thickness;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      thickness / 2,
      thickness / 2,
      size.width - thickness,
      size.height - thickness,
    );
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness;
    final whole = slices.fold(0, (sum, s) => sum + max(s.$1, 0));
    if (whole <= 0) {
      canvas.drawArc(rect, 0, 2 * pi, false, stroke..color = Hue.track);
      return;
    }
    // A thin gap between slices, none when one slice is all of it.
    final shown = slices.where((s) => s.$1 > 0).length;
    final gap = shown > 1 ? 0.035 : 0.0;
    var start = -pi / 2;
    for (final (value, color) in slices) {
      if (value <= 0) continue;
      final sweep = 2 * pi * value / whole;
      final drawn = max(sweep - gap, 0.001);
      canvas.drawArc(
        rect,
        start + gap / 2,
        drawn,
        false,
        stroke..color = color,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.thickness != thickness || !_same(old.slices, slices);

  static bool _same(List<(int, Color)> a, List<(int, Color)> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
