import 'dart:math';

import 'package:flutter/material.dart';

import '../compose/account_editor.dart';
import '../../../core/look/figures.dart';
import '../../../core/look/glyphs.dart';
import '../../../core/look/haptics.dart';
import '../../../core/look/icons.dart';
import '../../../core/look/theme.dart';
import '../../../core/look/widgets.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/nav.dart';
import 'account_card.dart';

/// The kinds 我的帳戶 holds, in the order 依類型重新排 puts them. Money
/// paid for someone and loans have a page of their own.
const walletKinds = [
  AccountKind.bank,
  AccountKind.wallet,
  AccountKind.cash,
  AccountKind.card,
];

/// The open accounts of [walletKinds]: those placed on 我的帳戶 in their
/// places, then the others by kind.
List<Account> walletAccounts(Ledger ledger) {
  final open = [
    for (final a in ledger.openAccounts)
      if (walletKinds.contains(a.kind)) a,
  ];
  final order = {for (final (i, a) in open.indexed) a.id: i};
  int rank(Account a) => walletKinds.indexOf(a.kind);
  return open..sort((a, b) {
    final pa = a.place, pb = b.place;
    if (pa != null && pb != null && pa != pb) return pa.compareTo(pb);
    if (pa != null && pb == null) return -1;
    if (pa == null && pb != null) return 1;
    final byKind = rank(a).compareTo(rank(b));
    return byKind != 0 ? byKind : order[a.id]!.compareTo(order[b.id]!);
  });
}

/// 我的帳戶: the net worth and what it is made of, then every account as
/// a card in one stack, the last in front. Each card opens its account.
class AccountsPage extends StatelessWidget {
  const AccountsPage({super.key, required this.ledger, required this.nav});

  final Ledger ledger;
  final Nav nav;

  Future<void> _sort(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => SortAccountsPage(ledger: ledger),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ledger,
      builder: (context, _) {
        final accounts = walletAccounts(ledger);
        final archived = [
          for (final a in ledger.accounts)
            if (a.archived && walletKinds.contains(a.kind)) a,
        ];
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          children: [
            PageHeader(
              '我的帳戶',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (accounts.length > 1)
                    TextButton(
                      onPressed: () => _sort(context),
                      style: TextButton.styleFrom(foregroundColor: Hue.accent),
                      child: const Text('排序'),
                    ),
                  TextButton.icon(
                    onPressed: () => editAccount(context, ledger),
                    icon: const GlyphIcon(Glyph.add, size: 16),
                    label: const Text('新增'),
                    style: TextButton.styleFrom(foregroundColor: Hue.ink),
                  ),
                ],
              ),
            ),
            _NetWorth(ledger: ledger),
            if (ledger.unrated.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '尚未取得臺銀匯率，${ledger.unrated.map((a) => a.name).join('、')}'
                  '暫不計入總額',
                  style: mutedSmall,
                ),
              ),
            SectionHead(
              '帳戶',
              trailing: Text('${accounts.length} 個', style: mutedSmall),
            ),
            if (accounts.isEmpty)
              const Text('還沒有帳戶，按右上的新增開始。', style: mutedSmall)
            else
              _Wallet(
                ledger: ledger,
                accounts: accounts,
                onOpen: (a) => nav.open(Pages.account(a.id)),
                onSort: () => _sort(context),
              ),
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
}

/// The net worth on the page's tinted block, how it moved since the end
/// of last month, and one bar of what it is made of.
class _NetWorth extends StatelessWidget {
  const _NetWorth({required this.ledger});

  final Ledger ledger;

  @override
  Widget build(BuildContext context) {
    final invest = ledger.investValue;
    var lent = 0;
    for (final a in ledger.accounts) {
      if (a.kind == AccountKind.receivable && a.inNetWorth) {
        final worth = ledger.worthOf(a);
        if (worth > 0) lent += worth;
      }
    }
    final debt = ledger.cardDebt + ledger.loanDebt;
    final saved = ledger.assets - invest - lent;
    final net = ledger.assets - debt;
    final today = ledger.today;
    final moved =
        net - ledger.netWorthAt(DateTime.utc(today.year, today.month, 0));
    final parts = [
      ('存款', saved, Hue.bank),
      ('投資', invest, Hue.holdings),
      ('代墊', lent, Hue.receivable),
      ('負債', debt, Hue.card),
    ];
    final shown = [
      for (final p in parts)
        if (p.$2 > 0) p,
    ];
    final total = shown.fold<int>(0, (sum, p) => sum + p.$2);
    return Tile(
      hero: true,
      icon: Glyph.wallet,
      label: '淨資產',
      value: ledger.money(net),
      valueColor: net < 0 ? Hue.negative : Hue.ink,
      trailing: moved == 0
          ? null
          : Pill(
              '${moved > 0 ? '↑' : '↓'} ${ledger.money(moved.abs())}',
              color: moved > 0 ? Hue.positive : Hue.negative,
            ),
      child: shown.isEmpty
          ? null
          : Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 8,
                    // Stretched: an empty box in a row is otherwise drawn
                    // no taller than nothing.
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final (i, (_, value, color)) in shown.indexed) ...[
                          if (i > 0) const SizedBox(width: 3),
                          Expanded(
                            flex: max(1, (value * 1000 / total).round()),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: color,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      for (final (name, value, color) in shown)
                        LegendKey(color, '$name ${ledger.money(value)}'),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}

/// The accounts as one stack of cards: the top strip of each, and the
/// last whole in front.
class _Wallet extends StatelessWidget {
  const _Wallet({
    required this.ledger,
    required this.accounts,
    required this.onOpen,
    required this.onSort,
  });

  final Ledger ledger;
  final List<Account> accounts;
  final ValueChanged<Account> onOpen;
  final VoidCallback onSort;

  @override
  Widget build(BuildContext context) {
    final last = accounts.length - 1;
    final (strip, front) = cardHeights(context);
    // How far each card sits below the one behind it.
    final step = strip - 12;
    return SizedBox(
      height: step * last + front,
      child: Stack(
        children: [
          for (final (i, a) in accounts.indexed)
            Positioned(
              top: step * i,
              left: 0,
              right: 0,
              child: AccountCard(
                ledger: ledger,
                account: a,
                front: i == last,
                onTap: () => onOpen(a),
                onLongPress: onSort,
              ),
            ),
        ],
      ),
    );
  }
}

/// 排序帳戶: the cards laid flat, each dragged by its handle. Nothing is
/// kept until 完成.
class SortAccountsPage extends StatefulWidget {
  const SortAccountsPage({super.key, required this.ledger});

  final Ledger ledger;

  @override
  State<SortAccountsPage> createState() => _SortAccountsPageState();
}

class _SortAccountsPageState extends State<SortAccountsPage> {
  late final _order = walletAccounts(widget.ledger);

  void _byKind() {
    final ledger = widget.ledger;
    final first = {for (final (i, a) in ledger.openAccounts.indexed) a.id: i};
    setState(() {
      _order.sort((a, b) {
        final byKind = walletKinds
            .indexOf(a.kind)
            .compareTo(walletKinds.indexOf(b.kind));
        return byKind != 0 ? byKind : first[a.id]!.compareTo(first[b.id]!);
      });
    });
  }

  void _done() {
    widget.ledger.placeAccounts([for (final a in _order) a.id]);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final ledger = widget.ledger;
    return Scaffold(
      backgroundColor: Hue.paper,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(foregroundColor: Hue.muted),
                    child: const Text('取消'),
                  ),
                  const Expanded(
                    child: Text(
                      '排序帳戶',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _done,
                    style: TextButton.styleFrom(foregroundColor: Hue.accent),
                    child: const Text('完成'),
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(8, 8, 8, 4),
                child: Text('按住右邊 ≡ 拖曳。最下面那張會展開在卡包最前面。', style: mutedSmall),
              ),
              Expanded(
                child: ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
                  itemCount: _order.length,
                  // [to] already counts the card taken out.
                  onReorderItem: (from, to) {
                    Haptics.selection();
                    setState(() => _order.insert(to, _order.removeAt(from)));
                  },
                  footer: Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: SoftPanel(
                      color: Hue.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 13,
                      ),
                      onTap: _byKind,
                      child: const Row(
                        children: [
                          Text(
                            '依類型重新排',
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Spacer(),
                          Text('銀行→支付→現金→卡', style: mutedSmall),
                        ],
                      ),
                    ),
                  ),
                  itemBuilder: (context, i) {
                    final a = _order[i];
                    final color = accountColor(a.kind);
                    return Padding(
                      key: ValueKey(a.id),
                      padding: const EdgeInsets.only(top: 8),
                      child: Container(
                        height: 56,
                        padding: const EdgeInsets.only(left: 14),
                        decoration: BoxDecoration(
                          color: softOf(color),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Row(
                          children: [
                            IconChip(accountIcon(a), color: color),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                a.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Text(
                              a.kind.isDebt
                                  ? ledger.money(-ledger.balance(a.id))
                                  : ledger.moneyIn(
                                      ledger.balance(a.id),
                                      a.currency,
                                    ),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Hue.muted,
                              ),
                            ),
                            ReorderableDragStartListener(
                              index: i,
                              child: Semantics(
                                label: '拖曳${a.name}',
                                child: const SizedBox(
                                  width: 48,
                                  height: 56,
                                  child: Center(child: _Grip()),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Three short lines, the handle a row is dragged by.
class _Grip extends StatelessWidget {
  const _Grip();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++)
          Container(
            width: 16,
            height: 2,
            margin: const EdgeInsets.symmetric(vertical: 1.5),
            decoration: BoxDecoration(
              color: Hue.faint,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
      ],
    );
  }
}
