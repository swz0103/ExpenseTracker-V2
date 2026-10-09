import 'package:flutter/material.dart';

import '../demo/ledger.dart';
import '../look/figures.dart';
import '../look/glyphs.dart';
import '../look/icons.dart';
import '../look/theme.dart';
import '../look/widgets.dart';
import 'nav.dart';

/// 我的帳戶: total assets and what they are made of, then every account
/// by group, two to a row. Each account opens its own page.
class AccountsPage extends StatelessWidget {
  const AccountsPage({super.key, required this.ledger, required this.nav});

  final Ledger ledger;
  final Nav nav;

  Future<void> _create(BuildContext context) async {
    final name = TextEditingController();
    final opening = TextEditingController();
    var kind = AccountKind.bank;
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          backgroundColor: Hue.panel,
          title: const Text('新增帳戶'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                decoration: const InputDecoration(labelText: '名稱'),
              ),
              TextField(
                controller: opening,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '目前餘額'),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final k in AccountKind.values)
                    ChoiceChip(
                      label: Text(groupName(k)),
                      selected: k == kind,
                      onSelected: (_) => setDialog(() => kind = k),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('新增'),
            ),
          ],
        ),
      ),
    );
    final title = name.text.trim();
    final amount = int.tryParse(opening.text.trim()) ?? 0;
    name.dispose();
    opening.dispose();
    if (created != true || title.isEmpty) return;
    final balance = kind == AccountKind.card ? -amount.abs() : amount;
    ledger.addAccount(
      Account('account-${ledger.newId()}', title, kind, balance),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ledger,
      builder: (context, _) {
        var cash = 0;
        for (final a in ledger.accounts) {
          if (a.kind != AccountKind.card) cash += ledger.balance(a.id);
        }
        final invest = ledger.investValue;
        final debt = ledger.cardDebt;
        String shown(int value) => ledger.hidden ? '••••' : groupDigits(value);
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          children: [
            PageHeader(
              '我的帳戶',
              trailing: TextButton.icon(
                onPressed: () => _create(context),
                icon: const GlyphIcon(Glyph.add, size: 16),
                label: const Text('新增'),
                style: TextButton.styleFrom(foregroundColor: Hue.ink),
              ),
            ),
            SoftPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '資產總額',
                    style: TextStyle(fontSize: 12, color: Hue.muted),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      const Text(
                        'TWD',
                        style: TextStyle(fontSize: 12, color: Hue.muted),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        shown(ledger.assets),
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      height: 8,
                      child: Row(
                        children: [
                          Expanded(
                            flex: cash < 1 ? 1 : cash,
                            child: Container(color: const Color(0xFF6B8C6B)),
                          ),
                          Expanded(
                            flex: invest < 1 ? 1 : invest,
                            child: Container(color: const Color(0xFFA99BC0)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  IntrinsicHeight(
                    child: Row(
                      children: [
                        Expanded(child: Figure('現金與存款', shown(cash))),
                        const VerticalDivider(color: Hue.faint),
                        Expanded(child: Figure('投資市值', shown(invest))),
                        const VerticalDivider(color: Hue.faint),
                        Expanded(
                          child: Figure(
                            '待繳卡款',
                            shown(debt),
                            color: debt > 0 ? Hue.negative : Hue.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: FilledButton.icon(
                      onPressed: () => nav.compose(type: EntryType.transfer),
                      icon: const GlyphIcon(Glyph.transfer, size: 18),
                      label: const Text('帳戶轉帳／繳卡款'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF5B7B5F),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SectionHead('帳戶一覽'),
            for (final kind in AccountKind.values) ..._group(kind),
          ],
        );
      },
    );
  }

  List<Widget> _group(AccountKind kind) {
    final accounts = [
      for (final a in ledger.accounts)
        if (a.kind == kind) a,
    ];
    if (accounts.isEmpty) return const [];
    final rows = <Widget>[];
    for (var i = 0; i < accounts.length; i += 2) {
      rows.add(
        Row(
          children: [
            Expanded(child: _cell(accounts[i])),
            const SizedBox(width: 16),
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
        padding: const EdgeInsets.only(top: 18, bottom: 2),
        child: Row(
          children: [
            Text(
              groupName(kind),
              style: const TextStyle(fontSize: 13, color: Hue.muted),
            ),
            const Spacer(),
            Text(
              groupDigits(total),
              style: const TextStyle(fontSize: 13, color: Hue.muted),
            ),
          ],
        ),
      ),
      ...rows,
    ];
  }

  Widget _cell(Account account) {
    final balance = ledger.balance(account.id);
    return InkWell(
      onTap: () => nav.open(Pages.account(account.id)),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Hue.line)),
        ),
        child: Row(
          children: [
            IconBadge(
              accountIcon(account.kind),
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
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      ledger.hidden ? '••••' : groupDigits(balance),
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: balance < 0 ? Hue.negative : Hue.ink,
                      ),
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
