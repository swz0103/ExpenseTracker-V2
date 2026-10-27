import 'dart:math';

import 'package:flutter/material.dart';

import '../look/paint.dart';
import '../look/theme.dart';

/// One stretch of a report: a week, a month, and what came in and went
/// out in it. A stretch still ahead has [ahead] set and no figures.
final class PeriodBucket {
  const PeriodBucket(
    this.label,
    this.income,
    this.expense, {
    this.ahead = false,
  });

  final String label;
  final int income;
  final int expense;
  final bool ahead;
}

/// Income and spending of each stretch as paired columns, with net worth
/// at each stretch's end as a line on its own scale; stretches still
/// ahead stay empty. Tap a stretch to choose it.
class PeriodBars extends StatelessWidget {
  const PeriodBars({
    super.key,
    required this.buckets,
    required this.selected,
    required this.onSelect,
    this.worth = const [],
    this.height = 170,
  });

  final List<PeriodBucket> buckets;

  /// Net worth at the end of each stretch; null for those ahead.
  final List<int?> worth;
  final int? selected;
  final ValueChanged<int?> onSelect;
  final double height;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            return GestureDetector(
              // Picking by position means nothing to a screen reader, which
              // reads the summary the page gives the chart.
              excludeFromSemantics: true,
              onTapDown: (d) {
                final i = (d.localPosition.dx / width * buckets.length).floor();
                if (i < 0 || i >= buckets.length || buckets[i].ahead) return;
                onSelect(i == selected ? null : i);
              },
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: 1),
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeOutCubic,
                builder: (context, grow, _) => CustomPaint(
                  size: Size(width, height),
                  painter: _BarsPainter(buckets, worth, selected, grow),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter(this.buckets, this.worth, this.selected, this.grow);

  final List<PeriodBucket> buckets;
  final List<int?> worth;
  final int? selected;
  final double grow;

  static const _labels = 18.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (buckets.isEmpty) return;
    final plot = size.height - _labels;
    final slot = size.width / buckets.length;
    final largest = buckets.fold(1, (m, b) => max(m, max(b.income, b.expense)));
    final bar = min(14.0, slot * 0.32);
    final faded = selected != null;
    for (final (i, b) in buckets.indexed) {
      final x = slot * i + slot / 2;
      if (i == selected) {
        canvas.drawRRect(
          RRect.fromLTRBR(
            slot * i + 2,
            0,
            slot * (i + 1) - 2,
            plot,
            const Radius.circular(8),
          ),
          Paint()..color = Hue.selected,
        );
      }
      if (!b.ahead) {
        final dim = faded && i != selected;
        for (final (k, (value, color)) in [
          (b.income, Hue.positive),
          (b.expense, Hue.negative),
        ].indexed) {
          final h = plot * value / largest * grow;
          final left = k == 0 ? x - bar - 1 : x + 1;
          canvas.drawRRect(
            RRect.fromLTRBAndCorners(
              left,
              plot - h,
              left + bar,
              plot,
              topLeft: const Radius.circular(3),
              topRight: const Radius.circular(3),
            ),
            Paint()..color = dim ? color.withValues(alpha: 0.35) : color,
          );
        }
      }
      paintText(
        canvas,
        b.label,
        TextStyle(
          fontSize: 11.5,
          color: i == selected ? Hue.ink : Hue.muted,
          fontWeight: i == selected ? FontWeight.w700 : FontWeight.w400,
        ),
        Offset(x, size.height - _labels / 2),
      );
    }
    canvas.drawLine(
      Offset(0, plot),
      Offset(size.width, plot),
      Paint()..color = Hue.line,
    );
    _worthLine(canvas, plot, slot);
  }

  /// Net worth as a line through the stretch centres, filling the upper
  /// part of the plot between its lowest and highest values.
  void _worthLine(Canvas canvas, double plot, double slot) {
    final known = [
      for (final v in worth)
        if (v != null) v,
    ];
    if (known.length < 2) return;
    final low = known.reduce(min);
    final span = max(1, known.reduce(max) - low);
    final points = [
      for (final (i, v) in worth.indexed)
        if (v != null)
          Offset(slot * (i + 0.5), 8 + plot * 0.55 * (1 - (v - low) / span)),
    ];
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round
      ..color = Hue.investment.withValues(alpha: grow);
    canvas.drawPath(Path()..addPolygon(points, false), paint);
    for (final p in points) {
      canvas.drawCircle(p, 3, Paint()..color = Hue.white);
      canvas.drawCircle(
        p,
        3,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = Hue.investment.withValues(alpha: grow),
      );
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.buckets != buckets ||
      old.worth != worth ||
      old.selected != selected ||
      old.grow != grow;
}

/// What each stretch's spending was made of: a column per stretch, as
/// tall as its spending, stacked by category. A chosen category stays in
/// colour and the rest fade.
class MixBars extends StatelessWidget {
  const MixBars({
    super.key,
    required this.columns,
    required this.colors,
    required this.labels,
    required this.selected,
    this.height = 150,
  });

  /// Per stretch, the amount of each category in [colors]' order.
  final List<List<int>> columns;
  final List<Color> colors;
  final List<String> labels;
  final int? selected;
  final double height;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: 1),
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutCubic,
        builder: (context, grow, _) => CustomPaint(
          size: Size(double.infinity, height),
          painter: _MixPainter(columns, colors, labels, selected, grow),
        ),
      ),
    );
  }
}

class _MixPainter extends CustomPainter {
  _MixPainter(this.columns, this.colors, this.labels, this.selected, this.grow);

  final List<List<int>> columns;
  final List<Color> colors;
  final List<String> labels;
  final int? selected;
  final double grow;

  @override
  void paint(Canvas canvas, Size size) {
    if (columns.isEmpty) return;
    final plot = size.height - 18;
    final slot = size.width / columns.length;
    final width = min(22.0, slot * 0.62);
    final largest = columns.fold(
      1,
      (m, c) => max(m, c.fold(0, (s, v) => s + v)),
    );
    for (final (i, column) in columns.indexed) {
      final x = slot * i + slot / 2;
      var top = plot;
      for (final (k, value) in column.indexed) {
        if (value <= 0) continue;
        final h = plot * value / largest * grow;
        final dim = selected != null && selected != k;
        canvas.drawRect(
          Rect.fromLTRB(x - width / 2, top - h, x + width / 2, top),
          Paint()
            ..color = dim
                ? colors[k].withValues(alpha: 0.18)
                : colors[k].withValues(alpha: 0.9),
        );
        top -= h;
      }
      if (i < labels.length) {
        paintText(
          canvas,
          labels[i],
          const TextStyle(fontSize: 11.5, color: Hue.muted),
          Offset(x, size.height - 9),
        );
      }
    }
    canvas.drawLine(
      Offset(0, plot),
      Offset(size.width, plot),
      Paint()..color = Hue.line,
    );
  }

  @override
  bool shouldRepaint(_MixPainter old) =>
      old.columns != columns ||
      old.selected != selected ||
      old.grow != grow ||
      old.colors != colors;
}
