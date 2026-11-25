import 'dart:math';

import 'package:flutter/material.dart';

import '../../../../design_system/display/amount.dart';
import '../forms/account_editor.dart';
import '../../../core/design_system/glyphs.dart';
import '../../../core/design_system/theme.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/navigation/nav.dart';
import '../../../core/widgets/shown_amounts.dart';
import '../../../core/design_system/shape.dart';
import '../../../core/design_system/spacing.dart';
import '../../../core/formatting/words.dart';
import '../../../core/messages/flow_messages.dart';

import 'package:core/time/utc_days.dart';

import 'sort_accounts.dart';
import 'wallet.dart';

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
      openFullScreen<void>(context, (_) => SortAccountsPage(ledger: ledger));

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      // Balances and net worth, foreign accounts and holdings valued at the
      // market.
      listenable: ledger.watch(const {
        Topic.entries,
        Topic.accounts,
        Topic.market,
      }),
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
                    style: wordButton(AppColors.accent),
                    child: const Text('排序'),
                  ),
                TextButton.icon(
                  onPressed: () => editAccount(context, ledger),
                  icon: const GlyphIcon(Glyph.add, size: 16),
                  label: const Text(Words.add),
                  style: wordButton(AppColors.ink),
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
              Words.account,
              trailing: Text(
                countOf(accounts.length, CountUnit.pieces),
                style: mutedSmall,
              ),
            ),
            if (accounts.isEmpty)
              const Text(FlowWords.noAccountsYet, style: mutedSmall)
            else
              Wallet(
                ledger: ledger,
                accounts: accounts,
                index: index,
                onShow: (a) => setState(() => _shown = a.id),
                onOpen: (a) => nav.open(AppRoutes.account(a.id)),
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
    final today = ledger.today;
    final worth = ledger.balanceService.netWorth(today);
    final net = worth.net;
    final moved =
        net -
        ledger.balanceService.netWorthAt(monthEnd(today.year, today.month - 1));
    final parts = [
      ('資產', worth.saved, AppColors.bank),
      (Words.investment, worth.invested, AppColors.holdings),
      (Words.lend, worth.lent, AppColors.receivable),
      ('負債', worth.owed, AppColors.card),
    ];
    final shown = [
      for (final p in parts)
        if (p.$2 > 0) p,
    ];
    return HeroFigure(
      icon: Glyph.wallet,
      label: '淨資產',
      value: ledger.money(net),
      valueColor: AppColors.ofBalance(net),
      trailing: moved == 0
          ? null
          : Pill(
              '${moved > 0 ? '↑' : '↓'} ${ledger.money(moved.abs())}',
              color: moved > 0 ? AppColors.positive : AppColors.negative,
            ),
      child: shown.isEmpty ? null : _MadeOf(ledger: ledger, shown: shown),
    );
  }
}

/// What the net worth is made of under it: one bar of [shown]'s shares,
/// and a key naming each with its sum.
class _MadeOf extends StatelessWidget {
  const _MadeOf({required this.ledger, required this.shown});

  final Ledger ledger;

  /// Each part's name, sum and colour, only those above nothing.
  final List<(String, int, Color)> shown;

  @override
  Widget build(BuildContext context) {
    final portions = visibleShares([for (final p in shown) p.$2]);
    return Padding(
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
                    flex: max(1, (portions[i] * 1000).round()),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(Radii.extraSmall),
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
    );
  }
}

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
