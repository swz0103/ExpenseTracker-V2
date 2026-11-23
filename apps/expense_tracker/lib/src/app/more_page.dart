import 'package:flutter/material.dart';

import '../../design_system/display/amount.dart';
import '../core/design_system/glyphs.dart';
import '../core/design_system/theme.dart';
import '../core/design_system/design_system.dart';
import '../core/ledger/ledger.dart';
import '../core/navigation/nav.dart';
import '../features/debts/ui/debts_page.dart';
import '../core/design_system/shape.dart';
import '../core/design_system/spacing.dart';
import '../core/formatting/words.dart';
import '../../design_system/display/date.dart';
import '../features/debts/model/debts.dart';

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
      builder: (context, _) => HeadedList(
        padding: const EdgeInsets.fromLTRB(Space.s5, 0, Space.s5, Space.s6),
        header: const PageHeader('更多'),
        children: [
          const RuleHead('報表與投資'),
          _reports(),
          const RuleHead('預算與往來'),
          _plans(),
          const RuleHead('分類與設定'),
          _setup(),
        ],
      ),
    );
  }

  /// 財務報表 with this month's savings rate, 投資與股息 with the gain.
  Widget _reports() {
    final today = ledger.today;
    final income = ledger.reportService.income(today.year, today.month);
    final expense = ledger.reportService.expense(today.year, today.month);
    return _ToolRow([
      ToolButton(
        glyph: Glyph.reports,
        color: ToolColors.reports,
        label: '財務報表',
        detail: '結餘率 ${wholePercent(income - expense, income)}',
        onTap: () => nav.open(AppRoutes.reports),
      ),
      ToolButton(
        glyph: Glyph.pie,
        color: ToolColors.investments,
        label: '投資與股息',
        detail: signed(ledger.holdings.marketValue - ledger.holdings.costBasis),
        spokenDetail: spokenAmount(
          ledger.holdings.marketValue - ledger.holdings.costBasis,
          sense: AmountSense.signed,
        ),
        onTap: () => nav.open(AppRoutes.investments),
      ),
    ]);
  }

  /// 預算管理 with what is left this month, 定期交易 with what is due
  /// or next, 代墊與借貸 with what people owe.
  Widget _plans() {
    final today = ledger.today;
    final due = ledger.recurringService.due;
    final items = [...due, ...ledger.recurringService.upcoming];
    final expense = ledger.reportService.expense(today.year, today.month);
    final limit = ledger.budgetService.allowance(
      ledger.budgets.forCategory(allSpending),
      today.year,
      today.month,
    );
    final next = items.isEmpty ? null : items.first;
    final lent = peopleOwing(ledger)
        .fold<int>(0, (sum, a) => sum + owedFrom(ledger.balanceService, a));
    final left = limit - expense;
    return _ToolRow([
      ToolButton(
        glyph: Glyph.gauge,
        color: ToolColors.budgets,
        label: '預算管理',
        detail: limit == 0
            ? '還沒設定'
            : left < 0
            ? '超支 ${groupDigits(-left)}'
            : '剩 ${groupDigits(left)}',
        onTap: () => nav.open(AppRoutes.budgets),
      ),
      ToolButton(
        glyph: Glyph.cycleCalendar,
        color: ToolColors.recurring,
        label: '定期交易',
        // What is due shows here, not as a tile of its own.
        detail: due.isNotEmpty
            ? '${countOf(due.length, CountUnit.entries)}到期'
            : next == null
            ? '沒有待扣款'
            : '下一筆 ${switch (ledger.recurringService.nextDate(next)) {
                final d? => formatMd(d),
                null => '',
              }}',
        onTap: () => nav.open(AppRoutes.recurring),
      ),
      ToolButton(
        glyph: Glyph.swap,
        color: ToolColors.debts,
        label: '代墊與借貸',
        detail: lent == 0 ? '沒有欠款' : '欠你 ${groupDigits(lent)}',
        onTap: () => nav.open(AppRoutes.debts),
      ),
    ]);
  }

  /// 分類, 標籤與商家 and 設定, each with how many or what it holds.
  Widget _setup() => _ToolRow([
    ToolButton(
      glyph: Glyph.grid,
      color: ToolColors.categories,
      label: Words.category,
      detail: countOf(ledger.categories.all.length, CountUnit.pieces),
      onTap: () => nav.open(AppRoutes.categories),
    ),
    ToolButton(
      glyph: Glyph.tag,
      color: ToolColors.tags,
      label: '標籤與商家',
      detail:
          '${countOf(ledger.reportService.tags.length, CountUnit.pieces)}標籤',
      onTap: () => nav.open(AppRoutes.tags),
    ),
    ToolButton(
      glyph: Glyph.gear,
      color: ToolColors.settings,
      label: '設定',
      detail: '備份、提醒',
      onTap: () => nav.open(AppRoutes.settings),
    ),
  ]);
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
    this.spokenDetail,
  });

  final Glyph glyph;
  final Color color;
  final String label;
  final String detail;

  /// What a screen reader says for [detail] when it is an amount with a
  /// sign: its direction in words.
  final String? spokenDetail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ReadAsButton(
      label: '$label，${spokenDetail ?? detail}',
      onTap: onTap,
      child: Pressable(
        child: InkWell(
          key: Keys.tool(label),
          onTap: onTap,
          borderRadius: BorderRadius.circular(Radii.largeIncreased),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: Space.s2,
              horizontal: Space.half,
            ),
            child: Column(
              children: [
                Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    color: tintOf(color, 0.2),
                    borderRadius: BorderRadius.circular(Radii.largeIncreased),
                  ),
                  alignment: Alignment.center,
                  child: GlyphIcon(glyph, size: 30, color: color),
                ),
                const SizedBox(height: Space.s2),
                OneLine(
                  label,
                  alignment: Alignment.center,
                  style: const TextStyle(
                    fontSize: TextSize.title,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: Space.half),
                OneLine(detail, alignment: Alignment.center, style: mutedSmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
