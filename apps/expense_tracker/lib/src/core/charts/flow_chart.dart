import 'dart:math';

import 'package:flutter/material.dart';

import '../../../design_system/display/amount.dart';
import '../design_system/paint.dart';
import '../design_system/theme.dart';
import '../design_system/shape.dart';
import '../design_system/motion.dart';

/// One month of [FlowChart].
final class FlowMonth {
  const FlowMonth(this.label, this.income, this.expense, this.worth);

  final String label;
  final int income;
  final int expense;

  /// Net worth at the month's end.
  final int worth;
}

/// Income and spending as paired columns (left axis, in 萬) with net worth
/// as a line (right axis). Tap a month to choose it.
class FlowChart extends StatelessWidget {
  const FlowChart({
    super.key,
    required this.months,
    required this.selected,
    required this.onSelect,
    this.height = 170,
    this.hidden = false,
  });

  final List<FlowMonth> months;
  final int selected;
  final ValueChanged<int> onSelect;
  final double height;

  /// Whether amounts are hidden: the axes show dots for their figures.
  final bool hidden;

  static const _left = 34.0;
  static const _right = 44.0;

  @override
  Widget build(BuildContext context) {
    // Its own layer: chart animations and taps do not repaint the page.
    return RepaintBoundary(
      child: SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final plot = constraints.maxWidth - _left - _right;
            void pick(Offset at) {
              final index = ((at.dx - _left) / plot * months.length).floor();
              if (index >= 0 && index < months.length) onSelect(index);
            }

            return GestureDetector(
              // Picking by position means nothing to a screen reader, which
              // reads the summary the page gives the chart.
              excludeFromSemantics: true,
              onTapDown: (d) => pick(d.localPosition),
              onHorizontalDragUpdate: (d) => pick(d.localPosition),
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: 1),
                duration: Motion.of(context, Motion.extraLong1),
                curve: Curves.easeOutCubic,
                builder: (context, grow, _) => CustomPaint(
                  size: Size.infinite,
                  painter: _FlowPainter(months, selected, grow, hidden),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _FlowPainter extends CustomPainter {
  _FlowPainter(this.months, this.selected, this.grow, this.hidden);

  final List<FlowMonth> months;
  final int selected;
  final double grow;
  final bool hidden;

  @override
  void paint(Canvas canvas, Size size) {
    if (months.isEmpty) return;
    final frame = _FlowFrame.of(months, size);
    _paintScales(canvas, frame);
    // The chosen month behind everything.
    canvas.drawRRect(
      RRect.fromLTRBR(
        _FlowFrame.left + frame.slot * selected + 2,
        _FlowFrame.top - 6,
        _FlowFrame.left + frame.slot * (selected + 1) - 2,
        frame.bottom + 20,
        const Radius.circular(Radii.small),
      ),
      Paint()..color = AppColors.surface,
    );
    _paintColumns(canvas, size, frame);
    _paintWorth(canvas, frame);
  }

  /// The grid and both axes: amounts on the left, net worth on the right.
  void _paintScales(Canvas canvas, _FlowFrame frame) {
    const left = _FlowFrame.left;
    const axis = mutedTiny;
    final plot = frame.plot;
    final grid = Paint()
      ..color = AppColors.line
      ..strokeWidth = 1;
    for (final step in const [0, 1, 2]) {
      final value = frame.ceiling * step ~/ 2;
      final yy = frame.y(value);
      if (step == 0) {
        canvas.drawLine(Offset(left, yy), Offset(left + plot, yy), grid);
      } else {
        _dotted(canvas, Offset(left, yy), Offset(left + plot, yy), grid);
      }
      paintText(
        canvas,
        step == 0
            ? '0'
            : hidden
            ? '••'
            : '${tenThousands(value)}萬',
        axis,
        Offset(left - 6, yy),
        anchor: const Offset(1, 0.5),
      );
      final worth = frame.floor + frame.span * step / 2;
      paintText(
        canvas,
        hidden ? '••' : '${tenThousands(worth.round())}萬',
        axis.copyWith(color: AppColors.investment),
        Offset(left + plot + 6, frame.y(value)),
        anchor: const Offset(0, 0.5),
      );
    }
  }

  /// Each month's income and spending as two columns, grown by [grow],
  /// over its name.
  void _paintColumns(Canvas canvas, Size size, _FlowFrame frame) {
    const axis = mutedTiny;
    final slot = frame.slot;
    final bottom = frame.bottom;
    final bar = min(12.0, slot * 0.24);
    for (final (i, m) in months.indexed) {
      final centre = _FlowFrame.left + slot * (i + 0.5);
      final faded = i != selected;
      void column(int value, double x, Color color) {
        final h = (bottom - frame.y(value)) * grow;
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTWH(x, bottom - h, bar, h),
            topLeft: const Radius.circular(Radii.extraSmall),
            topRight: const Radius.circular(Radii.extraSmall),
          ),
          Paint()..color = faded ? color.withValues(alpha: 0.85) : color,
        );
      }

      column(m.income, centre - bar - 2, markOf(AppColors.positive));
      column(m.expense, centre + 2, markOf(AppColors.negative));
      paintText(
        canvas,
        m.label,
        axis.copyWith(
          color: i == selected ? AppColors.ink : AppColors.muted,
          fontWeight: i == selected ? FontWeight.w700 : FontWeight.w400,
        ),
        Offset(centre, size.height - 2),
        anchor: const Offset(0.5, 1),
      );
    }
  }

  /// Net worth as a line through a ring on each month, larger on the
  /// chosen one.
  void _paintWorth(Canvas canvas, _FlowFrame frame) {
    Offset pointOf(int i, FlowMonth m) =>
        Offset(_FlowFrame.left + frame.slot * (i + 0.5), frame.yWorth(m.worth));
    final line = Path();
    for (final (i, m) in months.indexed) {
      final point = pointOf(i, m);
      if (i == 0) {
        line.moveTo(point.dx, point.dy);
      } else {
        line.lineTo(point.dx, point.dy);
      }
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = markOf(AppColors.investment)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
    for (final (i, m) in months.indexed) {
      final point = pointOf(i, m);
      final r = i == selected ? 5.0 : 3.0;
      canvas.drawCircle(point, r, Paint()..color = AppColors.panel);
      canvas.drawCircle(
        point,
        r,
        Paint()
          ..color = markOf(AppColors.investment)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(_FlowPainter old) =>
      old.selected != selected ||
      old.grow != grow ||
      old.months != months ||
      old.hidden != hidden;
}

/// Where things sit on the flow chart: the plot's bottom and width, a
/// month's slot, and the scales of the columns and of net worth.
final class _FlowFrame {
  const _FlowFrame({
    required this.bottom,
    required this.plot,
    required this.slot,
    required this.ceiling,
    required this.floor,
    required this.span,
  });

  factory _FlowFrame.of(List<FlowMonth> months, Size size) {
    final bottom = size.height - 22;
    final plot = size.width - left - FlowChart._right;
    var high = 1;
    for (final m in months) {
      high = max(high, max(m.income, m.expense));
    }
    final worths = [for (final m in months) m.worth];
    final low = worths.reduce(min);
    final peak = worths.reduce(max);
    final pad = max(1, (peak - low) * 0.2);
    final floor = low - pad;
    return _FlowFrame(
      bottom: bottom,
      plot: plot,
      slot: plot / months.length,
      ceiling: (high / 1000).ceil() * 1000,
      floor: floor,
      span: peak + pad - floor,
    );
  }

  static const left = FlowChart._left;
  static const top = 12.0;

  final double bottom;
  final double plot;
  final double slot;

  /// The amount at the top of the columns' scale, in whole thousands.
  final int ceiling;

  /// The net worth at the bottom of its scale, and how far the scale
  /// reaches above it.
  final num floor;
  final num span;

  /// Where the amount [v] sits.
  double y(num v) => bottom - (bottom - top) * v / ceiling;

  /// Where the net worth [v] sits.
  double yWorth(num v) => bottom - (bottom - top) * (v - floor) / span;
}

void _dotted(Canvas canvas, Offset from, Offset to, Paint paint) {
  final length = (to - from).distance;
  final step = (to - from) / length;
  for (var at = 0.0; at < length; at += 5) {
    canvas.drawLine(from + step * at, from + step * min(at + 2, length), paint);
  }
}
