import 'package:flutter/material.dart';

import '../charts/waterfall.dart';
import '../look/figures.dart';
import '../look/glyphs.dart';
import '../look/icons.dart';
import '../look/theme.dart';
import '../look/widgets.dart';
import '../model/ledger.dart';
import 'account_editor.dart';
import 'entry_tile.dart';
import 'nav.dart';

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
        category: '轉帳',
        note: lend ? '代墊 ${account.name}' : '${account.name}還款',
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
        final into = moneyIn(inflow, code);
        final out = moneyIn(outflow, code);
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 0, 20, 32),
          children: [
            PageHeader(
              account.name,
              onBack: widget.nav.back,
              trailing: TextButton(
                onPressed: () => editAccount(context, ledger, account: account),
                style: TextButton.styleFrom(foregroundColor: Hue.accent),
                child: const Text('編輯'),
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
                    value: moneyIn(balance, account.currency),
                    valueColor: balance < 0 ? Hue.negative : Hue.ink,
                    child: TileStats([
                      (Glyph.income, '本月流入', into, Hue.positive),
                      (Glyph.payout, '本月流出', out, Hue.negative),
                    ]),
                  ),
                  if (account.kind == AccountKind.receivable)
                    _Owed(
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
                            EntryTile(
                              ledger: ledger,
                              entry: e,
                              onTap: () => widget.nav.showEntry(e),
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
    required this.account,
    required this.balance,
    required this.onLend,
    required this.onRepaid,
  });

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
                ? '${account.name}還欠 ${moneyIn(balance, account.currency)}'
                : '${account.name}沒有欠款',
            style: const TextStyle(fontSize: 13, color: Hue.muted),
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
