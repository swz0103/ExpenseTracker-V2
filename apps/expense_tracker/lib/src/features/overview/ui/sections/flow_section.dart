import 'package:flutter/material.dart';

import '../../../../core/charts/flow_chart.dart';
import '../../../../core/look/figures.dart';
import '../../../../core/look/theme.dart';
import '../../../../core/look/widgets.dart';
import '../../../../core/ledger/ledger.dart';

/// 收支對照: six months of income and spending up to the page's month,
/// with net worth as a line; a tap on a month reads it out.
class FlowSection extends StatefulWidget {
  const FlowSection({super.key, required this.ledger, required this.month});

  final Ledger ledger;

  /// The last of the six months.
  final (int, int) month;

  @override
  State<FlowSection> createState() => _FlowSectionState();
}

class _FlowSectionState extends State<FlowSection> {
  int? _flowMonth;

  /// The six months last worked out, and what they were worked out from:
  /// the ledger and its revision, the page's month and today. Hiding the amounts
  /// or a tap on a month keeps them, so they are not worked out again and
  /// the chart keeps its paint.
  List<FlowMonth>? _months;
  (Ledger, int, (int, int), DateTime)? _monthsKey;

  List<FlowMonth> _sixMonths(Ledger ledger, DateTime today) {
    final key = (ledger, ledger.revision, widget.month, today);
    final kept = _months;
    if (kept != null && key == _monthsKey) return kept;
    final (year, month) = widget.month;
    final months = <FlowMonth>[];
    for (var back = 5; back >= 0; back--) {
      final first = DateTime.utc(year, month - back);
      final end = DateTime.utc(first.year, first.month + 1, 0);
      final until = end.isAfter(today) ? today : end;
      months.add(
        FlowMonth(
          '${first.month}月',
          ledger.income(first.year, first.month),
          ledger.expense(first.year, first.month),
          ledger.netWorthAt(until),
        ),
      );
    }
    _monthsKey = key;
    return _months = List.unmodifiable(months);
  }

  @override
  void didUpdateWidget(FlowSection old) {
    super.didUpdateWidget(old);
    // Another month above: read out its own month again.
    if (widget.month != old.month) _flowMonth = null;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.ledger,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _flow(),
      ),
    );
  }

  List<Widget> _flow() {
    final ledger = widget.ledger;
    final (year, month) = widget.month;
    final today = ledger.today;
    final months = _sixMonths(ledger, today);
    final picked = (_flowMonth ?? months.length - 1).clamp(0, 5);
    final shown = months[picked];
    final shownMonth = DateTime.utc(year, month - 5 + picked);
    final current =
        shownMonth.year == today.year && shownMonth.month == today.month;
    final scope = current
        ? '${shownMonth.month}月 · ${today.day}日止'
        : '${shownMonth.month}月';
    final left = shown.income - shown.expense;
    return [
      const SectionHead('收支對照', trailing: Text('近六個月', style: mutedSmall)),
      Row(
        children: [
          Expanded(
            child: Text(
              scope,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
          Text(
            '結餘 ${ledger.money(left)}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: left < 0 ? Hue.negative : Hue.ink,
            ),
          ),
        ],
      ),
      const SizedBox(height: 4),
      // Wraps to a second line when the phone's text is large.
      Wrap(
        spacing: 12,
        runSpacing: 4,
        children: [
          for (final (color, name, value, line) in [
            (Hue.positive, '收入', shown.income, false),
            (Hue.negative, '支出', shown.expense, false),
            (Hue.investment, '淨資產', shown.worth, true),
          ])
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                LegendKey(color, name, line: line),
                Text(' ${ledger.money(value)}', style: mutedSmall),
              ],
            ),
        ],
      ),
      const SizedBox(height: 10),
      Semantics(
        container: true,
        label: [
          for (final m in months)
            '${m.label} 收入 ${ledger.money(m.income)}，'
                '支出 ${ledger.money(m.expense)}',
        ].join('；'),
        child: FlowChart(
          months: months,
          selected: picked,
          onSelect: (index) => setState(() => _flowMonth = index),
          hidden: ledger.hidden,
        ),
      ),
    ];
  }
}
