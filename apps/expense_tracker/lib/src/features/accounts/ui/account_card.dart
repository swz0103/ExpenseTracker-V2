import 'package:flutter/material.dart';

import '../../../../design_system/display/status.dart';
import '../../../core/design_system/glyphs.dart';
import '../../../core/widgets/icons.dart';
import '../../../core/design_system/theme.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/widgets/shown_amounts.dart';
import '../../../../design_system/display/date.dart';
import '../../../core/design_system/shape.dart';
import '../../../core/design_system/spacing.dart';
import '../../../core/formatting/words.dart';

/// How tall a card of 我的帳戶 is when it lies in front, and how much of
/// each card behind it shows.
const frontCardHeight = 150.0;
const cardStripHeight = 60.0;

/// The strip and front heights for the phone's text size: larger text
/// makes the cards taller, so the words still fit.
(double, double) cardHeights(BuildContext context) {
  final grow = textGrowth(context) - 1;
  final more = grow > 0 ? grow : 0.0;
  return (cardStripHeight + 26 * more, frontCardHeight + 100 * more);
}

/// The kind of an account as its card writes it.
String cardKindLabel(Account account) => switch (account.kind) {
  AccountKind.bank => account.foreign ? '銀行 · ${account.currency}' : '銀行',
  AccountKind.wallet => account.foreign ? '電子支付 · ${account.currency}' : '電子支付',
  AccountKind.cash => account.foreign ? '現金 · ${account.currency}' : '現金',
  AccountKind.card => '信用卡',
  AccountKind.loan => '貸款',
  AccountKind.receivable => Words.lend,
};

/// What [account] spent this month, as the reports count 支出: spending
/// less refunds, with transfer fees; not money that only moved (D20).
int spentThisMonth(Ledger ledger, Account account) => ledger.reportService
    .expense(ledger.today.year, ledger.today.month, account: account.id);

/// The face of an account's card: one tint, its own or its kind's, with the name,
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
    final color = accountColor(account);
    final radius = BorderRadius.circular(Radii.largeIncreased);
    final (stripHeight, frontHeight) = cardHeights(context);
    final (label, figure, note) = front ? _face() : ('', '', '');
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: radius, boxShadow: _stacked),
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
              padding: const EdgeInsets.fromLTRB(
                Space.s4,
                Space.s4,
                Space.s4,
                Space.s4,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _head(color),
                  if (front) ...[
                    const Spacer(),
                    _Figure(label: label, figure: figure, note: note),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The top line: the mark, the name, and the kind on the front card or
  /// the figure on a card's strip.
  Widget _head(Color color) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: const BoxDecoration(
            color: AppColors.glass,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: GlyphIcon(accountIcon(account), size: 17, color: color),
        ),
        const SizedBox(width: Space.s2),
        Expanded(
          child: Text(
            account.name.isEmpty ? '帳戶名稱' : account.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: TextSize.body,
              fontWeight: FontWeight.w700,
              color: account.name.isEmpty ? AppColors.faint : AppColors.ink,
            ),
          ),
        ),
        const SizedBox(width: Space.s2),
        if (front)
          Text(cardKindLabel(account), style: mutedSmall)
        else
          Text(
            _strip(),
            style: const TextStyle(
              fontSize: TextSize.title,
              fontWeight: FontWeight.w700,
            ),
          ),
      ],
    );
  }

  /// The figure at the end of a card's strip: what is owed on a debt,
  /// else the balance.
  String _strip() {
    final balance = preview ?? ledger.balanceService.balance(account.id);
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
    final balance = ledger.balanceService.balance(account.id);
    switch (account.kind) {
      case AccountKind.card:
        final (_, _, due) = ledger.statementService.statement(account);
        return (
          '本期應繳',
          ledger.money(ledger.statementService.statementDue(account)),
          cardBillWords(
            ledger.statementService.billStatus(account),
            postponed: postponedTo(due, payByOf(due)),
          ),
        );
      case AccountKind.loan:
        return ('尚欠', ledger.money(-balance), '');
      case AccountKind.receivable:
        return ('還欠你', ledger.money(balance), '');
      case AccountKind.bank || AccountKind.wallet || AccountKind.cash:
        if (account.foreign) {
          final home = ledger.marketData.toHome(balance, account.currency);
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

/// The bottom of a front card: [label] over the large [figure], with
/// [note] beside it when there is one.
class _Figure extends StatelessWidget {
  const _Figure({
    required this.label,
    required this.figure,
    required this.note,
  });

  final String label;
  final String figure;
  final String note;

  @override
  Widget build(BuildContext context) {
    return Row(
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
                    fontSize: TextSize.figure,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
              ),
            ],
          ),
        ),
        // A long note, such as a bill's moved due day and days left,
        // wraps beside the figure rather than running off the card.
        if (note.isNotEmpty)
          Flexible(
            child: Padding(
              padding: const EdgeInsets.only(left: Space.s2, bottom: Space.s1),
              child: Text(note, style: mutedSmall, textAlign: TextAlign.end),
            ),
          ),
      ],
    );
  }
}

/// A card's shadow in the stack: a soft one above, where the card behind
/// shows, and a close one under it.
const _stacked = [
  BoxShadow(color: AppColors.stackFar, blurRadius: 8, offset: Offset(0, -2)),
  BoxShadow(color: AppColors.stackNear, blurRadius: 2, offset: Offset(0, 1)),
];
