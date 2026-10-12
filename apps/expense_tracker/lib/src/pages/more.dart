import 'package:flutter/material.dart';

import '../demo/ledger.dart';
import '../look/figures.dart';
import '../look/glyphs.dart';
import '../look/theme.dart';
import '../look/widgets.dart';
import 'nav.dart';

/// 更多: what falls due as the main tile, the four tools with the figure
/// each one is about, and the settings in a list.
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
        final limit = ledger.budgetFor(Ledger.allSpending).limit;
        final next = items.isEmpty ? null : items.first;
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          children: [
            const PageHeader('更多'),
            Tile(
              hero: true,
              icon: Glyph.calendar,
              label: due.isEmpty ? '即將扣款' : '已到期',
              trailing: const GlyphIcon(Glyph.next, size: 18, color: Hue.muted),
              value: '${items.length} 筆',
              valueColor: due.isEmpty ? Hue.ink : Hue.negative,
              size: 28,
              sub: items.isEmpty
                  ? '沒有待扣款項目'
                  : [
                      for (final r in items.take(3))
                        '${ledger.nextLabel(r)} ${r.name} ${money(r.amount)}',
                    ].join(' · '),
              onTap: () => nav.open(Pages.recurring),
            ),
            const SectionHead('分析與規劃'),
            TileRow([
              Tile(
                icon: Glyph.reports,
                label: '財務報表',
                value: '$rate%',
                sub: '本月結餘率',
                onTap: () => nav.open(Pages.reports),
              ),
              Tile(
                icon: Glyph.investment,
                label: '投資與股息',
                value: moneySigned(ledger.investValue - ledger.investCost),
                valueColor: ledger.investValue < ledger.investCost
                    ? Hue.negative
                    : Hue.positive,
                sub: '未實現損益',
                onTap: () => nav.open(Pages.investments),
              ),
            ]),
            TileRow([
              Tile(
                icon: Glyph.budget,
                label: '預算管理',
                value: money(limit - expense),
                valueColor: limit < expense ? Hue.negative : Hue.ink,
                sub: '本月剩餘',
                onTap: () => nav.open(Pages.budgets),
              ),
              Tile(
                icon: Glyph.recurring,
                label: '定期交易',
                value: next == null ? '—' : ledger.nextLabel(next),
                sub: next == null ? '沒有待扣款項目' : '下一筆 ${next.name}',
                onTap: () => nav.open(Pages.recurring),
              ),
            ]),
            const SectionHead('設定'),
            SoftPanel(
              color: Hue.white,
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  _Row(
                    icon: Glyph.categories,
                    title: '分類管理',
                    detail: '${ledger.categories.length} 個分類',
                    onTap: () => nav.open(Pages.categories),
                  ),
                  const Divider(height: 1, indent: 14, endIndent: 14),
                  _Row(
                    icon: Glyph.ticket,
                    title: '標籤與商家',
                    detail: '${ledger.tags.length} 個標籤',
                    onTap: () => nav.open(Pages.labels),
                  ),
                  const Divider(height: 1, indent: 14, endIndent: 14),
                  _Row(
                    icon: Glyph.sliders,
                    title: '設定與資料',
                    detail: '匯出、重設',
                    onTap: () => nav.open(Pages.settings),
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

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
  });

  final Glyph icon;
  final String title;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                color: Hue.tile,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: GlyphIcon(icon, size: 18, color: Hue.accent),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 15))),
            Text(
              detail,
              style: const TextStyle(fontSize: 13, color: Hue.muted),
            ),
            const SizedBox(width: 4),
            const GlyphIcon(Glyph.next, size: 16, color: Hue.muted),
          ],
        ),
      ),
    );
  }
}
