import 'package:flutter/material.dart';

import '../charts/budget_bar.dart';
import '../demo/ledger.dart';
import '../look/figures.dart';
import '../look/glyphs.dart';
import '../look/icons.dart';
import '../look/theme.dart';
import '../look/widgets.dart';
import 'dialogs.dart';
import 'nav.dart';

/// 預算管理: what is left of the month's budget, then each category's
/// allowance, most urgent first.
class BudgetsPage extends StatefulWidget {
  const BudgetsPage({super.key, required this.ledger, required this.nav});

  final Ledger ledger;
  final Nav nav;

  @override
  State<BudgetsPage> createState() => _BudgetsPageState();
}

class _BudgetsPageState extends State<BudgetsPage> {
  late var _month = (widget.ledger.today.year, widget.ledger.today.month);

  Future<void> _edit(String category, int limit) async {
    final title = category == Ledger.allSpending ? '總預算' : '$category 額度';
    final value = await askAmount(context, title, initial: limit);
    if (value != null && value >= 0) {
      widget.ledger.setBudget(category, value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ledger = widget.ledger;
    return ListenableBuilder(
      listenable: ledger,
      builder: (context, _) {
        final (year, month) = _month;
        final spent = ledger.expense(year, month);
        final total = ledger.budgetFor(Ledger.allSpending).limit;
        final used = {
          for (final (c, amount) in ledger.expenseByCategory(year, month))
            c.name: amount,
        };
        final rows = [
          for (final b in ledger.budgets)
            if (b.category != Ledger.allSpending) (b, used[b.category] ?? 0),
        ];
        // Overspent first, then by the share used.
        rows.sort((a, b) {
          double share((Budget, int) row) =>
              row.$1.limit == 0 ? 0 : row.$2 / row.$1.limit;
          return share(b).compareTo(share(a));
        });
        final left = total - spent;
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 0, 20, 32),
          children: [
            PageHeader(
              '預算管理',
              onBack: widget.nav.back,
              trailing: MonthSwitch(
                month: _month,
                latest: (ledger.today.year, ledger.today.month),
                onChanged: (m) => setState(() => _month = m),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SoftPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    left < 0 ? '本月超支' : '本月剩餘',
                                    style: const TextStyle(color: Hue.muted),
                                  ),
                                  Text(
                                    'TWD ${money(left.abs())}',
                                    style: TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.w600,
                                      color: left < 0
                                          ? Hue.negative
                                          : Hue.positive,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            InkWell(
                              onTap: () => _edit(Ledger.allSpending, total),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  const Row(
                                    children: [
                                      Text(
                                        '總預算 ',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Hue.muted,
                                        ),
                                      ),
                                      GlyphIcon(Glyph.edit, size: 14),
                                    ],
                                  ),
                                  Text(
                                    money(total),
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        BudgetBar(
                          pieces: [(const Color(0xFF6B8C6B), spent)],
                          limit: total,
                          height: 12,
                        ),
                        Text(
                          '已用 ${money(spent)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Hue.negative,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SectionHead('分類額度'),
                  for (final (budget, amount) in rows)
                    _CategoryLimit(
                      category: ledger.category(budget.category),
                      limit: budget.limit,
                      used: amount,
                      onEdit: () => _edit(budget.category, budget.limit),
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

class _CategoryLimit extends StatelessWidget {
  const _CategoryLimit({
    required this.category,
    required this.limit,
    required this.used,
    required this.onEdit,
  });

  final Category category;
  final int limit;
  final int used;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final left = limit - used;
    final share = limit == 0 ? 1.0 : (used / limit).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Hue.line)),
      ),
      child: Row(
        children: [
          IconBadge(iconFor(category.icon), category.color, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              children: [
                Row(
                  children: [
                    Text(
                      category.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      left < 0 ? '超支 ' : '剩餘 ',
                      style: const TextStyle(fontSize: 12, color: Hue.muted),
                    ),
                    Text(
                      money(left.abs()),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: left < 0 ? Hue.negative : Hue.ink,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: share,
                          minHeight: 5,
                          color: left < 0 ? Hue.negative : category.color,
                          backgroundColor: const Color(0xFFE6E0D2),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      money(limit),
                      style: const TextStyle(fontSize: 12, color: Hue.muted),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '調整額度',
            onPressed: onEdit,
            icon: const GlyphIcon(Glyph.edit, size: 18, color: Hue.muted),
          ),
        ],
      ),
    );
  }
}
