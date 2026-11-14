part of 'accounts.dart';

class _SortAccountsPageState extends State<SortAccountsPage> {
  late final _order = walletAccounts(widget.ledger);
  var _by = _SortBy.hand;

  void _sortBy(_SortBy by) {
    final ledger = widget.ledger;
    Haptics.selection();
    setState(() {
      _by = by;
      switch (by) {
        case _SortBy.hand:
          _order
            ..clear()
            ..addAll(walletAccounts(ledger));
        case _SortBy.balance:
          _order.sort((a, b) => ledger.worthOf(b).compareTo(ledger.worthOf(a)));
        case _SortBy.recent:
          final last = <String, DateTime>{};
          for (final e in ledger.entries) {
            for (final id in [e.account, ?e.to]) {
              final seen = last[id];
              if (seen == null || e.date.isAfter(seen)) last[id] = e.date;
            }
          }
          final never = DateTime.utc(1);
          _order.sort(
            (a, b) => (last[b.id] ?? never).compareTo(last[a.id] ?? never),
          );
      }
    });
  }

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
                    style: wordButton(Hue.muted),
                    child: const Text('取消'),
                  ),
                  const Expanded(
                    child: Text(
                      '排序帳戶',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: TextSize.title,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _done,
                    style: wordButton(Hue.accent),
                    child: const Text('完成'),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Row(
                  children: [
                    for (final (i, (by, label)) in const [
                      (_SortBy.hand, '手動'),
                      (_SortBy.balance, '餘額'),
                      (_SortBy.recent, '最近使用'),
                    ].indexed) ...[
                      if (i > 0) const SizedBox(width: 6),
                      Expanded(
                        child: ChoicePill(
                          label: label,
                          selected: by == _by,
                          onTap: () => _sortBy(by),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
                  itemCount: _order.length,
                  // [to] already counts the card taken out.
                  onReorderStart: (_) => Haptics.medium(),
                  // The card taken up grows a little and casts a shadow.
                  proxyDecorator: (child, index, lift) => AnimatedBuilder(
                    animation: lift,
                    builder: (context, child) {
                      final t = Curves.easeOut.transform(lift.value);
                      return Transform.scale(
                        scale: 1 + 0.04 * t,
                        child: Material(
                          color: Colors.transparent,
                          elevation: 10 * t,
                          shadowColor: Hue.lift,
                          borderRadius: BorderRadius.circular(18),
                          child: child,
                        ),
                      );
                    },
                    child: child,
                  ),
                  onReorderItem: (from, to) {
                    Haptics.selection();
                    setState(() {
                      _order.insert(to, _order.removeAt(from));
                      _by = _SortBy.hand;
                    });
                  },
                  footer: Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: SoftPanel(
                      color: Hue.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 13,
                      ),
                      onTap: () {
                        _byKind();
                        setState(() => _by = _SortBy.hand);
                      },
                      child: const Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        spacing: 12,
                        children: [
                          Text(
                            '依類型重新排',
                            style: TextStyle(
                              fontSize: TextSize.body,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text('銀行→支付→現金→卡', style: mutedSmall),
                        ],
                      ),
                    ),
                  ),
                  itemBuilder: (context, i) {
                    final a = _order[i];
                    final color = accountHue(a);
                    // Held anywhere, the card lifts and follows the finger;
                    // the handle takes it at once.
                    return ReorderableDelayedDragStartListener(
                      key: ValueKey(a.id),
                      index: i,
                      child: Padding(
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
                                    fontSize: TextSize.body,
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
                                  fontSize: TextSize.body,
                                  fontWeight: FontWeight.w700,
                                  color: Hue.muted,
                                ),
                              ),
                              // The whole square takes the finger, not only
                              // the lines drawn in it.
                              ReorderableDragStartListener(
                                index: i,
                                child: Semantics(
                                  label: '拖曳${a.name}',
                                  child: const ColoredBox(
                                    color: Colors.transparent,
                                    child: SizedBox(
                                      width: 56,
                                      height: 56,
                                      child: Center(child: _Grip()),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
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
            width: 20,
            height: 2.5,
            margin: const EdgeInsets.symmetric(vertical: 2),
            decoration: BoxDecoration(
              color: Hue.muted,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
      ],
    );
  }
}
