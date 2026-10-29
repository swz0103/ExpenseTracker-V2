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
    final picked = await showDateRangePicker(
      context: context,
      firstDate: first,
      lastDate: today,
      initialDateRange: from.isBefore(first) || to.isAfter(today)
          ? null
          : DateTimeRange(start: from, end: to),
      helpText: '選擇要比較的期間',
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
    final widest = moved.fold(1, (m, r) => max(m, (r.$2 - r.$3).abs()));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHead('比較'),
        Wrap(
          spacing: 8,
          children: [
            for (final against in _Against.values)
              ChoicePill(
                label: against == _Against.custom && _custom != null
                    ? _span(second)
                    : against.label,
                selected: against == _against,
                onTap: () => _choose(against),
              ),
          ],
        ),
        const SizedBox(height: 8),
        SoftPanel(
          color: Hue.white,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 14,
                children: [
                  LegendKey(Hue.accent, '本期 ${_span(first)}'),
                  LegendKey(Hue.faint, '${_against.label} ${_span(second)}'),
                ],
              ),
              for (final (name, now, then) in rows.take(3))
                _Measure(
                  ledger: ledger,
                  name: name,
                  now: now,
                  then: then,
                  largest: largest,
                  // More income or more left is better; more spending is not.
                  better: name != '支出',
                ),
              if (moved.isNotEmpty) ...[
                const SizedBox(height: 14),
                const Text('變化最多的分類', style: mutedSmall),
                const SizedBox(height: 4),
                for (final (name, now, then) in moved)
                  _Moved(
                    ledger: ledger,
                    category: ledger.category(name),
                    change: now - then,
                    widest: widest,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// 收入, 支出 or 結餘: the period's amount over its bar, the other's under.
class _Measure extends StatelessWidget {
  const _Measure({
    required this.ledger,
    required this.name,
    required this.now,
    required this.then,
    required this.largest,
    required this.better,
  });

  final Ledger ledger;
  final String name;
  final int now;
  final int then;
  final int largest;

  /// Whether more is better.
  final bool better;

  @override
  Widget build(BuildContext context) {
    final change = now - then;
    final tone = change == 0
        ? Hue.muted
        : (change > 0) == better
        ? Hue.positive
        : Hue.negative;
    final color = switch (name) {
      '收入' => Hue.positive,
      '支出' => Hue.negative,
      _ => Hue.accent,
    };
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              Text(
                ledger.money(now),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: now < 0 ? Hue.negative : Hue.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          PairBars(
            now: now.abs() / largest,
            then: then.abs() / largest,
            color: color,
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                ledger.money(then),
                style: const TextStyle(fontSize: 12.5, color: Hue.muted),
              ),
              const Spacer(),
              Text(
                then == 0
                    ? (now == 0 ? '持平' : '—')
                    : percentOf(change, then.abs()),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: tone,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A category that moved: its mark and name, a bar from the middle line,
/// right for more spent and left for less, and the difference.
class _Moved extends StatelessWidget {
  const _Moved({
    required this.ledger,
    required this.category,
    required this.change,
    required this.widest,
  });

  final Ledger ledger;
  final Category category;
  final int change;
  final int widest;

  @override
  Widget build(BuildContext context) {
    final more = change > 0;
    final tone = more ? Hue.negative : Hue.positive;
    final share = (change.abs() / widest).clamp(0.04, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          IconBadge(iconFor(category.icon), category.color, size: 26),
          const SizedBox(width: 8),
          SizedBox(
            width: 64,
            child: Text(
              category.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13.5),
            ),
          ),
          Expanded(
            child: SizedBox(
              height: 10,
              child: Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: more
                          ? null
                          : FractionallySizedBox(
                              widthFactor: share,
                              child: _bar(tone, left: true),
                            ),
                    ),
                  ),
                  Container(width: 1.5, height: 14, color: Hue.line),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: more
                          ? FractionallySizedBox(
                              widthFactor: share,
                              child: _bar(tone, left: false),
                            )
                          : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 76,
            child: Text(
              ledger.moneySigned(change),
              textAlign: TextAlign.end,
              maxLines: 1,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: tone,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _bar(Color color, {required bool left}) => Container(
    height: 10,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.horizontal(
        left: left ? const Radius.circular(5) : Radius.zero,
        right: left ? Radius.zero : const Radius.circular(5),
      ),
    ),
  );
}
