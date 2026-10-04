import 'dart:math';

import 'package:flutter/material.dart';

import 'chart_data.dart';
import 'chart_parts.dart';

/// Option A: income and expense per month as paired bars. Tap a month or
/// drag across the bars; the month's figures and categories follow.
class BarsChart extends StatefulWidget {
  const BarsChart({super.key, required this.data});

  final ChartData data;

  @override
  State<BarsChart> createState() => _BarsChartState();
}

class _BarsChartState extends State<BarsChart> {
  late int _selected = widget.data.months.length - 1;

  void _pick(Offset position, double width) {
    final count = widget.data.months.length;
    final index = (position.dx / width * count).floor().clamp(0, count - 1);
    if (index != _selected) setState(() => _selected = index);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final months = widget.data.months;
    final month = months[_selected];
    final categories = widget.data.categories[_selected];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${month.year}年${month.month}月',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: AmountFigure('收入', month.income, ChartColors.income),
            ),
            Expanded(
              child: AmountFigure('支出', month.expense, ChartColors.expense),
            ),
            Expanded(
              child: AmountFigure(
                '結餘',
                month.net,
                month.net < 0 ? ChartColors.expense : ChartColors.income,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 200,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              return GestureDetector(
                onTapDown: (details) => _pick(details.localPosition, width),
                onHorizontalDragUpdate: (details) =>
                    _pick(details.localPosition, width),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.easeOutCubic,
                  builder: (context, grow, _) => CustomPaint(
                    size: Size.infinite,
                    painter: _BarsPainter(
                      months: months,
                      selected: _selected,
                      grow: grow,
                      label: theme.textTheme.labelSmall!,
                      grid: theme.colorScheme.outlineVariant,
                      highlight: theme.colorScheme.primary.withValues(
                        alpha: 0.08,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        for (final slice in categories.take(5))
          CategoryRow(slice, month.expense),
      ],
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({
    required this.months,
    required this.selected,
    required this.grow,
    required this.label,
    required this.grid,
    required this.highlight,
  });

  final List<MonthPoint> months;
  final int selected;
  final double grow;
  final TextStyle label;
  final Color grid;
  final Color highlight;

  static const _labelHeight = 20.0;
  static const _top = 12.0;

  @override
  void paint(Canvas canvas, Size size) {
    final bottom = size.height - _labelHeight;
    final top = months.fold(1, (m, p) => max(m, max(p.income, p.expense)));
    final step = gridStep(top, 3);
    final scale = step * 3;
    final height = bottom - _top;
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    final muted = label.copyWith(color: label.color?.withValues(alpha: 0.7));
    for (var line = 1; line <= 3; line++) {
      final y = bottom - height * line / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
      paintText(
        canvas,
        compactAmount(step * line),
        muted,
        Offset(0, y - 2),
        anchor: const Offset(0, 1),
      );
    }
    canvas.drawLine(Offset(0, bottom), Offset(size.width, bottom), gridPaint);

    final slot = size.width / months.length;
    final bar = min(12.0, slot * 0.3);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(slot * selected, 0, slot, size.height),
        const Radius.circular(8),
      ),
      Paint()..color = highlight,
    );
    for (final (i, month) in months.indexed) {
      final centre = slot * (i + 0.5);
      final strong = i == selected;
      void column(int value, double left, Color color) {
        final h = height * value / scale * grow;
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTWH(left, bottom - h, bar, h),
            topLeft: const Radius.circular(3),
            topRight: const Radius.circular(3),
          ),
          Paint()..color = strong ? color : color.withValues(alpha: 0.45),
        );
      }

      column(month.income, centre - bar - 1, ChartColors.income);
      column(month.expense, centre + 1, ChartColors.expense);
      final name = slot >= 30 ? month.label : '${month.month}';
      final style = strong
          ? label.copyWith(fontWeight: FontWeight.w700)
          : muted;
      paintText(
        canvas,
        name,
        style,
        Offset(centre, bottom + 4),
        anchor: const Offset(0.5, 0),
      );
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.selected != selected ||
      old.grow != grow ||
      old.months != months ||
      old.label != label;
}
