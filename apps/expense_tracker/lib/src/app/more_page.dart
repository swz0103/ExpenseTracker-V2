import 'package:flutter/material.dart';

import '../core/text/figures.dart';
import '../core/look/glyphs.dart';
import '../core/look/theme.dart';
import '../core/look/widgets.dart';
import '../core/ledger/ledger.dart';
import '../core/nav.dart';
import '../features/debts/ui/debts_page.dart';

/// 更多: the tools as big icon buttons, three to a row, in three groups,
/// each with one line on what it is about now.
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
        final due = ledger.due;
        final items = [...due, ...ledger.upcoming];
        final income = ledger.income(today.year, today.month);
        final expense = ledger.expense(today.year, today.month);
        final rate = income == 0 ? 0 : (income - expense) * 100 ~/ income;
        final limit = ledger.allowance(
          ledger.budgetFor(Ledger.allSpending),
          today.year,
          today.month,
        );
        final next = items.isEmpty ? null : items.first;
        final lent = peopleOwing(ledger)
            .fold<int>(0, (sum, a) => sum + owedFrom(ledger, a));
        final left = limit - expense;
        return HeadedList(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          header: const PageHeader('更多'),
          children: [
            const RuleHead('報表與投資'),
            _ToolRow([
              ToolButton(
                glyph: Glyph.reports,
                color: ToolHue.reports,
                label: '財務報表',
                detail: '結餘率 $rate%',
                onTap: () => nav.open(Pages.reports),
              ),
              ToolButton(
                glyph: Glyph.pie,
                color: ToolHue.investments,
                label: '投資與股息',
                detail: signed(ledger.investValue - ledger.investCost),
                onTap: () => nav.open(Pages.investments),
              ),
            ]),
            const RuleHead('預算與往來'),
            _ToolRow([
              ToolButton(
                glyph: Glyph.gauge,
                color: ToolHue.budgets,
                label: '預算管理',
                detail: limit == 0
                    ? '還沒設定'
                    : left < 0
                    ? '超支 ${groupDigits(-left)}'
                    : '剩 ${groupDigits(left)}',
                onTap: () => nav.open(Pages.budgets),
              ),
              ToolButton(
                glyph: Glyph.cycleCalendar,
                color: ToolHue.recurring,
                label: '定期交易',
                // What is due shows here, not as a tile of its own.
                detail: due.isNotEmpty
                    ? '${due.length} 筆到期'
                    : next == null
                    ? '沒有待扣款'
                    : '下一筆 ${ledger.nextLabel(next)}',
                onTap: () => nav.open(Pages.recurring),
              ),
              ToolButton(
                glyph: Glyph.swap,
                color: ToolHue.debts,
                label: '代墊與借貸',
                detail: lent == 0 ? '沒有欠款' : '欠你 ${groupDigits(lent)}',
                onTap: () => nav.open(Pages.debts),
              ),
            ]),
            const RuleHead('分類與設定'),
            _ToolRow([
              ToolButton(
                glyph: Glyph.grid,
                color: ToolHue.categories,
                label: '分類',
                detail: '${ledger.categories.length} 個',
                onTap: () => nav.open(Pages.categories),
              ),
              ToolButton(
                glyph: Glyph.tag,
                color: ToolHue.tags,
                label: '標籤與商家',
                detail: '${ledger.tags.length} 個標籤',
                onTap: () => nav.open(Pages.tags),
              ),
              ToolButton(
                glyph: Glyph.gear,
                color: ToolHue.settings,
                label: '設定',
                detail: '備份、提醒',
                onTap: () => nav.open(Pages.settings),
              ),
            ]),
          ],
        );
      },
    );
  }
}

/// Up to three [ToolButton]s side by side, each a third of the width.
class _ToolRow extends StatelessWidget {
  const _ToolRow(this.tools);

  final List<Widget> tools;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < 3; i++)
          Expanded(child: i < tools.length ? tools[i] : const SizedBox()),
      ],
    );
  }
}

/// A tool on 更多: its icon on a pale rounded square of its colour, its
/// name, and one line on what it is about now.
class ToolButton extends StatelessWidget {
  const ToolButton({
    super.key,
    required this.glyph,
    required this.color,
    required this.label,
    required this.detail,
    required this.onTap,
  });

  final Glyph glyph;
  final Color color;
  final String label;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$label，$detail',
      excludeSemantics: true,
      child: Pressable(
        child: InkWell(
          key: Keys.tool(label),
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
            child: Column(
              children: [
                Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    color: tintOf(color, 0.2),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  alignment: Alignment.center,
                  child: GlyphIcon(glyph, size: 30, color: color),
                ),
                const SizedBox(height: 10),
                OneLine(
                  label,
                  alignment: Alignment.center,
                  style: const TextStyle(
                    fontSize: TextSize.title,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                OneLine(
                  detail,
                  alignment: Alignment.center,
                  style: const TextStyle(
                    fontSize: TextSize.small,
                    color: Hue.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
