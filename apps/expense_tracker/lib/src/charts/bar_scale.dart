import 'dart:math';

import 'package:flutter/material.dart';

import '../look/theme.dart';

/// How bar lengths follow values. Small changes are enlarged by default
/// (a square-root scale) so they stay visible next to large ones; the
/// proportional scale is linear.
enum BarScale {
  enlarged('小額放大'),
  proportional('等比例');

  const BarScale(this.label);

  final String label;

  BarScale get other =>
      this == enlarged ? BarScale.proportional : BarScale.enlarged;

  /// The share of the full length that [value] takes, at least a sliver
  /// when it is not zero.
  double share(num value, num largest) {
    if (largest == 0 || value == 0) return 0;
    final ratio = (value.abs() / largest.abs()).clamp(0.0, 1.0);
    final scaled = this == enlarged ? sqrt(ratio) : ratio.toDouble();
    return max(scaled, 0.04);
  }
}

/// One bar growing left or right from an axis. Positive values take
/// [positive], negative ones [negative]; the axis sits at [axis] of the
/// width (0.5 to diverge, 0 to grow from the left edge).
class AxisBar extends StatelessWidget {
  const AxisBar({
    super.key,
    required this.value,
    required this.largest,
    this.scale = BarScale.proportional,
    this.axis = 0.5,
    this.positive = Hue.positive,
    this.negative = Hue.negative,
    this.height = 12,
  });

  final num value;
  final num largest;
  final BarScale scale;
  final double axis;
  final Color positive;
  final Color negative;
  final double height;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: scale.share(value, largest)),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      builder: (context, share, _) => CustomPaint(
        size: Size(double.infinity, height + 12),
        painter: _AxisBarPainter(
          share: share,
          rising: value >= 0,
          axis: axis,
          color: value >= 0 ? positive : negative,
          height: height,
        ),
      ),
    );
  }
}

class _AxisBarPainter extends CustomPainter {
  _AxisBarPainter({
    required this.share,
    required this.rising,
    required this.axis,
    required this.color,
    required this.height,
  });

  final double share;
  final bool rising;
  final double axis;
  final Color color;
  final double height;

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width * axis;
    final middle = size.height / 2;
    canvas.drawRRect(
      RRect.fromLTRBR(
        0,
        middle - height / 2,
        size.width,
        middle + height / 2,
        const Radius.circular(3),
      ),
      Paint()..color = Hue.surface.withValues(alpha: 0.6),
    );
    final room = rising ? size.width - x : x;
    final length = room * share;
    final left = rising ? x : x - length;
    canvas.drawRRect(
      RRect.fromLTRBR(
        left,
        middle - height / 2,
        left + length,
        middle + height / 2,
        const Radius.circular(2),
      ),
      Paint()..color = color,
    );
    canvas.drawLine(
      Offset(x, 0),
      Offset(x, size.height),
      Paint()
        ..color = Hue.faint
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_AxisBarPainter old) =>
      old.share != share || old.color != color || old.axis != axis;
}
