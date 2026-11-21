import 'dart:math';

import 'package:flutter/material.dart';

import '../design_system/theme.dart';
import '../design_system/shape.dart';
import '../design_system/motion.dart';

/// The share of a bar's full length that [value] takes next to
/// [largest], in proportion, and at least a sliver when it is not zero.
double barShare(num value, num largest) {
  if (largest == 0 || value == 0) return 0;
  final ratio = (value.abs() / largest.abs()).clamp(0.0, 1.0);
  return max(ratio.toDouble(), 0.04);
}

/// One bar growing left or right from an axis. Positive values take
/// [positive], negative ones [negative]; the axis sits at [axis] of the
/// width (0.5 to diverge, 0 to grow from the left edge).
class AxisBar extends StatelessWidget {
  const AxisBar({
    super.key,
    required this.value,
    required this.largest,
    this.axis = 0.5,
    this.positive = AppColors.positive,
    this.negative = AppColors.negative,
    this.height = 12,
    this.minimum = 0,
  });

  final num value;
  final num largest;
  final double axis;
  final Color positive;
  final Color negative;
  final double height;

  /// The share the smallest non-zero value still gets, so every bar
  /// stays visible; larger values grow in proportion above it.
  final double minimum;

  @override
  Widget build(BuildContext context) {
    final share = barShare(value, largest);
    final end = value == 0 ? share : minimum + (1 - minimum) * share;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: end),
      duration: Motion.of(context, Motion.medium4),
      curve: Curves.easeOutCubic,
      builder: (context, share, _) => CustomPaint(
        size: Size(double.infinity, height + 12),
        painter: _AxisBarPainter(
          share: share,
          rising: value >= 0,
          axis: axis,
          color: markOf(value >= 0 ? positive : negative),
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
        const Radius.circular(Radii.extraSmall),
      ),
      Paint()..color = AppColors.surface.withValues(alpha: 0.6),
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
        const Radius.circular(Radii.extraSmall),
      ),
      Paint()..color = color,
    );
    canvas.drawLine(
      Offset(x, 0),
      Offset(x, size.height),
      Paint()
        ..color = AppColors.faint
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_AxisBarPainter old) =>
      old.share != share || old.color != color || old.axis != axis;
}
