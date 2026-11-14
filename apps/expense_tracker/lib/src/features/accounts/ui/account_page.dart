import 'package:flutter/material.dart';

import '../../../core/charts/waterfall.dart';
import '../compose/account_editor.dart';
import 'reconcile_sheet.dart';
import '../../../core/look/figures.dart';
import '../../../core/look/glyphs.dart';
import '../../../core/look/icons.dart';
import '../../../core/look/theme.dart';
import '../../../core/look/widgets.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/ui/entry_tile.dart';
import '../../../core/nav.dart';

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
      listenable: ledger,
      builder: (context, _) {
        // Gone by another way, such as a restore: nothing to show.
        if (!ledger.hasAccount(widget.accountId)) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => widget.nav.back(),
          );
          return const SizedBox.shrink();
        }
        final account = ledger.account(widget.accountId);
        final balance = ledger.balance(account.id);
        final (into, out) = monthFlow(ledger, account);
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 0, 20, 32),
          children: [
            CenterHeader(
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
                  style: TextButton.styleFrom(foregroundColor: Hue.accent),
                  child: const Text('編輯'),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Tile(
                    hero: true,
                    icon: accountIcon(account),
                    label: groupName(account.kind),
                    value: ledger.moneyIn(balance, account.currency),
                    valueColor: balance < 0 ? Hue.negative : Hue.ink,
                    child: TileStats([
                      (Glyph.income, '本月流入', into, Hue.positive),
                      (Glyph.payout, '本月流出', out, Hue.negative),
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
  final today = ledger.today;
  var inflow = 0;
  var outflow = 0;
  for (final e in ledger.entriesIn(today.year, today.month)) {
    if (e.account != account.id && e.to != account.id) continue;
    final change = ledger.effect(e, account.id);
    if (change > 0) {
      inflow += change;
    } else {
      outflow -= change;
    }
  }
  return (
    ledger.moneyIn(inflow, account.currency),
    ledger.moneyIn(outflow, account.currency),
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

  /// Opens the composer on a transfer out of [account], or for a card a
  /// payment into it from the main account.
  void _move(Account account) {
    final ledger = widget.ledger;
    final main = ledger.mainAccount;
    final card = account.kind == AccountKind.card;
    widget.nav.compose(
      type: EntryType.transfer,
      draft: Entry(
        id: '',
        date: ledger.today,
        type: EntryType.transfer,
        amount: card ? ledger.statementDue(account) : 0,
        account: card || main == account.id ? main : account.id,
        category: transferCategory,
        to: card || main == account.id ? account.id : main,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ledger = widget.ledger;
    final account = widget.account;
    final balance = ledger.balance(account.id);
    final code = account.currency;
    final weeks = ledger.weeklyChanges(account.id);
    final today = ledger.today;
    final (year, month) = _month;
    final entries = [
      for (final e in ledger.entriesIn(year, month))
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
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              Expanded(
                child: _Action(
                  icon: Glyph.add,
                  label: '記一筆',
                  onTap: () => _record(account),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _Action(
                  icon: Glyph.transfer,
                  label: account.kind == AccountKind.card ? '繳卡費' : '轉帳',
                  onTap: () => _move(account),
                ),
              ),
              if (reconcilable) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: _Action(
                    icon: Glyph.calculator,
                    label: '對帳',
                    onTap: () => reconcileAccount(context, ledger, account),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SectionHead('近四週'),
        Waterfall(
          weeks: weeks,
          balance: balance,
          selected: _week,
          onSelect: (week) => setState(() => _week = week),
          currency: code,
          hidden: ledger.hidden,
        ),
        SectionHead(
          '紀錄',
          trailing: MonthSwitch(
            month: _month,
            latest: (today.year, today.month),
            onChanged: (m) => setState(() => _month = m),
          ),
        ),
        if (entries.isEmpty)
          const Text('這個月沒有紀錄', style: TextStyle(color: Hue.muted)),
        for (final MapEntry(key: day, value: list) in days.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
            child: Row(
              children: [
                Text(
                  longDay(day),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  ledger.orDots(
                    amountIn(
                      list.fold<int>(
                        0,
                        (sum, e) => sum + ledger.effect(e, account.id),
                      ),
                      code,
                    ),
                  ),
                  style: mutedSmall,
                ),
              ],
            ),
          ),
          SoftPanel(
            color: Hue.white,
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

/// One of the things done with an account, as a white tile.
class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.onTap});

  final Glyph icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SoftPanel(
      color: Hue.white,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      onTap: onTap,
      child: Column(
        children: [
          IconChip(icon, size: 28, background: Hue.tile),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
