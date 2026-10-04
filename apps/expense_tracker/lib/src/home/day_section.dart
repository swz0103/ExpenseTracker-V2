import 'dart:math';

import 'package:flutter/material.dart';

import '../charts/chart_data.dart';
import '../charts/chart_parts.dart';
import '../theme.dart';
import 'home_data.dart';
import 'section.dart';

/// The last seven days as dots sized by spending, and the entries of the
/// chosen day (today at first). Only the first few entries show until
/// asked for more.
class DaySection extends StatefulWidget {
  const DaySection({super.key, required this.data});

  final HomeData data;

  @override
  State<DaySection> createState() => _DaySectionState();
}

class _DaySectionState extends State<DaySection> {
  late int _day = widget.data.week.length - 1;
  var _all = false;

  static const _shown = 3;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final week = widget.data.week;
    final day = week[_day];
    final muted = text.bodySmall?.copyWith(color: Palette.muted);
    final entries = _all ? day.entries : day.entries.take(_shown).toList();
    return Section(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeading(
            dayLabel(day.date),
            trailing: '支出 ${groupDigits(day.spent)}',
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              return GestureDetector(
                onTapUp: (details) {
                  final column = details.localPosition.dx ~/ (width / 7);
                  final index = column.clamp(0, week.length - 1);
                  if (index == _day) return;
                  setState(() {
                    _day = index;
                    _all = false;
                  });
                },
                child: CustomPaint(
                  size: Size(width, 64),
                  painter: _WeekPainter(
                    spent: [for (final d in week) d.spent],
                    dates: [for (final d in week) d.date],
                    selected: _day,
                    label: text.labelSmall!,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          if (day.entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text('這天沒有記帳', style: muted),
            ),
          for (final (i, entry) in entries.indexed) ...[
            if (i > 0) const Divider(),
            _EntryRow(entry),
          ],
          if (!_all && day.entries.length > _shown)
            TextButton(
              onPressed: () => setState(() => _all = true),
              style: TextButton.styleFrom(
                foregroundColor: Palette.muted,
                padding: EdgeInsets.zero,
              ),
              child: Text('顯示全部 ${day.entries.length} 筆'),
            ),
        ],
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow(this.entry);

  final Entry entry;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: Palette.muted);
    final where = entry.place.isEmpty ? '' : '・${entry.place}';
    final amount = groupDigits(entry.amount);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${entry.title}$where', style: text.bodyMedium),
                Text('${entry.category}・${entry.account}', style: muted),
              ],
            ),
          ),
          Text(
            entry.income ? '+$amount' : amount,
            style: text.bodyLarge?.copyWith(
              color: entry.income ? Palette.olive : Palette.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _WeekPainter extends CustomPainter {
  _WeekPainter({
    required this.spent,
    required this.dates,
    required this.selected,
    required this.label,
  });

  final List<int> spent;
  final List<DateTime> dates;
  final int selected;
  final TextStyle label;

  @override
  void paint(Canvas canvas, Size size) {
    final column = size.width / spent.length;
    final largest = min(column / 2 - 6, 17.0);
    final scale = weekScale(spent);
    final middle = (size.height - 18) / 2;
    for (final (i, amount) in spent.indexed) {
      final centre = Offset(column * (i + 0.5), middle);
      final picked = i == selected;
      if (amount <= 0) {
        canvas.drawCircle(
          centre,
          3,
          Paint()
            ..color = Palette.line
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      } else {
        final share = min(1.0, amount / scale);
        final radius = max(3.0, largest * sqrt(share));
        final color = picked ? Palette.ink : const Color(0xFFDDD5CA);
        canvas.drawCircle(centre, radius, Paint()..color = color);
      }
      final name = weekdayNames[dates[i].weekday - 1];
      paintText(
        canvas,
        i == spent.length - 1 ? '今' : name,
        label.copyWith(
          color: picked ? Palette.ink : Palette.muted,
          fontWeight: picked ? FontWeight.w700 : FontWeight.w400,
        ),
        Offset(centre.dx, size.height),
        anchor: const Offset(0.5, 1),
      );
    }
  }

  @override
  bool shouldRepaint(_WeekPainter old) =>
      old.selected != selected || old.spent != spent;
}

/// The amount drawn as the largest dot. One very large day, such as rent,
/// is capped at twice the next largest so the other days stay readable.
int weekScale(List<int> spent) {
  final sorted = [...spent]..sort();
  if (sorted.isEmpty || sorted.last <= 0) return 1;
  if (sorted.length < 2 || sorted[sorted.length - 2] <= 0) return sorted.last;
  return min(sorted.last, sorted[sorted.length - 2] * 2);
}
