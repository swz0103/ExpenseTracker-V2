import 'dart:math';

import 'package:flutter/material.dart';

import '../charts/chart_data.dart';
import '../charts/chart_parts.dart';
import '../theme.dart';
import 'home_data.dart';
import 'section.dart';

/// This month at a glance: what was spent against the budget, and a
/// small pace line. Tap to open the line, drag along it to read any day,
/// and see income, balance and a month-end estimate.
class MonthSection extends StatefulWidget {
  const MonthSection({super.key, required this.data});

  final HomeData data;

  @override
  State<MonthSection> createState() => _MonthSectionState();
}

class _MonthSectionState extends State<MonthSection> {
  var _open = false;
  int? _day;

  void _scrub(Offset position, double width) {
    final days = widget.data.daysInMonth;
    final day = (position.dx / width * days).ceil().clamp(1, days);
    final last = max(1, widget.data.days.length);
    final known = day.clamp(1, last);
    if (known != _day) setState(() => _day = known);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final data = widget.data;
    final month = data.month;
    final spent = month.expense;
    final used = (spent * 100 / data.budget).round();
    final estimate = monthEstimate(data.days, data.daysInMonth);
    final muted = text.bodySmall?.copyWith(color: Palette.muted);
    final gap = groupDigits((estimate - data.budget).abs());
    final pace = estimate > data.budget
        ? '照目前速度，月底會超出預算 $gap'
        : '照目前速度，月底還剩 $gap';
    final left = data.budget - spent;
    return Section(
      onTap: () => setState(() {
        _open = !_open;
        _day = null;
      }),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeading(
            '${month.month}月支出',
            trailing: left >= 0
                ? '預算剩 ${groupDigits(left)}'
                : '超出 ${groupDigits(-left)}',
          ),
          const SizedBox(height: 6),
          Text(
            groupDigits(spent),
            style: text.displaySmall?.copyWith(
              fontWeight: FontWeight.w300,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 14),
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: SizedBox(
              height: _open ? 132 : 36,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  void scrub(Offset at) => _scrub(at, width);
                  return GestureDetector(
                    onTapDown: _open ? (d) => scrub(d.localPosition) : null,
                    onHorizontalDragUpdate: _open
                        ? (d) => scrub(d.localPosition)
                        : null,
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: PacePainter(
                        days: data.days,
                        length: data.daysInMonth,
                        budget: data.budget,
                        open: _open,
                        day: _day,
                        month: month.month,
                        label: text.labelSmall!,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          if (_open) ...[
            const SizedBox(height: 18),
            Row(
              children: [
                _Figure('收入', month.income),
                _Figure('結餘', month.net),
                _Figure('月底預估', estimate),
              ],
            ),
            const SizedBox(height: 10),
            Text('已用預算 $used%。$pace', style: muted),
          ],
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure(this.label, this.amount);

  final String label;
  final int amount;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: text.labelSmall?.copyWith(color: Palette.muted)),
          const SizedBox(height: 2),
          Text(
            groupDigits(amount),
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w400),
          ),
        ],
      ),
    );
  }
}

/// Spending added up day by day against an even pace to the budget.
class PacePainter extends CustomPainter {
  PacePainter({
    required this.days,
    required this.length,
    required this.budget,
    required this.open,
    required this.day,
    required this.month,
    required this.label,
  });

  final List<int> days;

  /// Days in the month.
  final int length;
  final int budget;
  final bool open;
  final int? day;
  final int month;
  final TextStyle label;

  @override
  void paint(Canvas canvas, Size size) {
    final totals = <int>[];
    var running = 0;
    for (final amount in days) {
      running += amount;
      totals.add(running);
    }
    final spent = running;
    final estimate = monthEstimate(days, length);
    final top = [budget, spent, if (open) estimate].reduce(max) * 1.08;
    final bottom = size.height - (open ? 16 : 2);
    double x(int day) => size.width * day / length;
    double y(num value) => bottom - (bottom - 4) * value / top;

    // The even pace: where spending would be if the budget were spread
    // evenly over the month.
    _dashed(
      canvas,
      Offset(0, y(0)),
      Offset(size.width, y(budget)),
      Paint()
        ..color = Palette.muted.withValues(alpha: 0.6)
        ..strokeWidth = 1,
    );
    canvas.drawLine(
      Offset(0, bottom),
      Offset(size.width, bottom),
      Paint()..color = Palette.line,
    );
    if (totals.isEmpty) return;

    final line = Path()..moveTo(0, y(0));
    for (final (i, total) in totals.indexed) {
      line.lineTo(x(i + 1), y(total));
    }
    final end = Offset(x(totals.length), y(spent));
    final area = Path.from(line)
      ..lineTo(end.dx, bottom)
      ..lineTo(0, bottom)
      ..close();
    canvas.drawPath(
      area,
      Paint()..color = Palette.ink.withValues(alpha: 0.04),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = Palette.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round,
    );
    final ahead = spent > budget * totals.length / length;
    final dot = ahead ? Palette.clay : Palette.ink;
    canvas.drawCircle(end, 3.5, Paint()..color = dot);

    if (!open) return;
    _dashed(
      canvas,
      end,
      Offset(size.width, y(estimate)),
      Paint()
        ..color = Palette.muted.withValues(alpha: 0.7)
        ..strokeWidth = 1,
    );
    final muted = label.copyWith(color: Palette.muted);
    paintText(
      canvas,
      '預算 ${compactAmount(budget)}',
      muted,
      Offset(size.width, y(budget) - 4),
      anchor: const Offset(1, 1),
    );
    paintText(
      canvas,
      '$month/1',
      muted,
      Offset(0, bottom + 3),
      anchor: Offset.zero,
    );
    paintText(
      canvas,
      '$month/$length',
      muted,
      Offset(size.width, bottom + 3),
      anchor: const Offset(1, 0),
    );

    final picked = day;
    if (picked == null) return;
    final at = Offset(x(picked), y(totals[picked - 1]));
    canvas.drawLine(
      Offset(at.dx, 0),
      Offset(at.dx, bottom),
      Paint()..color = Palette.ink.withValues(alpha: 0.25),
    );
    canvas.drawCircle(at, 4, Paint()..color = Palette.ink);
    final note = '$month/$picked 累計 ${groupDigits(totals[picked - 1])}';
    final right = at.dx > size.width / 2;
    paintText(
      canvas,
      note,
      label.copyWith(color: Palette.ink),
      Offset(at.dx + (right ? -6 : 6), 0),
      anchor: Offset(right ? 1 : 0, 0),
    );
  }

  @override
  bool shouldRepaint(PacePainter old) =>
      old.open != open || old.day != day || old.days != days;
}

/// Spent so far plus a typical (median) day for each day left, so one
/// large payment such as rent is not repeated over the rest of the month.
int monthEstimate(List<int> days, int length) {
  if (days.isEmpty) return 0;
  final sorted = [...days]..sort();
  final typical = sorted[sorted.length ~/ 2];
  final spent = days.fold(0, (a, b) => a + b);
  return spent + typical * (length - days.length);
}

void _dashed(Canvas canvas, Offset from, Offset to, Paint paint) {
  final length = (to - from).distance;
  if (length == 0) return;
  final step = (to - from) / length;
  for (var at = 0.0; at < length; at += 7) {
    final dash = min(4.0, length - at);
    canvas.drawLine(from + step * at, from + step * (at + dash), paint);
  }
}
