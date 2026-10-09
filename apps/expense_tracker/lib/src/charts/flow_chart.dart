import 'dart:math';

import 'package:flutter/material.dart';

import '../look/figures.dart';
import '../look/paint.dart';
import '../look/theme.dart';

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
  });

  final List<FlowMonth> months;
  final int selected;
  final ValueChanged<int> onSelect;
  final double height;

  static const _left = 30.0;
  static const _right = 40.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final plot = constraints.maxWidth - _left - _right;
          void pick(Offset at) {
            final index = ((at.dx - _left) / plot * months.length).floor();
            if (index >= 0 && index < months.length) onSelect(index);
          }

          return GestureDetector(
            onTapDown: (d) => pick(d.localPosition),
            onHorizontalDragUpdate: (d) => pick(d.localPosition),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: 1),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (context, grow, _) => CustomPaint(
                size: Size.infinite,
                painter: _FlowPainter(months, selected, grow),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FlowPainter extends CustomPainter {
  _FlowPainter(this.months, this.selected, this.grow);

  final List<FlowMonth> months;
  final int selected;
  final double grow;

  @override
  void paint(Canvas canvas, Size size) {
    if (months.isEmpty) return;
    const left = FlowChart._left;
    const right = FlowChart._right;
    const top = 12.0;
    final bottom = size.height - 22;
    final plot = size.width - left - right;
    final slot = plot / months.length;
    const axis = TextStyle(fontSize: 10, color: Hue.muted);

    var high = 1;
    for (final m in months) {
      high = max(high, max(m.income, m.expense));
    }
    final ceiling = (high / 1000).ceil() * 1000;
    double y(num v) => bottom - (bottom - top) * v / ceiling;

    final worths = [for (final m in months) m.worth];
    final low = worths.reduce(min);
    final peak = worths.reduce(max);
    final pad = max(1, (peak - low) * 0.2);
    final floor = low - pad;
    final span = peak + pad - floor;
    double yWorth(num v) => bottom - (bottom - top) * (v - floor) / span;

    // Grid and both axes.
    final grid = Paint()
      ..color = Hue.line
      ..strokeWidth = 1;
    for (final step in const [0, 1, 2]) {
      final value = ceiling * step ~/ 2;
      final yy = y(value);
      if (step == 0) {
        canvas.drawLine(Offset(left, yy), Offset(left + plot, yy), grid);
      } else {
        _dotted(canvas, Offset(left, yy), Offset(left + plot, yy), grid);
      }
      paintText(
        canvas,
        tenThousands(value),
        axis,
        Offset(left - 6, yy),
        anchor: const Offset(1, 0.5),
      );
      final worth = floor + span * step / 2;
      paintText(
        canvas,
        (worth / 10000).toStringAsFixed(1),
        axis.copyWith(color: Hue.investment),
        Offset(left + plot + 6, y(value)),
        anchor: const Offset(0, 0.5),
      );
    }

    // The chosen month behind everything.
    canvas.drawRRect(
      RRect.fromLTRBR(
        left + slot * selected + 2,
        top - 6,
        left + slot * (selected + 1) - 2,
        bottom + 20,
        const Radius.circular(6),
      ),
      Paint()..color = Hue.surface,
    );

    final bar = min(12.0, slot * 0.24);
    for (final (i, m) in months.indexed) {
      final centre = left + slot * (i + 0.5);
      final faded = i != selected;
      void column(int value, double x, Color color) {
        final h = (bottom - y(value)) * grow;
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTWH(x, bottom - h, bar, h),
            topLeft: const Radius.circular(2),
            topRight: const Radius.circular(2),
          ),
          Paint()..color = faded ? color.withValues(alpha: 0.85) : color,
        );
      }

      column(m.income, centre - bar - 2, Hue.positive);
      column(m.expense, centre + 2, Hue.negative);
      paintText(
        canvas,
        m.label,
        axis.copyWith(
          color: i == selected ? Hue.ink : Hue.muted,
          fontWeight: i == selected ? FontWeight.w700 : FontWeight.w400,
        ),
        Offset(centre, size.height - 2),
        anchor: const Offset(0.5, 1),
      );
    }

    // Net worth.
    final line = Path();
    for (final (i, m) in months.indexed) {
      final point = Offset(left + slot * (i + 0.5), yWorth(m.worth));
      if (i == 0) {
        line.moveTo(point.dx, point.dy);
      } else {
        line.lineTo(point.dx, point.dy);
      }
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = Hue.investment
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
    for (final (i, m) in months.indexed) {
      final point = Offset(left + slot * (i + 0.5), yWorth(m.worth));
      final r = i == selected ? 5.0 : 3.0;
      canvas.drawCircle(point, r, Paint()..color = Hue.panel);
      canvas.drawCircle(
        point,
        r,
        Paint()
          ..color = Hue.investment
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(_FlowPainter old) =>
      old.selected != selected || old.grow != grow || old.months != months;
}

void _dotted(Canvas canvas, Offset from, Offset to, Paint paint) {
  final length = (to - from).distance;
  final step = (to - from) / length;
  for (var at = 0.0; at < length; at += 5) {
    canvas.drawLine(
      from + step * at,
      from + step * min(at + 2, length),
      paint,
    );
  }
}
