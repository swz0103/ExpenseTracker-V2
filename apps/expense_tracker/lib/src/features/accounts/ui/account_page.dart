import 'package:flutter/material.dart';

import '../../../core/charts/waterfall.dart';
import '../forms/account_editor.dart';
import '../forms/reconcile_sheet.dart';
import 'account_action.dart';
import '../../../../design_system/display/amount.dart';
import '../../../core/design_system/glyphs.dart';
import '../../../core/widgets/icons.dart';
import '../../../core/design_system/theme.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/widgets/entry_tile.dart';
import '../../../core/navigation/nav.dart';
import '../../../core/widgets/shown_amounts.dart';
import '../../../../design_system/display/date.dart';
import '../../../core/design_system/spacing.dart';
import '../../../core/formatting/words.dart';

/// One account: its balance and this month's flow over [AccountBody].
class AccountPage extends StatefulWidget {
  const AccountPage({
    super.key,
    required this.ledger,
    required this.nav,
    required this.accountId,
  });

  final Ledger ledger;
  final Nav nav;
  final String accountId;

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  @override
  Widget build(BuildContext context) {
    final ledger = widget.ledger;
    return ListenableBuilder(
      // The account, its balance and entries, their categories' icons.
      listenable: ledger.watch(const {
        Topic.entries,
        Topic.accounts,
        Topic.categories,
      }),
      builder: (context, _) {
        // Gone by another way, such as a restore: nothing to show.
        if (!ledger.accounts.contains(widget.accountId)) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => widget.nav.back(),
          );
          return const SizedBox.shrink();
        }
        final account = ledger.account(widget.accountId);
        final balance = ledger.balanceService.balance(account.id);
        final (into, out) = monthFlow(ledger, account);
        return HeadedList(
          padding: const EdgeInsets.fromLTRB(Space.s3, 0, Space.s5, Space.s8),
          header: CenterHeader(
            account.name,
            onBack: widget.nav.back,
            actions: [
              TextButton(
                onPressed: () async {
                  final gone = await editAccount(
                    context,
                    ledger,
                    account: account,
                  );
                  // Deleted or archived: back to the accounts.
                  if (gone) widget.nav.back();
                },
                style: wordButton(AppColors.accent),
                child: const Text(Words.edit),
              ),
            ],
          ),
          children: [
            Padding(
              padding: const EdgeInsets.only(left: Space.s2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  HeroFigure(
                    icon: accountIcon(account),
                    label: groupName(account.kind),
                    value: ledger.moneyIn(balance, account.currency),
                    valueColor: AppColors.ofBalance(balance),
                    child: FigureCells([
                      (Glyph.income, '本月流入', into, AppColors.positive),
                      (Glyph.payout, '本月流出', out, AppColors.negative),
                    ]),
                  ),
                  AccountBody(
                    key: ValueKey(account.id),
                    ledger: ledger,
                    nav: widget.nav,
                    account: account,
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

/// What flowed into and out of [account] this month, as its money.
(String, String) monthFlow(Ledger ledger, Account account) {
  final flow = ledger.balanceService.flowOf(account.id, ledger.today);
  return (
    ledger.moneyIn(flow.inflow, account.currency),
    ledger.moneyIn(flow.outflow, account.currency),
  );
}

/// Under an account's card: what is done with it, four weeks of changes
/// as a waterfall, and a month of its entries by day. Shown on its own
/// page and under the cards of 我的帳戶; key it by the account, so
/// another account starts at its own latest week and month.
class AccountBody extends StatefulWidget {
  const AccountBody({
    super.key,
    required this.ledger,
    required this.nav,
    required this.account,
  });

  final Ledger ledger;
  final Nav nav;
  final Account account;

  @override
  State<AccountBody> createState() => _AccountBodyState();
}

class _AccountBodyState extends State<AccountBody> {
  var _week = 3;
  late var _month = (widget.ledger.today.year, widget.ledger.today.month);

  /// Opens the composer on a spending from [account].
  void _record(Account account) {
    final ledger = widget.ledger;
    widget.nav.compose(
      type: EntryType.expense,
      draft: Entry(
        id: '',
        date: ledger.today,
        type: EntryType.expense,
        amount: 0,
        account: account.id,
      ),
    );
  }

  /// Opens the composer on a transfer out of [account]. A card has a page
  /// of its own, which pays its statement.
  void _move(Account account) => widget.nav.compose(
    type: EntryType.transfer,
    draft: widget.ledger.transferDrafts.move(account.id),
  );

  /// How much [entries] of one day changed the account's balance.
  int _dayChange(List<Entry> entries) => entries.fold<int>(
    0,
    (sum, e) => sum + widget.ledger.balanceService.effect(e, widget.account.id),
  );

  @override
  Widget build(BuildContext context) {
    final ledger = widget.ledger;
    final account = widget.account;
    final balance = ledger.balanceService.balance(account.id);
    final code = account.currency;
    final weeks = ledger.balanceService.weeklyChanges(account.id);
    final today = ledger.today;
    final (year, month) = _month;
    final entries = [
      // Exception to as-of-today: the month's list shows 預定 entries marked;
      // nothing is summed.
      for (final e in ledger.entries.inMonth(year, month))
        if (e.account == account.id || e.to == account.id) e,
    ]..sort((a, b) => b.date.compareTo(a.date));
    final days = <DateTime, List<Entry>>{};
    for (final e in entries) {
      (days[e.date] ??= []).add(e);
    }
    // 對帳 needs NT$: another currency would need a rate.
    final reconcilable = !account.foreign;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AccountActions(
          onRecord: () => _record(account),
          onMove: () => _move(account),
          onReconcile: reconcilable
              ? () => reconcileAccount(context, ledger, account)
              : null,
        ),
        const SectionTitle('近四週'),
        Waterfall(
          weeks: weeks,
          balance: balance,
          selected: _week,
          onSelect: (week) => setState(() => _week = week),
          currency: code,
          hidden: ledger.amounts.hidden,
        ),
        SectionTitle(
          '紀錄',
          trailing: MonthSwitch(
            month: _month,
            latest: (today.year, today.month),
            onChanged: (m) => setState(() => _month = m),
          ),
        ),
        if (entries.isEmpty) const Text('這個月沒有紀錄', style: mutedText),
        for (final MapEntry(key: day, value: list) in days.entries) ...[
          _DayHeading(
            day: day,
            total: ledger.orDots(amountIn(_dayChange(list), code)),
          ),
          GroupBox(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final e in list)
                  EntryRow(
                    ledger: ledger,
                    entry: e,
                    onOpen: widget.nav.showEntry,
                    divider: !identical(e, list.last),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// The row of what is done with an account: 記一筆, a transfer, and 對帳
/// when [onReconcile] is given.
class _AccountActions extends StatelessWidget {
  const _AccountActions({
    required this.onRecord,
    required this.onMove,
    required this.onReconcile,
  });

  final VoidCallback onRecord;
  final VoidCallback onMove;

  /// Opens 對帳; null when the account cannot be reconciled.
  final VoidCallback? onReconcile;

  @override
  Widget build(BuildContext context) {
    final onReconcile = this.onReconcile;
    return Padding(
      padding: const EdgeInsets.only(top: Space.s2),
      child: Row(
        children: [
          Expanded(
            child: AccountAction(
              icon: Glyph.add,
              label: '記一筆',
              onTap: onRecord,
            ),
          ),
          const SizedBox(width: Space.s2),
          Expanded(
            child: AccountAction(
              icon: Glyph.transfer,
              label: Words.transfer,
              onTap: onMove,
            ),
          ),
          if (onReconcile != null) ...[
            const SizedBox(width: Space.s2),
            Expanded(
              child: AccountAction(
                icon: Glyph.calculator,
                label: '對帳',
                onTap: onReconcile,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The heading over one day of an account's entries: the date, and how
/// much that day changed the balance.
class _DayHeading extends StatelessWidget {
  const _DayHeading({required this.day, required this.total});

  final DateTime day;

  /// The day's change, as shown money (dots when amounts are hidden).
  final String total;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.s1, Space.s2, Space.s1, Space.s2),
    child: Row(
      children: [
        Text(
          formatMMMEd(day),
          style: const TextStyle(
            fontSize: TextSize.small,
            fontWeight: FontWeight.w700,
          ),
        ),
        const Spacer(),
        Text(total, style: mutedSmall),
      ],
    ),
  );
}
