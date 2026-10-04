import 'dart:math';

import 'package:flutter/material.dart';

import 'chart_data.dart';
import 'chart_parts.dart';

/// Option B: smooth lines over the last 3, 6 or 12 months, of income and
/// expense or of net worth. Touch or drag along the chart to read a month.
class TrendChart extends StatefulWidget {
  const TrendChart({super.key, required this.data});

  final ChartData data;

  @override
  State<TrendChart> createState() => _TrendChartState();
}

enum _Mode { flow, worth }

class _TrendChartState extends State<TrendChart> {
  var _range = 6;
  var _mode = _Mode.flow;
  int? _touched;

  List<MonthPoint> get _months {
    final all = widget.data.months;
    return all.sublist(max(0, all.length - _range));
  }

  void _touch(Offset position, double width) {
    final count = _months.length;
    final step = (width - 2 * _TrendPainter.inset) / max(1, count - 1);
    final index = ((position.dx - _TrendPainter.inset) / step).round();
    final clamped = index.clamp(0, count - 1);
    if (clamped != _touched) setState(() => _touched = clamped);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final months = _months;
    final shown = months[_touched ?? months.length - 1];
    final before = months.indexOf(shown) > 0
        ? months[months.indexOf(shown) - 1]
        : null;
    final series = switch (_mode) {
      _Mode.flow => [
        _Series('收入', ChartColors.income, [for (final m in months) m.income]),
        _Series('支出', ChartColors.expense, [for (final m in months) m.expense]),
      ],
      _Mode.worth => [
        _Series('淨資產', ChartColors.netWorth, [
          for (final m in months) m.netWorth,
        ]),
      ],
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SegmentedButton<_Mode>(
              segments: const [
                ButtonSegment(value: _Mode.flow, label: Text('收支')),
                ButtonSegment(value: _Mode.worth, label: Text('淨資產')),
              ],
              selected: {_mode},
              showSelectedIcon: false,
              onSelectionChanged: (choice) => setState(() {
                _mode = choice.single;
              }),
            ),
            for (final range in const [3, 6, 12])
              ChoiceChip(
                label: Text('$range個月'),
                selected: _range == range,
                onSelected: (_) => setState(() {
                  _range = range;
                  _touched = null;
                }),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          '${shown.year}年${shown.month}月',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        if (_mode == _Mode.flow)
          Row(
            children: [
              Expanded(
                child: AmountFigure('收入', shown.income, ChartColors.income),
              ),
              Expanded(
                child: AmountFigure('支出', shown.expense, ChartColors.expense),
              ),
            ],
          )
        else
          Row(
            children: [
              Expanded(
                child: AmountFigure(
                  '淨資產',
                  shown.netWorth,
                  ChartColors.netWorth,
                ),
              ),
              if (before != null)
                Expanded(
                  child: AmountFigure(
                    '比上月',
                    shown.netWorth - before.netWorth,
                    shown.netWorth < before.netWorth
                        ? ChartColors.expense
                        : ChartColors.income,
                  ),
                ),
            ],
          ),
        const SizedBox(height: 12),
        SizedBox(
          height: 220,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              return GestureDetector(
                onTapDown: (details) => _touch(details.localPosition, width),
                onHorizontalDragStart: (details) =>
                    _touch(details.localPosition, width),
                onHorizontalDragUpdate: (details) =>
                    _touch(details.localPosition, width),
                child: TweenAnimationBuilder<double>(
                  key: ValueKey((_range, _mode)),
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 800),
                  curve: Curves.easeInOutCubic,
                  builder: (context, reveal, _) => CustomPaint(
                    size: Size.infinite,
                    painter: _TrendPainter(
                      months: months,
                      series: series,
                      touched: _touched,
                      reveal: reveal,
                      label: theme.textTheme.labelSmall!,
                      grid: theme.colorScheme.outlineVariant,
                      surface: theme.colorScheme.surface,
                      ink: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

final class _Series {
  const _Series(this.name, this.color, this.values);

  final String name;
  final Color color;
  final List<int> values;
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.months,
    required this.series,
    required this.touched,
    required this.reveal,
    required this.label,
    required this.grid,
    required this.surface,
    required this.ink,
  });

  final List<MonthPoint> months;
  final List<_Series> series;
  final int? touched;
  final double reveal;
  final TextStyle label;
  final Color grid;
  final Color surface;
  final Color ink;

  /// Room at either end so the first and last points are not cut off.
  static const inset = 16.0;
  static const _labelHeight = 20.0;
  static const _top = 12.0;

  @override
  void paint(Canvas canvas, Size size) {
    final bottom = size.height - _labelHeight;
    final values = [for (final s in series) ...s.values];
    final high = values.fold(1, max);
    final low = values.fold(high, min);
    // Net worth moves little against its size, so its scale starts near
    // its lowest value; income and expense start at zero.
    final step = series.length == 1
        ? gridStep(max(1, high - low), 3)
        : gridStep(high, 3);
    final floor = series.length == 1 ? (low ~/ step) * step : 0;
    final ceiling = floor + step * 3 + (series.length == 1 ? step : 0);
    final span = (ceiling - floor).toDouble();
    final height = bottom - _top;
    double yOf(int value) => bottom - height * (value - floor) / span;
    final dx = (size.width - 2 * inset) / max(1, months.length - 1);
    double xOf(int i) => inset + dx * i;

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    final muted = label.copyWith(color: label.color?.withValues(alpha: 0.7));
    for (var value = floor; value <= ceiling; value += step) {
      final y = yOf(value);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
      if (value != floor) {
        paintText(
          canvas,
          compactAmount(value),
          muted,
          Offset(0, y - 2),
          anchor: const Offset(0, 1),
        );
      }
    }
    final every = months.length > 6 ? 2 : 1;
    for (final (i, month) in months.indexed) {
      if ((months.length - 1 - i) % every != 0) continue;
      paintText(
        canvas,
        month.label,
        i == touched ? label.copyWith(fontWeight: FontWeight.w700) : muted,
        Offset(xOf(i), bottom + 4),
        anchor: const Offset(0.5, 0),
      );
    }

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width * reveal, size.height));
    for (final s in series) {
      final points = [
        for (final (i, v) in s.values.indexed) Offset(xOf(i), yOf(v)),
      ];
      final line = _smooth(points);
      final area = Path.from(line)
        ..lineTo(points.last.dx, bottom)
        ..lineTo(points.first.dx, bottom)
        ..close();
      canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              s.color.withValues(alpha: 0.22),
              s.color.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromLTRB(0, _top, size.width, bottom)),
      );
      canvas.drawPath(
        line,
        Paint()
          ..color = s.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
    canvas.restore();

    final at = touched;
    if (at == null || reveal < 1) return;
    final x = xOf(at);
    canvas.drawLine(
      Offset(x, _top),
      Offset(x, bottom),
      Paint()
        ..color = ink.withValues(alpha: 0.4)
        ..strokeWidth = 1,
    );
    for (final s in series) {
      final point = Offset(x, yOf(s.values[at]));
      canvas.drawCircle(point, 5, Paint()..color = surface);
      canvas.drawCircle(
        point,
        5,
        Paint()
          ..color = s.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    }
    _tooltip(canvas, size, x, at);
  }

  void _tooltip(Canvas canvas, Size size, double x, int at) {
    final style = label.copyWith(color: surface, fontSize: 12);
    final bold = style.copyWith(fontWeight: FontWeight.w700);
    final lines = [
      layoutText(months[at].label, bold),
      for (final s in series)
        layoutText('${s.name} ${groupDigits(s.values[at])}', style),
    ];
    const pad = 8.0;
    final width = lines.fold(0.0, (w, l) => max(w, l.width)) + pad * 2;
    final height = lines.fold(0.0, (h, l) => h + l.height) + pad * 2;
    final right = x + 10 + width <= size.width;
    final left = (right ? x + 10 : x - 10 - width).clamp(0.0, size.width);
    final box = Rect.fromLTWH(left, 0, width, height);
    canvas.drawRRect(
      RRect.fromRectAndRadius(box, const Radius.circular(8)),
      Paint()..color = ink.withValues(alpha: 0.85),
    );
    var y = box.top + pad;
    for (final line in lines) {
      line.paint(canvas, Offset(box.left + pad, y));
      y += line.height;
      line.dispose();
    }
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.touched != touched ||
      old.reveal != reveal ||
      old.months != months ||
      old.series != series ||
      old.label != label;
}

/// A curve through [points] that never overshoots between them: each
/// segment leaves and arrives horizontally.
Path _smooth(List<Offset> points) {
  final path = Path()..moveTo(points.first.dx, points.first.dy);
  for (var i = 1; i < points.length; i++) {
    final from = points[i - 1];
    final to = points[i];
    final middle = (from.dx + to.dx) / 2;
    path.cubicTo(middle, from.dy, middle, to.dy, to.dx, to.dy);
  }
  return path;
}
