import 'package:flutter/material.dart';

import '../../../core/look/figures.dart';
import '../../../core/look/theme.dart';
import '../../../core/look/widgets.dart';
import '../../../core/ledger/ledger.dart';
import '../model/comparison.dart';
import 'report_period.dart';

/// 與另一段比較: asks for a second stretch of days (the period before by
/// default), then sets the two side by side: income, spending, what was
/// left, and each category, the largest difference first.
Future<void> showComparison(
  BuildContext context,
  Ledger ledger,
  ReportPeriod period,
) async {
  final today = ledger.today;
  DateTime clamp(DateTime d) => d.isAfter(today) ? today : d;
  final first = ledger.firstDay.isAfter(today) ? today : ledger.firstDay;
  final before = period.step(-1);
  final start = before.from.isBefore(first) ? first : before.from;
  final end = clamp(before.to);
  final picked = await showDateRangePicker(
    context: context,
    firstDate: first,
    lastDate: today,
    initialDateRange: start.isAfter(end)
        ? null
        : DateTimeRange(start: start, end: end),
    helpText: '選擇要比較的期間',
  );
  if (picked == null || !context.mounted) return;
  final aTo = clamp(period.to);
  final a = sumsBetween(ledger, period.from, aTo);
  final bFrom = DateTime.utc(
    picked.start.year,
    picked.start.month,
    picked.start.day,
  );
  final bTo = DateTime.utc(picked.end.year, picked.end.month, picked.end.day);
  final b = sumsBetween(ledger, bFrom, bTo);
  String label(DateTime from, DateTime to) =>
      '${from.year}/${from.month}/${from.day}–${to.year}/${to.month}/${to.day}';
  await showSheet<void>(
    context,
    (context) => _Comparison(
      ledger: ledger,
      first: label(period.from, aTo),
      second: label(bFrom, bTo),
      rows: compare(a, b),
    ),
  );
}

class _Comparison extends StatelessWidget {
  const _Comparison({
    required this.ledger,
    required this.first,
    required this.second,
    required this.rows,
  });

  final Ledger ledger;
  final String first;
  final String second;
  final List<CompareRow> rows;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.8,
      ),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          const Text(
            '期間比較',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text('A：$first', style: mutedSmall, textAlign: TextAlign.center),
          Text('B：$second', style: mutedSmall, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          SoftPanel(
            color: Hue.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Column(
              children: [
                const _Line('', 'A', 'B', '差（A−B）', head: true),
                for (final (i, (name, a, b)) in rows.indexed)
                  _Line(
                    name,
                    ledger.money(a),
                    ledger.money(b),
                    ledger.moneySigned(a - b),
                    // Below income, spending and what was left: categories.
                    rule: i == 3,
                    tone: a == b
                        ? Hue.muted
                        : (name == '收入' || name == '結餘') == (a > b)
                        ? Hue.positive
                        : Hue.negative,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A row of the comparison: what, A, B and the difference.
class _Line extends StatelessWidget {
  const _Line(
    this.name,
    this.a,
    this.b,
    this.difference, {
    this.head = false,
    this.rule = false,
    this.tone = Hue.ink,
  });

  final String name;
  final String a;
  final String b;
  final String difference;
  final bool head;
  final bool rule;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final style = head
        ? mutedSmall
        : const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: rule ? ruleAbove : null,
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: head ? mutedSmall : null,
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(a, textAlign: TextAlign.end, style: style),
          ),
          Expanded(
            flex: 3,
            child: Text(b, textAlign: TextAlign.end, style: style),
          ),
          Expanded(
            flex: 4,
            child: Text(
              difference,
              textAlign: TextAlign.end,
              style: head ? mutedSmall : style.copyWith(color: tone),
            ),
          ),
        ],
      ),
    );
  }
}
