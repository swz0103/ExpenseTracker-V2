import 'package:flutter/material.dart';

import '../../../../core/look/figures.dart';
import '../../../../core/look/glyphs.dart';
import '../../../../core/look/theme.dart';
import '../../../../core/look/widgets.dart';
import '../../../../core/ledger/ledger.dart';
import '../../../../core/ui/entry_tile.dart';
import '../../../../core/nav.dart';

/// 預算 and 即將扣款 side by side: what is left of the month's limit, and
/// what falls due.
class PlanSection extends StatelessWidget {
  const PlanSection({
    super.key,
    required this.ledger,
    required this.nav,
    required this.month,
  });

  final Ledger ledger;
  final Nav nav;
  final (int, int) month;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ledger,
      builder: (context, _) => TileRow([_budgetTile(), _dueTile()]),
    );
  }

  /// 預算: what is left of the month's limit, with the share spent as a
  /// ring and the share of the month gone by.
  Widget _budgetTile() {
    final (year, m) = month;
    final spent = ledger.expense(year, m);
    final limit = ledger.allowance(
      ledger.budgetFor(Ledger.allSpending),
      year,
      m,
    );
    final (gone, days) = ledger.daysGone(year, m);
    final pace = (gone / days * 100).round();
    return Tile(
      icon: Glyph.budget,
      label: '預算',
      trailing: const Text('調整', style: accentSmall),
      lead: RingGauge(share: limit == 0 ? 0 : spent / limit, size: 50),
      value: ledger.money(limit - spent),
      valueColor: limit < spent ? Hue.negative : Hue.ink,
      size: 18,
      sub: '剩餘 · 時間 $pace%',
      onTap: () => nav.open(Pages.budgets),
    );
  }

  /// 即將扣款: how many recurring items are due or coming, and the next
  /// two.
  Widget _dueTile() {
    final due = ledger.due;
    final items = [...due, ...ledger.upcoming];
    return Tile(
      icon: Glyph.calendar,
      label: due.isEmpty ? '即將扣款' : '已到期',
      trailing: const GlyphIcon(Glyph.next, size: 16, color: Hue.muted),
      value: '${items.length} 筆',
      valueColor: due.isEmpty ? Hue.ink : Hue.negative,
      sub: items.isEmpty
          ? '沒有待扣款項目'
          : [
              for (final r in items.take(2))
                [
                  ledger.nextLabel(r),
                  r.name,
                  ledger.orDots(recurringAmount(ledger, r)),
                ].join(' '),
            ].join('\n'),
      onTap: () => nav.open(Pages.recurring),
    );
  }
}
