import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/look/figures.dart';
import '../../../core/look/icons.dart';
import '../../../core/look/theme.dart';
import '../../../core/look/widgets.dart';
import '../../../core/ledger/ledger.dart';
import '../model/comparison.dart';
import 'report_period.dart';

/// What the period is set against.
enum _Against {
  previous('上一期'),
  lastYear('去年同期'),
  custom('自訂');

  const _Against(this.label);

  final String label;
}

/// 比較, on the page itself: the period so far against the same number
/// of days just before it, the same days a year before, or days the
/// person picks. Income, spending and what was left as paired bars, then
/// the categories that moved the most, more to the right and less to
/// the left of a middle line.
class CompareSection extends StatefulWidget {
  const CompareSection({super.key, required this.ledger, required this.period});

  final Ledger ledger;
  final ReportPeriod period;

  @override
  State<CompareSection> createState() => _CompareSectionState();
}

class _CompareSectionState extends State<CompareSection> {
  var _against = _Against.previous;
  DateTimeRange? _custom;

  DateTime get _today {
    final t = widget.ledger.today;
    return DateTime.utc(t.year, t.month, t.day);
  }

  static DateTime _day(DateTime d) => DateTime.utc(d.year, d.month, d.day);

  /// The same day a year earlier, the 29th of February becoming the 28th.
  static DateTime _yearBefore(DateTime day) => DateTime.utc(
    day.year - 1,
    day.month,
    min(day.day, DateTime.utc(day.year - 1, day.month + 1, 0).day),
  );

  /// The period's days so far.
  (DateTime, DateTime) get _first {
    final period = widget.period;
    final today = _today;
    return (period.from, period.to.isAfter(today) ? today : period.to);
  }

  /// The days set against it, as long as the period has run so far.
  (DateTime, DateTime) get _second {
    final (from, to) = _first;
    final custom = _custom;
    switch (_against) {
      case _Against.previous:
        final before = widget.period.step(-1);
        final end = before.from.add(to.difference(from));
        return (before.from, end.isAfter(before.to) ? before.to : end);
      case _Against.lastYear:
        return (_yearBefore(from), _yearBefore(to));
      case _Against.custom:
        if (custom == null) return (_yearBefore(from), _yearBefore(to));
        return (_day(custom.start), _day(custom.end));
    }
  }

  Future<void> _choose(_Against against) async {
    if (against != _Against.custom) {
      setState(() => _against = against);
      return;
    }
    final ledger = widget.ledger;
    final today = _today;
    final first = ledger.firstDay.isAfter(today) ? today : ledger.firstDay;
    final (from, to) = _second;
    final picked = await pickDateRange(
      context,
      first: first,
      last: today,
      initial: from.isBefore(first) || to.isAfter(today)
          ? null
          : DateTimeRange(start: from, end: to),
      title: '要比較的期間',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _against = _Against.custom;
      _custom = picked;
    });
  }

  static String _span((DateTime, DateTime) days) {
    final (from, to) = days;
    return from.year == to.year
        ? '${from.month}/${from.day}–${to.month}/${to.day}'
        : '${from.year}/${from.month}/${from.day}–${to.year}/${to.month}/${to.day}';
  }

  @override
  Widget build(BuildContext context) {
    final ledger = widget.ledger;
    final first = _first;
    final second = _second;
    final a = sumsBetween(ledger, first.$1, first.$2);
    final b = sumsBetween(ledger, second.$1, second.$2);
    final rows = compare(a, b);
    final largest = [
      a.income,
      b.income,
      a.expense,
      b.expense,
      a.left.abs(),
      b.left.abs(),
    ].fold(1, max);
    final moved = [
      for (final row in rows.skip(3))
        if (row.$2 != row.$3) row,
    ].take(5).toList();
    String then(String label) =>
        _against == _Against.custom ? '自訂' : label.replaceAll('同期', '');
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: Hue.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: Hue.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Hue.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                for (final against in _Against.values)
                  Expanded(
                    child: Semantics(
                      selected: against == _against,
                      button: true,
                      child: Material(
                        color: against == _against
                            ? Hue.white
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(11),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(11),
                          onTap: () => _choose(against),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 44),
                            child: Center(
                              child: Text(
                                against == _Against.custom && _custom != null
                                    ? _span(second)
                                    : against.label,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: against == _against
                                      ? Hue.ink
                                      : Hue.muted,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          for (final (name, now, before) in rows.take(3))
            _Pair(
              ledger: ledger,
              name: name,
              now: now,
              then: before,
              thenLabel: then(_against.label),
              largest: largest,
              color: switch (name) {
                '收入' => Hue.positive,
                '支出' => Hue.negative,
                _ => Hue.accent,
              },
            ),
          if (moved.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              '變化最多的分類',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (name, now, before) in moved)
                  _MovedChip(
                    ledger: ledger,
                    category: ledger.category(name),
                    change: now - before,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 收入, 支出 or 結餘: its name and both amounts on a line, then the
/// period's bar in its colour over the other's, paler.
class _Pair extends StatelessWidget {
  const _Pair({
    required this.ledger,
    required this.name,
    required this.now,
    required this.then,
    required this.thenLabel,
    required this.largest,
    required this.color,
  });

  final Ledger ledger;
  final String name;
  final int now;
  final int then;
  final String thenLabel;
  final int largest;
  final Color color;

  @override
  Widget build(BuildContext context) {
    Widget bar(int value, Color tone) => ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: SizedBox(
        height: 9,
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: (value.abs() / largest).clamp(0.02, 1.0),
            child: ColoredBox(color: tone, child: const SizedBox.expand()),
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 12,
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: ledger.orDots(groupDigits(now)),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    TextSpan(
                      text: ' ／$thenLabel ${ledger.orDots(groupDigits(then))}',
                      style: mutedSmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          bar(now, color),
          const SizedBox(height: 4),
          bar(then, tintOf(color, 0.4)),
        ],
      ),
    );
  }
}

/// A category that moved most, as a chip in its colour: its icon, name
/// and the change, red for more spent and green for less.
class _MovedChip extends StatelessWidget {
  const _MovedChip({
    required this.ledger,
    required this.category,
    required this.change,
  });

  final Ledger ledger;
  final Category category;
  final int change;

  @override
  Widget build(BuildContext context) {
    final color = shownColor(category.color);
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
      decoration: BoxDecoration(
        color: tintOf(color, 0.22),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SquareIcon(iconFor(category.icon), color, size: 28),
          const SizedBox(width: 8),
          Text(
            category.name,
            style: TextStyle(fontWeight: FontWeight.w800, color: deepOf(color)),
          ),
          const SizedBox(width: 8),
          Text(
            ledger.orDots(signed(change)),
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: change > 0 ? Hue.negative : Hue.positive,
            ),
          ),
        ],
      ),
    );
  }
}
