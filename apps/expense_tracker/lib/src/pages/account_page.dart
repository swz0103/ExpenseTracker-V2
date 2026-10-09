import 'package:flutter/material.dart';

import '../charts/bar_scale.dart';
import '../charts/waterfall.dart';
import '../demo/ledger.dart';
import '../look/figures.dart';
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
  var _scale = BarScale.enlarged;
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
        final color = accountColor(account.kind);
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 0, 20, 32),
          children: [
            PageHeader(account.name, onBack: widget.nav.back),
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SoftPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            IconBadge(accountIcon(account), color, size: 30),
                            const SizedBox(width: 8),
                            Text(
                              groupName(account.kind),
                              style: const TextStyle(color: Hue.muted),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'TWD ${groupDigits(balance)}',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w600,
                            color: balance < 0 ? Hue.negative : Hue.ink,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: Figure(
                                '本月流入',
                                groupDigits(inflow),
                                color: Hue.positive,
                              ),
                            ),
                            Expanded(
                              child: Figure(
                                '本月流出',
                                groupDigits(outflow),
                                color: Hue.negative,
                              ),
                            ),
                          ],
                        ),
                        if (account.kind == AccountKind.card) ...[
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: () =>
                                  widget.nav.compose(type: EntryType.transfer),
                              child: const Text('繳卡款'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  SectionHead(
                    '近四週',
                    trailing: LinkToggle(
                      _scale.label,
                      onTap: () => setState(() => _scale = _scale.other),
                    ),
                  ),
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
        );
      },
    );
  }
}
