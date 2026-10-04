import 'dart:math';

import 'package:flutter/material.dart';

import 'chart_data.dart';
import 'chart_parts.dart';

/// Option C: a month's spending as a ring. Tap a slice or a row to lift
/// it out; the centre shows its amount and share.
class DonutChart extends StatefulWidget {
  const DonutChart({super.key, required this.data});

  final ChartData data;

  @override
  State<DonutChart> createState() => _DonutChartState();
}

class _DonutChartState extends State<DonutChart> {
  late int _month = widget.data.months.length - 1;
  int? _selected;

  void _select(int? index) =>
      setState(() => _selected = index == _selected ? null : index);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final slices = widget.data.categories[_month];
    final total = widget.data.months[_month].expense;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MonthStepper(
          months: widget.data.months,
          index: _month,
          suffix: ' 支出',
          onChanged: (index) => setState(() {
            _month = index;
            _selected = null;
          }),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 260,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = constraints.biggest;
              return GestureDetector(
                onTapUp: (details) =>
                    _select(donutSliceAt(slices, size, details.localPosition)),
                child: TweenAnimationBuilder<double>(
                  key: ValueKey(_month),
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.easeOutCubic,
                  builder: (context, sweep, _) => CustomPaint(
                    size: Size.infinite,
                    painter: _DonutPainter(
                      slices: slices,
                      total: total,
                      selected: _selected,
                      sweep: sweep,
                      text: theme.textTheme,
                      gap: theme.colorScheme.surface,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        for (final (i, slice) in slices.indexed)
          CategoryRow(
            slice,
            total,
            selected: i == _selected,
            onTap: () => _select(i),
          ),
      ],
    );
  }
}

/// The ring's radii in a box of [size]; the selected slice reaches out
/// to [lifted].
({Offset centre, double inner, double outer, double lifted}) _ring(Size size) {
  final outer = min(size.width, size.height) / 2 - 12;
  return (
    centre: size.center(Offset.zero),
    inner: outer * 0.6,
    outer: outer,
    lifted: outer + 10,
  );
}

/// The slice under [position], or null outside the ring.
int? donutSliceAt(List<CategorySlice> slices, Size size, Offset position) {
  final ring = _ring(size);
  final offset = position - ring.centre;
  final distance = offset.distance;
  if (distance < ring.inner || distance > ring.lifted) return null;
  // Angles run clockwise from twelve o'clock, as the slices are drawn.
  final angle = (offset.direction + pi / 2) % (2 * pi);
  final total = slices.fold(0, (sum, s) => sum + s.amount);
  var start = 0.0;
  for (final (i, slice) in slices.indexed) {
    start += 2 * pi * slice.amount / total;
    if (angle < start) return i;
  }
  return null;
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.slices,
    required this.total,
    required this.selected,
    required this.sweep,
    required this.text,
    required this.gap,
  });

  final List<CategorySlice> slices;
  final int total;
  final int? selected;
  final double sweep;
  final TextTheme text;
  final Color gap;

  @override
  void paint(Canvas canvas, Size size) {
    final ring = _ring(size);
    final sum = slices.fold(0, (s, slice) => s + slice.amount);
    if (sum == 0) return;
    var start = -pi / 2;
    for (final (i, slice) in slices.indexed) {
      final angle = 2 * pi * slice.amount / sum * sweep;
      final lifted = i == selected;
      final outer = lifted ? ring.lifted : ring.outer;
      final faded = selected != null && !lifted;
      final path = Path()
        ..arcTo(
          Rect.fromCircle(center: ring.centre, radius: outer),
          start,
          angle,
          true,
        )
        ..arcTo(
          Rect.fromCircle(center: ring.centre, radius: ring.inner),
          start + angle,
          -angle,
          false,
        )
        ..close();
      final color = faded ? slice.color.withValues(alpha: 0.35) : slice.color;
      canvas.drawPath(path, Paint()..color = color);
      canvas.drawPath(
        path,
        Paint()
          ..color = gap
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      start += angle;
    }

    final index = selected;
    final title = index == null ? '總支出' : slices[index].name;
    final amount = index == null ? total : slices[index].amount;
    final share = index == null
        ? '${slices.length} 個分類'
        : '${(amount / sum * 100).toStringAsFixed(1)}%';
    final width = ring.inner * 1.6;
    paintText(
      canvas,
      title,
      text.labelLarge!,
      ring.centre.translate(0, -22),
      maxWidth: width,
    );
    paintText(
      canvas,
      groupDigits(amount),
      text.titleLarge!.copyWith(
        fontWeight: FontWeight.w700,
        color: index == null ? null : slices[index].color,
      ),
      ring.centre,
      maxWidth: width,
    );
    paintText(
      canvas,
      share,
      text.labelMedium!,
      ring.centre.translate(0, 22),
      maxWidth: width,
    );
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.selected != selected ||
      old.sweep != sweep ||
      old.slices != slices ||
      old.text != text;
}
