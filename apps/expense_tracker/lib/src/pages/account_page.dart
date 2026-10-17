import 'package:flutter/material.dart';

import '../charts/bar_scale.dart';
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
  static const _scale = BarScale.proportional;
  var _week = 3;

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
          final change = switch (e.type) {
            EntryType.income ||
            EntryType.sell ||
            EntryType.dividend => e.amount,
            EntryType.transfer => e.to == account.id ? e.arrived : -e.amount,
            _ => -e.amount,
          };
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
                  const SectionHead('近四週'),
                  Waterfall(
                    weeks: weeks,
                    balance: balance,
                    scale: _scale,
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
