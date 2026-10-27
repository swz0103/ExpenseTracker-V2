import 'package:flutter/material.dart';

import '../../accounts/compose/account_editor.dart';
import '../../../core/ui/pickers.dart';
import '../../../core/look/figures.dart';
import '../../../core/look/glyphs.dart';
import '../../../core/look/icons.dart';
import '../../../core/look/theme.dart';
import '../../../core/look/widgets.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/ui/entry_tile.dart';
import '../../../core/nav.dart';

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

  /// What entries on [card] tagged [tag] came to this year.
  int _tagged(Account card, String tag, EntryType type) {
    final year = ledger.today.year;
    var total = 0;
    for (var month = 1; month <= ledger.today.month; month++) {
      for (final e in ledger.entriesIn(year, month)) {
        if (e.account == card.id && e.type == type && e.tags.contains(tag)) {
          total += e.amount;
        }
      }
    }
    return total;
  }

  /// Opens the composer on a cashback credit or an annual fee for [card].
  void _extra(Account card, EntryType type) {
    final reward = type == EntryType.income;
    nav.compose(
      type: type,
      draft: Entry(
        id: '',
        date: ledger.today,
        type: type,
        amount: 0,
        account: card.id,
        category: reward ? '其他收入' : feeCategory,
        note: '${card.name}${reward ? '回饋' : '年費'}',
        tags: [reward ? '回饋' : '年費'],
      ),
    );
  }

  /// Lets the person move the next close of [card], [next], by up to a
  /// week, as banks do around holidays.
  Future<void> _moveClose(
    BuildContext context,
    Account card,
    DateTime next,
  ) async {
    var scheduled = next;
    for (final MapEntry(:key, :value) in card.closes.entries) {
      if (value == next) scheduled = key;
    }
    final picked = await pickDate(
      context,
      title: '這期改在哪天結帳',
      selected: next,
      latest: scheduled.add(const Duration(days: 7)),
      marked: {scheduled},
    );
    if (picked == null) return;
    if (picked.difference(scheduled).inDays.abs() > 7) {
      if (context.mounted) showNote(context, '結帳日最多只能前後移動 7 天');
      return;
    }
    ledger.moveClose(card.id, scheduled, picked);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ledger,
      builder: (context, _) {
        // Gone by another way, such as a restore: nothing to show.
        if (!ledger.hasAccount(accountId)) {
          WidgetsBinding.instance.addPostFrameCallback((_) => nav.back());
          return const SizedBox.shrink();
        }
        final card = ledger.account(accountId);
        final today = ledger.today;
        final (start, end, due) = ledger.statement(card);
        final owed = ledger.statementDue(card);
        final unbilled = ledger.unbilled(card);
        final spentSince = unbilled.fold(
          0,
          (sum, e) => sum - ledger.effect(e, card.id),
        );
        final plans = ledger.instalmentsOn(card);
        final pending = plans.fold(
          0,
          (sum, e) => sum + e.amount - ledger.billed(e, ledger.closedBy),
        );
        final limit = card.limit;
        final debt = -ledger.balance(card.id);
        final following = card.closingOn(
          DateTime.utc(end.year, end.month + 1, end.day),
        );
        final cycleDays = following.difference(end).inDays;
        final gone = today.difference(end).inDays;
        final left = due.difference(today).inDays;
        final next = card.closingOn(end.add(const Duration(days: 40)));
        final status = owed == 0
            ? '這期已繳清'
            : '繳款截止 ${_day(due)}（${left < 0 ? '已逾期' : '還有 $left 天'}）';
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          children: [
            PageHeader(
              card.name,
              onBack: nav.back,
              trailing: TextButton(
                onPressed: () async {
                  final gone = await editAccount(
                    context,
                    ledger,
                    account: card,
                  );
                  // Deleted or archived: back to the accounts.
                  if (gone) nav.back();
                },
                style: TextButton.styleFrom(foregroundColor: Hue.accent),
                child: const Text('編輯'),
              ),
            ),
            Tile(
              hero: true,
              icon: Glyph.card,
              label: '本期帳單 · ${_day(start)}–${_day(end)}',
              trailing: Pill(owed == 0 ? '已繳清' : '已出帳'),
              value: ledger.money(owed),
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
                            account: ledger.mainAccount,
                            category: transferCategory,
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
                value: ledger.money(spentSince),
                sub: '第 $gone / $cycleDays 天',
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: LinearProgressIndicator(
                    value: cycleDays == 0 ? 0 : gone / cycleDays,
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(3),
                    color: Hue.accent,
                    backgroundColor: Hue.accentTrack,
                  ),
                ),
              ),
              Tile(
                icon: Glyph.budget,
                label: '可用額度',
                value: limit == null
                    ? '—'
                    : ledger.money(limit - debt - pending),
                sub: limit == null
                    ? '未設定額度'
                    : pending == 0
                    ? '總額度 ${ledger.orDots(shortAmount(limit))}'
                    : '含分期未繳 ${ledger.money(pending)}',
              ),
            ]),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Tile(
                icon: Glyph.calendar,
                label: '下次結帳',
                value: _day(next),
                sub: '遇假日可以前後調整 7 天內',
                trailing: const GlyphIcon(Glyph.edit, size: 16),
                onTap: () => _moveClose(context, card, next),
              ),
            ),
            TileRow([
              Tile(
                icon: Glyph.sparkle,
                label: '今年回饋',
                value: ledger.money(_tagged(card, '回饋', EntryType.income)),
                valueColor: Hue.positive,
                trailing: const GlyphIcon(Glyph.add, size: 16),
                onTap: () => _extra(card, EntryType.income),
              ),
              Tile(
                icon: Glyph.ticket,
                label: '今年年費',
                value: ledger.money(_tagged(card, '年費', EntryType.expense)),
                trailing: const GlyphIcon(Glyph.add, size: 16),
                onTap: () => _extra(card, EntryType.expense),
              ),
            ]),
            if (plans.isNotEmpty) ...[
              SectionHead(
                '分期中',
                trailing: Text('${plans.length} 筆', style: mutedSmall),
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
                      _plan(e, ledger.billedPeriods(e, ledger.closedBy)),
                  ],
                ),
              ),
            ],
            SectionHead(
              '本期未出帳',
              trailing: Text(
                '${_day(end.add(const Duration(days: 1)))} 起',
                style: mutedSmall,
              ),
            ),
            if (unbilled.isEmpty)
              const Text('還沒有新的刷卡', style: TextStyle(color: Hue.muted))
            else
              SoftPanel(
                color: Hue.white,
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Column(
                  children: [
                    for (final e in unbilled)
                      EntryTile(
                        ledger: ledger,
                        entry: e,
                        onTap: () => nav.showEntry(e),
                        divider: !identical(e, unbilled.last),
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
                  _setting('信用額度', limit == null ? '未設定' : ledger.money(limit)),
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
                      '${ledger.money(each)} / 期',
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
                  '剩 ${ledger.money(e.amount - ledger.billed(e, ledger.closedBy))}',
                  style: mutedSmall,
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
