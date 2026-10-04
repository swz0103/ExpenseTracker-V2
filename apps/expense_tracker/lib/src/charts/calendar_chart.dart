import 'dart:math';

import 'package:flutter/material.dart';

import 'chart_data.dart';
import 'chart_parts.dart';

/// Option D: a month calendar shaded by each day's spending. Tap a day to
/// read it; swipe sideways or use the arrows to change month.
class CalendarChart extends StatefulWidget {
  const CalendarChart({super.key, required this.data});

  final ChartData data;

  @override
  State<CalendarChart> createState() => _CalendarChartState();
}

class _CalendarChartState extends State<CalendarChart> {
  late int _month = widget.data.months.length - 1;
  late int? _day = _lastDay(widget.data.days.last);

  static int? _lastDay(List<int> days) => days.isEmpty ? null : days.length;

  void _show(int month) {
    if (month < 0 || month >= widget.data.months.length) return;
    setState(() {
      _month = month;
      _day = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final month = widget.data.months[_month];
    final days = widget.data.days[_month];
    final layout = CalendarLayout(month.year, month.month);
    final average = days.isEmpty ? 0 : month.expense ~/ days.length;
    final day = _day;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MonthStepper(
          months: widget.data.months,
          index: _month,
          onChanged: _show,
        ),
        Row(
          children: [
            Expanded(
              child: AmountFigure('本月支出', month.expense, ChartColors.expense),
            ),
            Expanded(
              child: AmountFigure('日均', average, theme.colorScheme.onSurface),
            ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final height = layout.heightFor(width);
            return GestureDetector(
              onTapUp: (details) {
                final tapped = layout.dayAt(details.localPosition, width);
                if (tapped != null && tapped <= days.length) {
                  setState(() => _day = tapped == _day ? null : tapped);
                }
              },
              onHorizontalDragEnd: (details) {
                final speed = details.primaryVelocity ?? 0.0;
                if (speed.abs() > 200) _show(_month + (speed < 0 ? 1 : -1));
              },
              child: CustomPaint(
                size: Size(width, height),
                painter: _CalendarPainter(
                  layout: layout,
                  days: days,
                  selected: day,
                  text: theme.textTheme,
                  empty: theme.colorScheme.surfaceContainerHighest,
                  outline: theme.colorScheme.primary,
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        _Legend(empty: theme.colorScheme.surfaceContainerHighest),
        const SizedBox(height: 12),
        if (day != null)
          _DayDetail(
            date: DateTime.utc(month.year, month.month, day),
            amount: days[day - 1],
            average: average,
          ),
      ],
    );
  }
}

/// Where each day of a month sits in a Sunday-first grid.
final class CalendarLayout {
  CalendarLayout(int year, int month)
    : offset = DateTime.utc(year, month).weekday % 7,
      length = DateTime.utc(year, month + 1, 0).day;

  /// Empty cells before the 1st.
  final int offset;
  final int length;

  static const header = 24.0;
  static const cellHeight = 52.0;

  int get rows => (offset + length + 6) ~/ 7;

  double heightFor(double width) => header + rows * cellHeight;

  Rect cell(int day, double width) {
    final index = offset + day - 1;
    final cellWidth = width / 7;
    return Rect.fromLTWH(
      cellWidth * (index % 7),
      header + cellHeight * (index ~/ 7),
      cellWidth,
      cellHeight,
    );
  }

  /// The day under [position], or null.
  int? dayAt(Offset position, double width) {
    if (position.dy < header || position.dx < 0 || position.dx >= width) {
      return null;
    }
    final column = position.dx ~/ (width / 7);
    final row = (position.dy - header) ~/ cellHeight;
    final day = row * 7 + column - offset + 1;
    return day >= 1 && day <= length ? day : null;
  }
}

/// How dark a day is drawn: 0 for nothing spent, up to 4. The scale
/// stops at the 90th percentile so one large payment, such as rent, does
/// not wash out every other day.
int calendarShade(int amount, List<int> days) {
  if (amount <= 0 || days.isEmpty) return 0;
  final sorted = [...days]..sort();
  final cap = max(1, sorted[((sorted.length - 1) * 0.9).round()]);
  return (amount / cap * 4).ceil().clamp(1, 4);
}

Color _shadeColor(int shade, Color empty) => shade == 0
    ? empty
    : ChartColors.expense.withValues(alpha: 0.15 + 0.2 * shade);

class _CalendarPainter extends CustomPainter {
  _CalendarPainter({
    required this.layout,
    required this.days,
    required this.selected,
    required this.text,
    required this.empty,
    required this.outline,
  });

  final CalendarLayout layout;
  final List<int> days;
  final int? selected;
  final TextTheme text;
  final Color empty;
  final Color outline;

  static const _weekdays = ['日', '一', '二', '三', '四', '五', '六'];

  @override
  void paint(Canvas canvas, Size size) {
    final small = text.labelSmall!;
    final cellWidth = size.width / 7;
    for (final (i, name) in _weekdays.indexed) {
      paintText(
        canvas,
        name,
        small,
        Offset(cellWidth * (i + 0.5), CalendarLayout.header / 2),
      );
    }
    for (var day = 1; day <= layout.length; day++) {
      final rect = layout.cell(day, size.width).deflate(2);
      final known = day <= days.length;
      final amount = known ? days[day - 1] : 0;
      final shade = calendarShade(amount, days);
      final box = RRect.fromRectAndRadius(rect, const Radius.circular(8));
      canvas.drawRRect(
        box,
        Paint()..color = known ? _shadeColor(shade, empty) : empty,
      );
      final ink = shade >= 3 ? Colors.white : text.bodySmall!.color;
      paintText(
        canvas,
        '$day',
        small.copyWith(color: ink, fontWeight: FontWeight.w700),
        rect.topLeft.translate(5, 3),
        anchor: Offset.zero,
      );
      if (known && amount > 0) {
        paintText(
          canvas,
          compactAmount(amount),
          small.copyWith(color: ink, fontSize: 10),
          rect.bottomCenter.translate(0, -4),
          anchor: const Offset(0.5, 1),
          maxWidth: rect.width,
        );
      }
      if (!known) {
        canvas.drawRRect(
          box,
          Paint()..color = Colors.white.withValues(alpha: 0.4),
        );
      }
      if (day == selected) {
        canvas.drawRRect(
          box.inflate(1),
          Paint()
            ..color = outline
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_CalendarPainter old) =>
      old.selected != selected || old.days != days || old.text != text;
}

class _Legend extends StatelessWidget {
  const _Legend({required this.empty});

  final Color empty;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text('少', style: style),
        for (var shade = 0; shade <= 4; shade++)
          Container(
            width: 14,
            height: 14,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: _shadeColor(shade, empty),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        Text('多', style: style),
      ],
    );
  }
}

class _DayDetail extends StatelessWidget {
  const _DayDetail({
    required this.date,
    required this.amount,
    required this.average,
  });

  final DateTime date;
  final int amount;
  final int average;

  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final weekday = _weekdays[date.weekday - 1];
    final difference = average == 0 ? 0 : (amount - average) * 100 ~/ average;
    final compared = difference >= 0
        ? '比日均多 $difference%'
        : '比日均少 ${-difference}%';
    return Card.filled(
      child: ListTile(
        title: Text('${date.month}月${date.day}日（$weekday）'),
        subtitle: Text(compared),
        trailing: Text(
          groupDigits(amount),
          style: theme.textTheme.titleMedium?.copyWith(
            color: ChartColors.expense,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
