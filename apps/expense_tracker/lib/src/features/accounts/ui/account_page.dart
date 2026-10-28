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

/// One account: its balance, four weeks of changes as a waterfall, and
/// this month's entries.
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
  var _week = 3;

  /// Opens the composer on money paid for someone, from the main account
  /// into [account] ([lend]), or on money paid back, all that is owed by
  /// default.
  void _move(Account account, {required bool lend}) {
    final ledger = widget.ledger;
    final main = ledger.mainAccount;
    final owed = ledger.balance(account.id);
    widget.nav.compose(
      type: EntryType.transfer,
      draft: Entry(
        id: '',
        date: ledger.today,
        type: EntryType.transfer,
        amount: lend || owed < 0 ? 0 : owed,
        account: lend ? main : account.id,
        category: transferCategory,
        to: lend ? account.id : main,
      ),
    );
  }

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
        final code = account.currency;
        final weeks = ledger.weeklyChanges(account.id);
        final today = ledger.today;
        final entries = [
          for (final e in ledger.entriesIn(today.year, today.month))
            if (e.account == account.id || e.to == account.id) e,
        ];
        var inflow = 0;
        var outflow = 0;
        for (final e in entries) {
          final change = ledger.effect(e, account.id);
          if (change > 0) {
            inflow += change;
          } else {
            outflow -= change;
          }
        }
        final into = ledger.moneyIn(inflow, code);
        final out = ledger.moneyIn(outflow, code);
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 0, 20, 32),
          children: [
            PageHeader(
              account.name,
              onBack: widget.nav.back,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 對帳 needs NT$: another currency would need a rate.
                  if (!account.foreign && account.kind != AccountKind.receivable)
                    TextButton(
                      onPressed: () => reconcileAccount(context, ledger, account),
                      style: TextButton.styleFrom(foregroundColor: Hue.accent),
                      child: const Text('對帳'),
                    ),
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
                  if (account.kind == AccountKind.receivable)
                    _Owed(
                      ledger: ledger,
                      account: account,
                      balance: balance,
                      onLend: () => _move(account, lend: true),
                      onRepaid: () => _move(account, lend: false),
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
                  const SectionHead('本月紀錄'),
                  if (entries.isEmpty)
                    const Text('本月沒有紀錄', style: TextStyle(color: Hue.muted)),
                  if (entries.isNotEmpty)
                    SoftPanel(
                      color: Hue.white,
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (final e in entries)
                            EntryRow(
                              ledger: ledger,
                              entry: e,
                              onOpen: widget.nav.showEntry,
                              divider: !identical(e, entries.last),
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

/// What [account], money paid for someone, still has owed, with the two
/// things done with it: paying for them again, or taking money back.
class _Owed extends StatelessWidget {
  const _Owed({
    required this.ledger,
    required this.account,
    required this.balance,
    required this.onLend,
    required this.onRepaid,
  });

  final Ledger ledger;
  final Account account;
  final int balance;
  final VoidCallback onLend;
  final VoidCallback onRepaid;

  @override
  Widget build(BuildContext context) {
    final style = OutlinedButton.styleFrom(
      foregroundColor: Hue.accent,
      minimumSize: const Size.fromHeight(44),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            balance > 0
                ? '${account.name}還欠 ${ledger.moneyIn(balance, account.currency)}'
                : '${account.name}沒有欠款',
            style: mutedSmall,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onLend,
                  style: style,
                  child: const Text('幫忙付'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: balance > 0 ? onRepaid : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: Hue.accent,
                    minimumSize: const Size.fromHeight(44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(balance > 0 ? '收回全部' : '收回'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
