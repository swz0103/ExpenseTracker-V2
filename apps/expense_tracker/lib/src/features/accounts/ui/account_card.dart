import 'package:flutter/material.dart';

import '../../../core/look/figures.dart';
import '../../../core/look/glyphs.dart';
import '../../../core/look/icons.dart';
import '../../../core/look/theme.dart';
import '../../../core/ledger/ledger.dart';

/// How tall a card of 我的帳戶 is when it lies in front, and how much of
/// each card behind it shows.
const frontCardHeight = 150.0;
const cardStripHeight = 60.0;

/// The strip and front heights for the phone's text size: larger text
/// makes the cards taller, so the words still fit.
(double, double) cardHeights(BuildContext context) {
  final grow = MediaQuery.textScalerOf(context).scale(16) / 16 - 1;
  final more = grow > 0 ? grow : 0.0;
  return (cardStripHeight + 26 * more, frontCardHeight + 80 * more);
}

/// The kind of an account as its card writes it.
String cardKindLabel(Account account) => switch (account.kind) {
  AccountKind.bank => account.foreign ? '銀行 · ${account.currency}' : '銀行',
  AccountKind.wallet => account.foreign ? '電子支付 · ${account.currency}' : '電子支付',
  AccountKind.cash => account.foreign ? '現金 · ${account.currency}' : '現金',
  AccountKind.card => '信用卡',
  AccountKind.loan => '貸款',
  AccountKind.receivable => '代墊',
};

/// What [account] spent this month: everything that left it.
int spentThisMonth(Ledger ledger, Account account) {
  final today = ledger.today;
  var out = 0;
  for (final e in ledger.entriesIn(today.year, today.month)) {
    if (e.account != account.id && e.to != account.id) continue;
    final change = ledger.effect(e, account.id);
    if (change < 0) out -= change;
  }
  return out;
}

/// The face of an account's card: one tint, its kind's, with the name,
/// one large figure and one line under it. Behind the front card only
/// the top strip shows, with the balance at its end.
class AccountCard extends StatelessWidget {
  const AccountCard({
    super.key,
    required this.ledger,
    required this.account,
    this.front = true,
    this.onTap,
    this.onLongPress,
    this.preview,
  });

  final Ledger ledger;
  final Account account;

  /// The balance to show for an account still being filled in, which the
  /// ledger does not hold yet.
  final int? preview;

  /// The whole face; false shows the strip of a card behind.
  final bool front;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final color = accountColor(account.kind);
    final radius = BorderRadius.circular(20);
    final (stripHeight, frontHeight) = cardHeights(context);
    final (label, figure, note) = front ? _face() : ('', '', '');
    final head = Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: const BoxDecoration(
            color: Shade(0xC0FFFFFF, 0x1FFFFFFF),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: GlyphIcon(accountIcon(account), size: 17, color: color),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            account.name.isEmpty ? '帳戶名稱' : account.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: account.name.isEmpty ? Hue.faint : Hue.ink,
            ),
          ),
        ),
        const SizedBox(width: 8),
        if (front)
          Text(cardKindLabel(account), style: mutedSmall)
        else
          Text(
            _strip(),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
      ],
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: const [
          BoxShadow(
            color: Shade(0x141E2832, 0x00000000),
            blurRadius: 8,
            offset: Offset(0, -2),
          ),
          BoxShadow(
            color: Shade(0x0F1E2832, 0x00000000),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Material(
        color: softOf(color),
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          onLongPress: onLongPress,
          child: SizedBox(
            height: front ? frontHeight : stripHeight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 16, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  head,
                  if (front) ...[
                    const Spacer(),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(label, style: mutedSmall),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  figure,
                                  style: const TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w700,
                                    height: 1.15,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (note.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(left: 8, bottom: 4),
                            child: Text(note, style: mutedSmall),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The figure at the end of a card's strip: what is owed on a debt,
  /// else the balance.
  String _strip() {
    final balance = preview ?? ledger.balance(account.id);
    return account.kind.isDebt
        ? ledger.money(-balance)
        : ledger.moneyIn(balance, account.currency);
  }

  /// The label over the figure, the figure, and the line beside it.
  (String, String, String) _face() {
    final shown = preview;
    if (shown != null) {
      return switch (account.kind) {
        AccountKind.card => (
          '目前欠款',
          ledger.money(-shown),
          account.dueDay == null ? '' : '每月 ${account.dueDay} 日繳款',
        ),
        AccountKind.loan => ('尚欠', ledger.money(-shown), ''),
        _ => ('餘額', ledger.moneyIn(shown, account.currency), ''),
      };
    }
    final balance = ledger.balance(account.id);
    switch (account.kind) {
      case AccountKind.card:
        final (_, _, due) = ledger.statement(account);
        return (
          '本期應繳',
          ledger.money(ledger.statementDue(account)),
          '${due.month}/${due.day} 繳款',
        );
      case AccountKind.loan:
        return ('尚欠', ledger.money(-balance), '');
      case AccountKind.receivable:
        return ('還欠你', ledger.money(balance), '');
      case AccountKind.bank || AccountKind.wallet || AccountKind.cash:
        if (account.foreign) {
          final home = ledger.toHome(balance, account.currency);
          return (
            '餘額',
            ledger.moneyIn(balance, account.currency),
            home == null ? '' : '約 NT\$ ${ledger.money(home)}',
          );
        }
        final out = spentThisMonth(ledger, account);
        return (
          '餘額',
          ledger.money(balance),
          out == 0 ? '' : '本月支出 ${ledger.money(out)}',
        );
    }
  }
}
