import 'dart:math';

import 'package:flutter/material.dart';

import '../look/figures.dart';
import '../look/glyphs.dart';
import '../look/icons.dart';
import '../look/theme.dart';
import '../look/widgets.dart';
import '../model/ledger.dart';
import 'account_editor.dart';
import 'nav.dart';

/// 我的帳戶: total assets and what they are made of, then every account
/// by group, two to a row. Each account opens its own page.
class AccountsPage extends StatelessWidget {
  const AccountsPage({super.key, required this.ledger, required this.nav});

  final Ledger ledger;
  final Nav nav;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ledger,
      builder: (context, _) {
        final invest = ledger.investValue;
        final cash = ledger.assets - invest;
        final debt = ledger.cardDebt + ledger.loanDebt;
        final archived = [
          for (final a in ledger.accounts)
            if (a.archived) a,
        ];
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          children: [
            PageHeader(
              '我的帳戶',
              trailing: TextButton.icon(
                onPressed: () => editAccount(context, ledger),
                icon: const GlyphIcon(Glyph.add, size: 16),
                label: const Text('新增'),
                style: TextButton.styleFrom(foregroundColor: Hue.ink),
              ),
            ),
            Tile(
              hero: true,
              icon: Glyph.wallet,
              label: '淨資產',
              value: money(ledger.assets - debt),
              valueColor: ledger.assets < debt ? Hue.negative : Hue.ink,
              child: _Balance(cash: cash, invest: invest, debt: debt),
            ),
            if (ledger.unrated.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '尚未取得臺銀匯率，${ledger.unrated.map((a) => a.name).join('、')}'
                  '暫不計入總額',
                  style: const TextStyle(fontSize: 13, color: Hue.muted),
                ),
              ),
            for (final kind in AccountKind.values) ..._group(kind),
            if (archived.isNotEmpty) ...[
              const SectionHead('已封存'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final a in archived)
                    ActionChip(
                      label: Text(a.name),
                      onPressed: () => editAccount(context, ledger, account: a),
                    ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }

  List<Widget> _group(AccountKind kind) {
    final accounts = [
      for (final a in ledger.openAccounts)
        if (a.kind == kind) a,
    ];
    if (accounts.isEmpty) return const [];
    final rows = <Widget>[];
    for (var i = 0; i < accounts.length; i += 2) {
      rows.add(
        IntrinsicHeight(
          child: Row(
            children: [
              Expanded(child: _cell(accounts[i])),
              VerticalDivider(
                width: 1,
                indent: 10,
                endIndent: 10,
                color: i + 1 < accounts.length ? Hue.line : Colors.transparent,
              ),
              Expanded(
                child: i + 1 < accounts.length
                    ? _cell(accounts[i + 1])
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      );
    }
    return [
      Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 8),
        child: Row(
          children: [
            Container(width: 3, height: 14, color: accountColor(kind)),
            const SizedBox(width: 8),
            Text(
              kind.isDebt ? '${groupName(kind)} · 待繳' : groupName(kind),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
      SoftPanel(
        color: Hue.white,
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Column(
          children: [
            for (final (i, row) in rows.indexed) ...[
              if (i > 0) const Divider(height: 1, indent: 14, endIndent: 14),
              row,
            ],
          ],
        ),
      ),
    ];
  }

  Widget _cell(Account account) {
    final balance = ledger.balance(account.id);
    return InkWell(
      onTap: () => nav.open(Pages.account(account.id)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            IconBadge(
              accountIcon(account),
              accountColor(account.kind),
              size: 34,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    account.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: Hue.muted),
                  ),
                  Text(
                    moneyIn(balance, account.currency),
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: balance < 0 ? Hue.negative : Hue.ink,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What the net worth is made of: the assets as savings and investments,
/// and the debt set against them, each bar to the same scale.
class _Balance extends StatelessWidget {
  const _Balance({
    required this.cash,
    required this.invest,
    required this.debt,
  });

  final int cash;
  final int invest;
  final int debt;

  @override
  Widget build(BuildContext context) {
    final assets = cash + invest;
    final scale = max(1, max(assets, debt));
    final share = assets <= 0 ? 0 : (invest * 100 / assets).round();
    // Widths from fractions of the larger side, so both bars share a scale.
    Widget bar(List<(int, Color)> parts) => LayoutBuilder(
      builder: (context, box) => ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Container(
          height: 8,
          color: Hue.track,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (value, color) in parts)
                if (value > 0)
                  Container(
                    width: box.maxWidth * min(1, value / scale),
                    height: 8,
                    color: color,
                  ),
            ],
          ),
        ),
      ),
    );
    Widget line(String label, int value, Widget barWidget) => Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 13, color: Hue.muted),
              ),
              const Spacer(),
              Text(
                money(value),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          barWidget,
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        line('資產', assets, bar([(cash, Hue.bank), (invest, Hue.investment)])),
        line('負債', debt, bar([(debt, Hue.negative)])),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            LegendKey(Hue.bank, '存款 ${money(cash)}・${100 - share}%'),
            LegendKey(Hue.investment, '投資 ${money(invest)}・$share%'),
          ],
        ),
      ],
    );
  }
}
