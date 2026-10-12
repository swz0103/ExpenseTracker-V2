import 'package:flutter/material.dart';

import '../compose/calculator.dart';
import '../compose/pickers.dart';
import '../demo/ledger.dart';
import '../look/figures.dart';
import '../look/glyphs.dart';
import '../look/icons.dart';
import '../look/theme.dart';
import '../look/widgets.dart';
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

  Future<void> _edit(String category, int limit) => showSheet<void>(
    context,
    (_) => _BudgetEditor(
      ledger: widget.ledger,
      budget: widget.ledger.budgetFor(category),
    ),
  );

  Future<void> _addLimit() async {
    final ledger = widget.ledger;
    final picked = await pickOption<String>(
      context,
      title: '設定額度的分類',
      selected: null,
      options: [
        for (final c in ledger.categoriesFor(income: false))
          if (ledger.budgetFor(c.name).limit == 0)
            Option(c.name, c.name, iconFor(c.icon), c.color),
      ],
    );
    if (picked != null && mounted) await _edit(picked, 0);
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
        final today = ledger.today;
        final current = year == today.year && month == today.month;
        final days = DateTime.utc(year, month + 1, 0).day;
        final passed = current ? today.day : days;
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
                  Tile(
                    hero: true,
                    icon: Glyph.budget,
                    label: left < 0 ? '本月超支' : '本月剩餘',
                    trailing: GestureDetector(
                      onTap: () => _edit(Ledger.allSpending, total),
                      child: const GlyphIcon(Glyph.edit, size: 18),
                    ),
                    lead: RingGauge(
                      share: total == 0 ? 0 : spent / total,
                      size: 68,
                    ),
                    value: money(left.abs()),
                    valueColor: left < 0 ? Hue.negative : Hue.ink,
                    sub: '總預算 ${money(total)} · 已用 ${money(spent)}',
                  ),
                  TileRow([
                    Tile(
                      icon: Glyph.calendar,
                      label: '時間進度',
                      value: '${passed * 100 ~/ days}%',
                      sub: current ? '剩 ${days - passed + 1} 天' : '已結束',
                    ),
                    Tile(
                      icon: Glyph.wallet,
                      label: '每日可用',
                      value: current && left > 0
                          ? money(left ~/ (days - passed + 1))
                          : '—',
                      valueColor: Hue.positive,
                    ),
                  ]),
                  const SectionHead('分類額度'),
                  SoftPanel(
                    color: Hue.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Column(
                      children: [
                        for (final (budget, amount) in rows)
                          _CategoryLimit(
                            category: ledger.category(budget.category),
                            warning: budget.warning,
                            limit: budget.limit,
                            used: amount,
                            onEdit: () => _edit(budget.category, budget.limit),
                          ),
                        InkWell(
                          onTap: _addLimit,
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 14),
                            child: Center(
                              child: Text(
                                '＋ 為其他分類設定額度',
                                style: TextStyle(color: Hue.accent),
                              ),
                            ),
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

class _CategoryLimit extends StatelessWidget {
  const _CategoryLimit({
    required this.category,
    required this.warning,
    required this.limit,
    required this.used,
    required this.onEdit,
  });

  final Category category;
  final int warning;
  final int limit;
  final int used;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final left = limit - used;
    final share = limit == 0 ? 1.0 : (used / limit).clamp(0.0, 1.0);
    final near = limit > 0 && used * 100 >= limit * warning;
    final tone = left < 0
        ? Hue.negative
        : near
        ? Hue.gold
        : category.color;
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
                        color: left < 0 || near ? tone : Hue.ink,
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
                          color: tone,
                          backgroundColor: Hue.track,
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

/// A budget's form: the limit, the share at which it warns, and, for a
/// category, taking the budget away.
class _BudgetEditor extends StatefulWidget {
  const _BudgetEditor({required this.ledger, required this.budget});

  final Ledger ledger;
  final Budget budget;

  @override
  State<_BudgetEditor> createState() => _BudgetEditorState();
}

class _BudgetEditorState extends State<_BudgetEditor> {
  late var _limit = widget.budget.limit;
  late var _warning = widget.budget.warning;

  static const _shares = [70, 80, 90, 100];

  @override
  Widget build(BuildContext context) {
    final name = widget.budget.category;
    final total = name == Ledger.allSpending;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            total ? '總預算' : '$name 額度',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Tile(
            hero: true,
            icon: Glyph.budget,
            label: '每月額度',
            value: money(_limit),
            onTap: () async {
              final value = await showCalculator(
                context,
                title: '每月額度',
                initial: _limit,
                color: Hue.accent,
              );
              if (value != null) setState(() => _limit = value);
            },
          ),
          const SizedBox(height: 12),
          const Text(
            '用到幾成時提醒',
            style: TextStyle(fontSize: 12.5, color: Hue.accent),
          ),
          const SizedBox(height: 6),
          Segments(
            labels: [for (final p in _shares) '$p%'],
            selected: _shares.contains(_warning)
                ? _shares.indexOf(_warning)
                : 1,
            onChanged: (i) => setState(() => _warning = _shares[i]),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              if (!total)
                TextButton(
                  onPressed: () {
                    widget.ledger.removeBudget(name);
                    Navigator.of(context).pop();
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: Hue.danger,
                    minimumSize: const Size(64, 46),
                  ),
                  child: const Text('移除'),
                ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    widget.ledger.setBudget(name, _limit, warning: _warning);
                    Navigator.of(context).pop();
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: Hue.accent,
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('儲存'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
