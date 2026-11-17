import 'dart:math';

import 'package:flutter/material.dart';

import '../compose/account_editor.dart';
import '../../../core/look/glyphs.dart';
import '../../../core/look/haptics.dart';
import '../../../core/ui/icons.dart';
import '../../../core/look/theme.dart';
import '../../../core/look/widgets.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/nav.dart';
import 'account_card.dart';
import '../../../core/ui/shown_amounts.dart';
import '../../../core/look/shape.dart';
import '../../../core/look/spacing.dart';

part 'sort_accounts.dart';
part 'wallet.dart';

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
    for (final a in ledger.accounts.open)
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
/// a card in one stack, one in front. A tap on a card behind slides it to
/// the front, and held and moved up or down the cards turn through the
/// front; a tap on the front card opens its account. 排序 sets the order.
class AccountsPage extends StatefulWidget {
  const AccountsPage({super.key, required this.ledger, required this.nav});

  final Ledger ledger;
  final Nav nav;

  @override
  State<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends State<AccountsPage> {
  Ledger get ledger => widget.ledger;
  Nav get nav => widget.nav;

  /// The account in front, kept while the app runs; null for the last.
  static String? _shown;

  Future<void> _sort(BuildContext context) =>
      openFlow<void>(context, (_) => SortAccountsPage(ledger: ledger));

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ledger,
      builder: (context, _) {
        final accounts = walletAccounts(ledger);
        final archived = [
          for (final a in ledger.accounts.all)
            if (a.archived && walletKinds.contains(a.kind)) a,
        ];
        final at = accounts.indexWhere((a) => a.id == _shown);
        final index = at < 0 ? accounts.length - 1 : at;
        return HeadedList(
          padding: const EdgeInsets.fromLTRB(Space.s5, 0, Space.s5, Space.s4),
          header: PageHeader(
            '我的帳戶',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (accounts.length > 1)
                  TextButton(
                    onPressed: () => _sort(context),
                    style: wordButton(Hue.accent),
                    child: const Text('排序'),
                  ),
                TextButton.icon(
                  onPressed: () => editAccount(context, ledger),
                  icon: const GlyphIcon(Glyph.add, size: 16),
                  label: const Text('新增'),
                  style: wordButton(Hue.ink),
                ),
              ],
            ),
          ),
          children: [
            _NetWorth(ledger: ledger),
            if (ledger.balanceService.unrated.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: Space.s2),
                child: Text(
                  '尚未取得臺銀匯率，${ledger.balanceService.unrated.map((a) => a.name).join('、')}'
                  '暫不計入總額',
                  style: mutedSmall,
                ),
              ),
            SectionTitle(
              '帳戶',
              trailing: Text('${accounts.length} 個', style: mutedSmall),
            ),
            if (accounts.isEmpty)
              const Text('還沒有帳戶，按右上的新增開始。', style: mutedSmall)
            else
              _Wallet(
                ledger: ledger,
                accounts: accounts,
                index: index,
                onShow: (a) => setState(() => _shown = a.id),
                onOpen: (a) => nav.open(Pages.account(a.id)),
              ),
            if (archived.isNotEmpty) ...[
              const SectionTitle('已封存'),
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
    final invest = ledger.holdings.marketValue;
    var lent = 0;
    for (final a in ledger.accounts.all) {
      if (a.kind == AccountKind.receivable && a.inNetWorth) {
        final worth = ledger.balanceService.worthOf(a);
        if (worth > 0) lent += worth;
      }
    }
    final debt =
        ledger.balanceService.cardDebt + ledger.balanceService.loanDebt;
    final saved = ledger.balanceService.assets - invest - lent;
    final net = ledger.balanceService.assets - debt;
    final today = ledger.today;
    final moved =
        net -
        ledger.balanceService.netWorthAt(
          DateTime.utc(today.year, today.month, 0),
        );
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
    final shares = visibleShares([for (final p in shown) p.$2]);
    return HeroFigure(
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
              padding: const EdgeInsets.only(top: Space.s2),
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
                        for (final (i, (_, _, color)) in shown.indexed) ...[
                          if (i > 0) const SizedBox(width: Space.half),
                          Expanded(
                            flex: max(1, (shares[i] * 1000).round()),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: color,
                                borderRadius: BorderRadius.circular(
                                  Radii.extraSmall,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: Space.s2),
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

/// 排序帳戶: the cards laid flat, each dragged by its handle. Nothing is
/// kept until 完成.
class SortAccountsPage extends StatefulWidget {
  const SortAccountsPage({super.key, required this.ledger});

  final Ledger ledger;

  @override
  State<SortAccountsPage> createState() => _SortAccountsPageState();
}

/// How 排序帳戶 lines the cards up: by hand, the most money first, or
/// the one used last first.
enum _SortBy { hand, balance, recent }

/// Each of [values]' share of a bar, every one at least [least] of it so
/// even a small sum shows; the rest is shared among the larger ones by
/// size.
List<double> visibleShares(List<int> values, {double least = 0.06}) {
  final total = values.fold<int>(0, (sum, v) => sum + v);
  if (total <= 0) return [for (final _ in values) 1 / values.length];
  final small = {
    for (final (i, v) in values.indexed)
      if (v / total < least) i,
  };
  final rest = 1 - least * small.length;
  final big = [
    for (final (i, v) in values.indexed)
      if (!small.contains(i)) v,
  ].fold<int>(0, (sum, v) => sum + v);
  return [
    for (final (i, v) in values.indexed)
      small.contains(i) ? least : (big == 0 ? 0 : v / big * rest),
  ];
}
