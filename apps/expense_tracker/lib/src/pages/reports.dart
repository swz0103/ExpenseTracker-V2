import 'dart:math';

import 'package:flutter/material.dart';

import '../charts/bar_scale.dart';
import '../demo/ledger.dart';
import '../look/figures.dart';
import '../look/glyphs.dart';
import '../look/icons.dart';
import '../look/theme.dart';
import '../look/widgets.dart';
import 'nav.dart';

/// 財務報表: the month's balance and how its spending moved against the
/// month before, by category.
class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key, required this.ledger, required this.nav});

  final Ledger ledger;
  final Nav nav;

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  late var _month = (widget.ledger.today.year, widget.ledger.today.month);

  @override
  Widget build(BuildContext context) {
    final ledger = widget.ledger;
    return ListenableBuilder(
      listenable: ledger,
      builder: (context, _) {
        final (year, month) = _month;
        final today = ledger.today;
        final current = year == today.year && month == today.month;
        final before = DateTime.utc(year, month - 1);
        final income = ledger.income(year, month);
        final expense = ledger.expense(year, month);
        final left = income - expense;
        final rate = income == 0 ? 0 : (left * 100 / income).round();
        final previous = ledger.expense(before.year, before.month);
        final change = expense - previous;
        final now = {
          for (final (c, amount) in ledger.expenseByCategory(year, month))
            c.name: amount,
        };
        final then = {
          for (final (c, amount) in ledger.expenseByCategory(
            before.year,
            before.month,
          ))
            c.name: amount,
        };
        final names = {...now.keys, ...then.keys}.toList();
        final rows = [
          for (final name in names)
            (
              ledger.category(name),
              now[name] ?? 0,
              (now[name] ?? 0) - (then[name] ?? 0),
            ),
        ]..sort((a, b) => b.$3.abs().compareTo(a.$3.abs()));
        final largest = rows.fold(0, (m, r) => max(m, r.$3.abs()));
        final scope = current
            ? '至 ${today.day} 日支出 · 較 ${before.month} 月'
            : '$month 月支出 · 較 ${before.month} 月';
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 0, 20, 32),
          children: [
            PageHeader(
              '財務報表',
              onBack: widget.nav.back,
              trailing: MonthSwitch(
                month: _month,
                latest: (today.year, today.month),
                onChanged: (m) => setState(() => _month = m),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('本月結餘', style: TextStyle(color: Hue.muted)),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      const Text(
                        'TWD ',
                        style: TextStyle(fontSize: 12, color: Hue.muted),
                      ),
                      Text(
                        money(left),
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w600,
                          color: left < 0 ? Hue.negative : Hue.positive,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Hue.mist,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '結餘率 $rate%',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Hue.positive,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Figure(
                          '● 收入',
                          money(income),
                          color: Hue.positive,
                          size: 20,
                        ),
                      ),
                      Figure(
                        '支出 ●',
                        money(expense),
                        color: Hue.negative,
                        size: 20,
                        end: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Rail(income: income, expense: expense),
                  const SizedBox(height: 16),
                  SoftPanel(
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Text(
                              scope,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Hue.muted,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              change <= 0
                                  ? '減少 ${money(-change)}'
                                  : '增加 ${money(change)}',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: change <= 0
                                    ? Hue.positive
                                    : Hue.negative,
                              ),
                            ),
                          ],
                        ),
                        if (rows.isNotEmpty) ...[
                          const Divider(height: 20),
                          Row(
                            children: [
                              const Text(
                                '主要變動',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Hue.muted,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                rows.first.$1.name,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                moneySigned(rows.first.$3),
                                style: const TextStyle(fontSize: 13),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SectionHead(
                    '分類變化',
                    trailing: Text(
                      '較上月增減',
                      style: TextStyle(fontSize: 12, color: Hue.muted),
                    ),
                  ),
                  const Row(
                    children: [
                      SizedBox(width: 110),
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '減少',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Hue.muted,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                '增加',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Hue.muted,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: 80),
                    ],
                  ),
                  for (final (category, amount, diff) in rows)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: const BoxDecoration(
                        border: Border(bottom: BorderSide(color: Hue.line)),
                      ),
                      child: Row(
                        children: [
                          GlyphIcon(
                            iconFor(category.icon),
                            size: 20,
                            color: category.color,
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 82,
                            child: Text(
                              category.name,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Expanded(
                            child: AxisBar(
                              value: diff,
                              largest: largest,
                              positive: Hue.negative,
                              negative: Hue.positive,
                              height: 12,
                            ),
                          ),
                          SizedBox(
                            width: 80,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  money(amount),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Hue.negative,
                                  ),
                                ),
                                Text(
                                  moneySigned(diff),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Hue.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
