import 'dart:math';

import 'package:flutter/material.dart';

import '../charts/chart_data.dart';
import '../charts/chart_parts.dart';
import '../theme.dart';

/// A line over [slots] evenly spaced points, of which the first
/// `values.length` are known. Tap or drag to choose a point; its value is
/// written on the chart beside it.
class LineChart extends StatelessWidget {
  const LineChart({
    super.key,
    required this.values,
    required this.selected,
    required this.onSelect,
    this.slots,
    this.reference,
    this.labels = const {},
    this.fromZero = false,
  });

  final List<int> values;
  final int selected;
  final ValueChanged<int> onSelect;

  /// Points across the width; defaults to the number of values.
  final int? slots;

  /// A dashed line to compare with, one value per slot.
  final List<int>? reference;

  /// Labels under some points, by index.
  final Map<int, String> labels;

  /// Whether the scale starts at zero rather than near the lowest value.
  final bool fromZero;

  int get _slots => max(slots ?? values.length, 2);

  void _pick(Offset at, double width) {
    if (values.isEmpty) return;
    final index = (at.dx / width * (_slots - 1)).round();
    final known = index.clamp(0, values.length - 1);
    if (known != selected) onSelect(known);
  }

  @override
  Widget build(BuildContext context) {
    final label = Theme.of(context).textTheme.labelSmall!;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          onTapDown: (d) => _pick(d.localPosition, width),
          onHorizontalDragUpdate: (d) => _pick(d.localPosition, width),
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: 1),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (context, reveal, _) => CustomPaint(
              size: Size.infinite,
              painter: _LinePainter(
                values: values,
                slots: _slots,
                reference: reference,
                labels: labels,
                fromZero: fromZero,
                selected: selected,
                reveal: reveal,
                label: label,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({
    required this.values,
    required this.slots,
    required this.reference,
    required this.labels,
    required this.fromZero,
    required this.selected,
    required this.reveal,
    required this.label,
  });

  final List<int> values;
  final int slots;
  final List<int>? reference;
  final Map<int, String> labels;
  final bool fromZero;
  final int selected;
  final double reveal;
  final TextStyle label;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    const top = 18.0;
    final bottom = size.height - (labels.isEmpty ? 2 : 16);
    final all = [...values, ...?reference];
    final high = all.reduce(max);
    final lowest = all.reduce(min);
    final low = fromZero ? min(0, lowest) : lowest - (high - lowest) * 0.15;
    final span = max(1.0, high - low);
    double x(int i) => size.width * i / (slots - 1);
    double y(num v) => bottom - (bottom - top) * (v - low) / span;
    final muted = label.copyWith(color: Palette.muted);

    canvas.drawLine(
      Offset(0, bottom),
      Offset(size.width, bottom),
      Paint()..color = Palette.line,
    );
    final guide = reference;
    if (guide != null) {
      final paint = Paint()
        ..color = Palette.muted
        ..strokeWidth = 1;
      for (var i = 0; i < guide.length - 1; i++) {
        final from = Offset(x(i), y(guide[i]));
        _dash(canvas, from, Offset(x(i + 1), y(guide[i + 1])), paint);
      }
    }
    for (final MapEntry(key: i, value: text) in labels.entries) {
      final anchor = i == 0 ? 0.0 : (i == slots - 1 ? 1.0 : 0.5);
      paintText(
        canvas,
        text,
        muted,
        Offset(x(i), size.height),
        anchor: Offset(anchor, 1),
      );
    }

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width * reveal, size.height));
    final line = Path()..moveTo(x(0), y(values[0]));
    for (var i = 1; i < values.length; i++) {
      line.lineTo(x(i), y(values[i]));
    }
    final area = Path.from(line)
      ..lineTo(x(values.length - 1), bottom)
      ..lineTo(x(0), bottom)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Palette.clay.withValues(alpha: 0.22),
            Palette.clay.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromLTRB(0, top, size.width, bottom)),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = Palette.clay
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();
    if (reveal < 1) return;

    final i = selected.clamp(0, values.length - 1);
    final point = Offset(x(i), y(values[i]));
    canvas.drawLine(
      Offset(point.dx, top - 4),
      Offset(point.dx, bottom),
      Paint()..color = Palette.ink.withValues(alpha: 0.2),
    );
    canvas.drawCircle(point, 4.5, Paint()..color = Palette.card);
    canvas.drawCircle(
      point,
      4.5,
      Paint()
        ..color = Palette.clay
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    final right = point.dx > size.width * 0.7;
    paintText(
      canvas,
      compactAmount(values[i]),
      label.copyWith(color: Palette.clay, fontWeight: FontWeight.w700),
      Offset(point.dx + (right ? -6 : 6), top - 4),
      anchor: Offset(right ? 1 : 0, 0.5),
    );
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.selected != selected || old.reveal != reveal || old.values != values;
}

void _dash(Canvas canvas, Offset from, Offset to, Paint paint) {
  final length = (to - from).distance;
  if (length == 0) return;
  final step = (to - from) / length;
  for (var at = 0.0; at < length; at += 6) {
    final dash = min(3.0, length - at);
    canvas.drawLine(from + step * at, from + step * (at + dash), paint);
  }
}

/// Columns in groups, one group per label and one column per series.
/// Tap a group to choose it; its values are written over its columns.
class ColumnChart extends StatelessWidget {
  const ColumnChart({
    super.key,
    required this.series,
    required this.colors,
    required this.labels,
    required this.selected,
    required this.onSelect,
  });

  /// Each series has one value per label.
  final List<List<int>> series;
  final List<Color> colors;
  final List<String> labels;
  final int? selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final label = Theme.of(context).textTheme.labelSmall!;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          onTapDown: (d) {
            final index = (d.localPosition.dx / width * labels.length).floor();
            if (index >= 0 && index < labels.length) onSelect(index);
          },
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: 1),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            builder: (context, grow, _) => CustomPaint(
              size: Size.infinite,
              painter: _ColumnsPainter(
                series: series,
                colors: colors,
                labels: labels,
                selected: selected,
                grow: grow,
                label: label,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ColumnsPainter extends CustomPainter {
  _ColumnsPainter({
    required this.series,
    required this.colors,
    required this.labels,
    required this.selected,
    required this.grow,
    required this.label,
  });

  final List<List<int>> series;
  final List<Color> colors;
  final List<String> labels;
  final int? selected;
  final double grow;
  final TextStyle label;

  @override
  void paint(Canvas canvas, Size size) {
    const top = 16.0;
    final bottom = size.height - 16;
    final high = max(1, [for (final s in series) ...s].fold(0, max));
    final slot = size.width / labels.length;
    const gap = 3.0;
    final count = series.length;
    final column = min(16.0, (slot * 0.7 - gap * (count - 1)) / count);
    final groupWidth = column * count + gap * (count - 1);
    for (var i = 0; i < labels.length; i++) {
      final picked = i == selected;
      final faded = selected != null && !picked;
      var left = slot * i + (slot - groupWidth) / 2;
      for (final (s, values) in series.indexed) {
        final height = max(2.0, (bottom - top) * values[i] / high * grow);
        final color = colors[s];
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTWH(left, bottom - height, column, height),
            topLeft: const Radius.circular(3),
            topRight: const Radius.circular(3),
          ),
          Paint()..color = faded ? color.withValues(alpha: 0.35) : color,
        );
        if (picked) {
          paintText(
            canvas,
            compactAmount(values[i]),
            label.copyWith(color: Palette.ink, fontWeight: FontWeight.w700),
            Offset(left + column / 2, bottom - height - 2),
            anchor: const Offset(0.5, 1),
          );
        }
        left += column + gap;
      }
      paintText(
        canvas,
        labels[i],
        label.copyWith(
          color: picked ? Palette.ink : Palette.muted,
          fontWeight: picked ? FontWeight.w700 : FontWeight.w400,
        ),
        Offset(slot * (i + 0.5), size.height),
        anchor: const Offset(0.5, 1),
      );
    }
  }

  @override
  bool shouldRepaint(_ColumnsPainter old) =>
      old.selected != selected || old.grow != grow || old.series != series;
}
