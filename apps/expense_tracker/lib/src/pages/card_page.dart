import 'package:flutter/material.dart';

import '../demo/ledger.dart';
import '../look/figures.dart';
import '../look/glyphs.dart';
import '../look/icons.dart';
import '../look/theme.dart';
import '../look/widgets.dart';
import 'entry_tile.dart';
import 'nav.dart';

/// A credit card: the last statement and when it is due, with 繳卡款;
/// what has been spent since, the credit left, purchases paid in
/// instalments and the card's closing and payment days.
class CardPage extends StatelessWidget {
  const CardPage({
    super.key,
    required this.ledger,
    required this.nav,
    required this.accountId,
  });

  final Ledger ledger;
  final Nav nav;
  final String accountId;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ledger,
      builder: (context, _) {
        final card = ledger.account(accountId);
        final today = ledger.today;
        final (start, end, due) = ledger.statement(card);
        final owed = ledger.statementDue(card);
        final unbilled = ledger.unbilled(card);
        final spentSince = unbilled.fold(0, (sum, e) => sum + e.amount);
        final plans = ledger.instalmentsOn(card);
        final pending = plans.fold(
          0,
          (sum, e) => sum + e.amount - ledger.billed(e, today),
        );
        final limit = card.limit;
        final debt = -ledger.balance(card.id);
        final cycleDays = ledger
            .closingOn(card, DateTime.utc(end.year, end.month + 1, end.day))
            .difference(end)
            .inDays;
        final gone = today.difference(end).inDays;
        final left = due.difference(today).inDays;
        final next = ledger.closingOn(card, end.add(const Duration(days: 40)));
        final status = owed == 0
            ? '下次結帳 ${_day(next)}'
            : '繳款截止 ${_day(due)}（${left < 0 ? '已逾期' : '還有 $left 天'}）';
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          children: [
            PageHeader(card.name, onBack: nav.back),
            Tile(
              hero: true,
              icon: Glyph.card,
              label: '本期帳單 · ${_day(start)}–${_day(end)}',
              trailing: Pill(owed == 0 ? '已繳清' : '已出帳'),
              value: money(owed),
              valueColor: owed > 0 ? Hue.negative : Hue.positive,
              sub: status,
              child: owed == 0
                  ? null
                  : Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: FilledButton(
                        onPressed: () => nav.compose(
                          type: EntryType.transfer,
                          draft: Entry(
                            id: '',
                            date: today,
                            type: EntryType.transfer,
                            amount: owed,
                            account: 'bank',
                            category: '轉帳',
                            note: '${card.name}繳款',
                            to: card.id,
                          ),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: Hue.accent,
                          minimumSize: const Size.fromHeight(44),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('繳卡款'),
                      ),
                    ),
            ),
            TileRow([
              Tile(
                icon: Glyph.calendar,
                label: '本期未出帳',
                value: money(spentSince),
                sub: '第 $gone / $cycleDays 天',
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: LinearProgressIndicator(
                    value: cycleDays == 0 ? 0 : gone / cycleDays,
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(3),
                    color: Hue.accent,
                    backgroundColor: const Color(0x263B6C80),
                  ),
                ),
              ),
              Tile(
                icon: Glyph.budget,
                label: '可用額度',
                value: limit == null ? '—' : money(limit - debt - pending),
                sub: limit == null
                    ? '未設定額度'
                    : pending == 0
                    ? '總額度 ${shortAmount(limit)}'
                    : '含分期未繳 ${money(pending)}',
              ),
            ]),
            if (plans.isNotEmpty) ...[
              SectionHead(
                '分期中',
                trailing: Text(
                  '${plans.length} 筆',
                  style: const TextStyle(fontSize: 12, color: Hue.muted),
                ),
              ),
              SoftPanel(
                color: Hue.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 4,
                ),
                child: Column(
                  children: [
                    for (final e in plans)
                      _plan(e, ledger.billedPeriods(e, today)),
                  ],
                ),
              ),
            ],
            SectionHead(
              '本期未出帳',
              trailing: Text(
                '${_day(end.add(const Duration(days: 1)))} 起',
                style: const TextStyle(fontSize: 12, color: Hue.muted),
              ),
            ),
            if (unbilled.isEmpty)
              const Text('還沒有新的刷卡', style: TextStyle(color: Hue.muted))
            else
              SoftPanel(
                color: Hue.white,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Column(
                  children: [
                    for (final e in unbilled)
                      EntryTile(
                        ledger: ledger,
                        entry: e,
                        onTap: () => nav.showEntry(e),
                      ),
                  ],
                ),
              ),
            const SectionHead('設定'),
            SoftPanel(
              color: Hue.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: Column(
                children: [
                  _setting('結帳日', '每月 ${card.closingDay ?? 1} 日'),
                  const Divider(height: 1),
                  _setting('繳款日', '每月 ${card.dueDay ?? 15} 日'),
                  const Divider(height: 1),
                  _setting('信用額度', limit == null ? '未設定' : money(limit)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  static String _day(DateTime day) => '${day.month}/${day.day}';

  Widget _plan(Entry e, int periods) {
    final each = e.amount ~/ e.installments;
    final category = ledger.category(e.category);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          IconBadge(iconFor(category.icon), category.color, size: 34),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        e.title,
                        style: const TextStyle(fontSize: 15),
                      ),
                    ),
                    Text(
                      '${money(each)} / 期',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: periods / e.installments,
                  minHeight: 5,
                  borderRadius: BorderRadius.circular(3),
                  color: category.color,
                  backgroundColor: Hue.track,
                ),
                const SizedBox(height: 4),
                Text(
                  '第 $periods / ${e.installments} 期 · '
                  '剩 ${money(e.amount - ledger.billed(e, ledger.today))}',
                  style: const TextStyle(fontSize: 12, color: Hue.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _setting(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontSize: 14)),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
