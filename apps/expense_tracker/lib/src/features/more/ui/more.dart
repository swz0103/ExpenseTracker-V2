import 'package:flutter/material.dart';

import '../../../core/look/figures.dart';
import '../../../core/look/glyphs.dart';
import '../../../core/look/theme.dart';
import '../../../core/look/widgets.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/nav.dart';
import '../../debts/ui/debts_page.dart';

/// The colour of each tool, on its tile here and on its own page.
abstract final class ToolHue {
  static const reports = Shade(0xFF5B8DB0, 0xFF8DB5D1);
  static const investments = Shade(0xFF4A5D99, 0xFF9FAEE0);
  static const budgets = Shade(0xFF5C9A83, 0xFF8CC3AE);
  static const recurring = Shade(0xFFD08B5B, 0xFFE3AA82);
  static const debts = Shade(0xFF8E7CC0, 0xFFB5A8DD);
  static const categories = Shade(0xFFB07A8C, 0xFFD3A2B3);
  static const labels = Shade(0xFFC9A34A, 0xFFDDBE73);
  static const settings = Shade(0xFF6B767C, 0xFFA3AEB3);
}

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
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            const PageHeader('更多'),
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
                color: ToolHue.labels,
                label: '標籤與商家',
                detail: '${ledger.tags.length} 個標籤',
                onTap: () => nav.open(Pages.labels),
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
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: Hue.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
