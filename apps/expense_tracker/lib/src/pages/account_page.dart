import 'package:flutter/material.dart';

import '../charts/bar_scale.dart';
import '../charts/waterfall.dart';
import '../demo/ledger.dart';
import '../look/figures.dart';
import '../look/glyphs.dart';
import '../look/icons.dart';
import '../look/theme.dart';
import '../look/widgets.dart';
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
            EntryType.transfer => e.to == account.id ? e.amount : -e.amount,
            _ => -e.amount,
          };
          if (change > 0) {
            inflow += change;
          } else {
            outflow -= change;
          }
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 0, 20, 32),
          children: [
            PageHeader(account.name, onBack: widget.nav.back),
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Tile(
                    hero: true,
                    icon: accountIcon(account),
                    label: groupName(account.kind),
                    value: money(balance),
                    valueColor: balance < 0 ? Hue.negative : Hue.ink,
                    child: TileStats([
                      (Glyph.income, '本月流入', money(inflow), Hue.positive),
                      (Glyph.payout, '本月流出', money(outflow), Hue.negative),
                    ]),
                  ),
                  const SectionHead('近四週'),
                  Waterfall(
                    weeks: weeks,
                    balance: balance,
                    scale: _scale,
                    selected: _week,
                    onSelect: (week) => setState(() => _week = week),
                  ),
                  const SectionHead('本月紀錄'),
                  if (entries.isEmpty)
                    const Text('本月沒有紀錄', style: TextStyle(color: Hue.muted)),
                  if (entries.isNotEmpty)
                    SoftPanel(
                      color: Hue.white,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
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
