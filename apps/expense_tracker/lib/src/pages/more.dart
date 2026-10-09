import 'package:flutter/material.dart';

import '../demo/ledger.dart';
import '../look/figures.dart';
import '../look/glyphs.dart';
import '../look/theme.dart';
import '../look/widgets.dart';
import 'nav.dart';

/// 更多: the four tools used most, each with its headline figure, then
/// categories and settings as a short list.
class MorePage extends StatelessWidget {
  const MorePage({super.key, required this.ledger, required this.nav});

  final Ledger ledger;
  final Nav nav;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ledger,
      builder: (context, _) {
        final today = ledger.today;
        final income = ledger.income(today.year, today.month);
        final expense = ledger.expense(today.year, today.month);
        final budget = ledger.budgetFor(Ledger.allSpending).limit;
        final gain = ledger.investValue - ledger.investCost;
        final due = ledger.due.length;
        final soon = ledger.upcoming.length;
        final tools = [
          (
            Pages.reports,
            '財務報表',
            Glyph.reports,
            '本月結餘 ${money(income - expense)}',
          ),
          (
            Pages.investments,
            '投資與股息',
            Glyph.investment,
            '未實現 ${moneySigned(gain)}',
          ),
          (Pages.budgets, '預算管理', Glyph.budget, '剩 ${money(budget - expense)}'),
          (
            Pages.recurring,
            '定期交易',
            Glyph.recurring,
            due > 0 ? '$due 筆已到期' : '$soon 筆即將扣款',
          ),
        ];
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          children: [
            const PageHeader('更多'),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.9,
              children: [
                for (final (page, name, icon, detail) in tools)
                  SoftPanel(
                    color: Hue.white,
                    padding: const EdgeInsets.all(12),
                    onTap: () => nav.open(page),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        IconBadge(icon, Hue.positive, size: 30),
                        const Spacer(),
                        Text(
                          name,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
            const SizedBox(height: 18),
            for (final (page, name, icon) in const [
              (Pages.categories, '分類管理', Glyph.categories),
              (Pages.settings, '設定與資料', Glyph.sliders),
            ])
              InkWell(
                onTap: () => nav.open(page),
                child: Container(
                  height: 54,
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: Hue.line)),
                  ),
                  child: Row(
                    children: [
                      GlyphIcon(icon, color: Hue.muted),
                      const SizedBox(width: 12),
                      Text(name, style: const TextStyle(fontSize: 15)),
                      const Spacer(),
                      const GlyphIcon(Glyph.next, size: 16, color: Hue.faint),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
