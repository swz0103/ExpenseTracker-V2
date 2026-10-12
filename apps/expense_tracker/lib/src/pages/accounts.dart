import 'package:flutter/material.dart';

import '../demo/ledger.dart';
import '../look/figures.dart';
import '../look/glyphs.dart';
import '../look/icons.dart';
import '../look/theme.dart';
import '../look/widgets.dart';
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
        String shown(int value) => ledger.hidden ? '••••' : groupDigits(value);
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
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
              label: '資產總額',
              value: shown(ledger.assets),
              sub: '淨資產 ${shown(ledger.assets - debt)}（扣除卡費）',
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    height: 8,
                    child: Row(
                      children: [
                        Expanded(
                          flex: cash < 1 ? 1 : cash,
                          child: Container(color: Hue.bank),
                        ),
                        const SizedBox(width: 2),
                        Expanded(
                          flex: invest < 1 ? 1 : invest,
                          child: Container(color: Hue.investment),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            TileRow([
              Tile(icon: Glyph.bank, label: '存款', value: shown(cash), size: 17),
              Tile(
                icon: Glyph.investment,
                label: '投資',
                value: shown(invest),
                size: 17,
                onTap: () => nav.open(Pages.investments),
              ),
              Tile(
                icon: Glyph.card,
                label: '負債',
                value: shown(debt),
                valueColor: debt > 0 ? Hue.negative : Hue.ink,
                size: 17,
              ),
            ]),
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
        Row(
          children: [
            Expanded(child: _cell(accounts[i])),
            Expanded(
              child: i + 1 < accounts.length
                  ? _cell(accounts[i + 1])
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      );
    }
    final total = accounts.fold<int>(0, (sum, a) => sum + ledger.balance(a.id));
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
            const Spacer(),
            Text(
              ledger.hidden ? '••••' : groupDigits(total.abs()),
              style: const TextStyle(fontSize: 12, color: Hue.muted),
            ),
          ],
        ),
      ),
      SoftPanel(
        color: Hue.white,
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Column(children: rows),
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
                    ledger.hidden ? '••••' : groupDigits(balance),
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
