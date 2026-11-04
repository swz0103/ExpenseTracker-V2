import 'package:flutter/material.dart';

import '../look/figures.dart';
import '../look/glyphs.dart';
import '../look/icons.dart';
import '../look/theme.dart';
import '../look/widgets.dart';
import '../ledger/ledger.dart';

/// A bottom sheet with a title over [builder]'s content. The sheet's own
/// drag handle closes it (down to the page below, when opened from one);
/// a picker that only chooses something needs no back arrow of its own.
///
/// [height] gives the sheet a fixed share of the screen, as [sheetHeight]
/// for the pickers 記一筆 opens.
Future<T?> showChildPage<T>(
  BuildContext context, {
  required String title,
  required Widget Function(BuildContext) builder,
  double? height,
}) {
  return showSheet<T>(
    context,
    (context) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Flexible(child: builder(context)),
        ],
      ),
    ),
    capHeight: true,
    height: height,
  );
}

/// One choice in [pickOption].
final class Option<T> {
  const Option(this.value, this.label, this.icon, this.color);

  final T value;
  final String label;
  final Glyph icon;
  final Color color;
}

/// The open accounts as choices, each with its mark: of [among] when
/// given; only those kept in [currency] when it is given; and only those
/// [where] lets through.
List<Option<String>> accountOptions(
  Ledger ledger, {
  String? currency,
  bool Function(Account account)? where,
  List<Account>? among,
}) => [
  for (final a in among ?? ledger.openAccounts)
    if ((currency == null || a.currency == currency) &&
        (where == null || where(a)))
      Option(a.id, a.name, accountIcon(a), accountColor(a.kind)),
];

/// The open categories of income, or of spending, as choices; only those
/// [where] lets through when it is given.
List<Option<String>> categoryOptions(
  Ledger ledger, {
  required bool income,
  bool Function(Category category)? where,
}) => [
  for (final c in ledger.categoriesFor(income: income))
    if (where == null || where(c))
      Option(c.name, c.name, iconFor(c.icon), c.color),
];

/// A grid of choices, [columns] to a row; the chosen one has a coloured
/// background only.
Future<T?> pickOption<T>(
  BuildContext context, {
  required String title,
  required List<Option<T>> options,
  required T? selected,
  int columns = 4,
  double? height,
}) {
  return showChildPage<T>(
    context,
    title: title,
    height: height,
    builder: (context) => GridView.count(
      crossAxisCount: columns,
      shrinkWrap: true,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 0.95,
      children: [
        for (final option in options)
          Material(
            color: option.value == selected ? Hue.selected : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => Navigator.of(context).pop(option.value),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconBadge(option.icon, option.color, size: 40),
                  const SizedBox(height: 6),
                  Text(
                    option.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}

/// The open accounts to choose from, two to a row in groups by kind:
/// banks, cash, then cards and e-wallets, then the rest; each with its
/// balance. Of [among] when given, and only those kept in [currency]
/// when it is given.
Future<String?> pickAccount(
  BuildContext context,
  Ledger ledger, {
  required String title,
  required String? selected,
  String? currency,
  List<Account>? among,
  double? height = sheetHeight,
}) {
  final open = [
    for (final a in among ?? ledger.openAccounts)
      if (currency == null || a.currency == currency) a,
  ];
  final groups = [
    ('銀行', {AccountKind.bank}),
    ('現金', {AccountKind.cash}),
    ('卡片與電子支付', {AccountKind.card, AccountKind.wallet}),
    ('其他', {AccountKind.loan, AccountKind.receivable}),
  ];
  return showChildPage<String>(
    context,
    title: title,
    height: height,
    builder: (context) => ListView(
      shrinkWrap: true,
      children: [
        for (final (name, kinds) in groups)
          if (open.any((a) => kinds.contains(a.kind))) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 8, 2, 6),
              child: Text(
                name,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Hue.faint,
                ),
              ),
            ),
            _Pairs([
              for (final a in open)
                if (kinds.contains(a.kind))
                  _AccountChoice(
                    account: a,
                    balance: ledger.moneyIn(ledger.balance(a.id), a.currency),
                    picked: a.id == selected,
                    onTap: () => Navigator.of(context).pop(a.id),
                  ),
            ]),
          ],
      ],
    ),
  );
}

/// Widgets two to a row, the last alone on the left when odd.
class _Pairs extends StatelessWidget {
  const _Pairs(this.children);

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < children.length; i += 2)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(child: children[i]),
                const SizedBox(width: 8),
                Expanded(
                  child: i + 1 < children.length
                      ? children[i + 1]
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// One account in [pickAccount]: its mark, name and balance.
class _AccountChoice extends StatelessWidget {
  const _AccountChoice({
    required this.account,
    required this.balance,
    required this.picked,
    required this.onTap,
  });

  final Account account;
  final String balance;
  final bool picked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(14);
    return Material(
      color: picked ? Hue.selected : Hue.surface,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: picked
            ? const BorderSide(color: Hue.accent, width: 1.5)
            : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                IconBadge(
                  accountIcon(account),
                  accountColor(account.kind),
                  size: 32,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        account.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        balance,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: Hue.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A month calendar, six rows from Monday; days after [latest] cannot
/// be chosen and days in [marked] have a soft background.
Future<DateTime?> pickDate(
  BuildContext context, {
  required String title,
  required DateTime selected,
  required DateTime latest,
  Set<DateTime> marked = const {},
  DateTime? today,
  double? height,
}) {
  return showChildPage<DateTime>(
    context,
    title: title,
    height: height,
    builder: (context) => _Calendar(
      selected: selected,
      latest: latest,
      marked: marked,
      today: today,
    ),
  );
}

class _Calendar extends StatefulWidget {
  const _Calendar({
    required this.selected,
    required this.latest,
    required this.marked,
    this.today,
  });

  final DateTime selected;
  final DateTime latest;
  final Set<DateTime> marked;

  /// Given, 今天, 昨天 and 前天 are picked at once above the calendar.
  final DateTime? today;

  @override
  State<_Calendar> createState() => _CalendarState();
}

class _CalendarState extends State<_Calendar> {
  late var _month = DateTime.utc(widget.selected.year, widget.selected.month);

  @override
  Widget build(BuildContext context) {
    final first = _month;
    final start = first.subtract(Duration(days: first.weekday - 1));
    final latest = widget.latest;
    final atEnd =
        first.year * 12 + first.month >= latest.year * 12 + latest.month;
    // The days written down most: picked at once, without the calendar.
    final today = widget.today;
    final quick = [
      if (today != null)
        for (final (i, name) in const ['今天', '昨天', '前天'].indexed)
          (name, today.subtract(Duration(days: i))),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (quick.isNotEmpty)
          Row(
            children: [
              for (final (name, day) in quick) ...[
                ChoicePill(
                  label: name,
                  selected: day == widget.selected,
                  onTap: () => Navigator.of(context).pop(day),
                ),
                const SizedBox(width: 6),
              ],
            ],
          ),
        const SizedBox(height: 4),
        StepSwitch(
          label: '${first.year} 年 ${first.month} 月',
          previousLabel: '上個月',
          nextLabel: '下個月',
          iconSize: 20,
          expand: true,
          onPrevious: () => setState(() {
            _month = DateTime.utc(first.year, first.month - 1);
          }),
          onNext: atEnd
              ? null
              : () => setState(() {
                  _month = DateTime.utc(first.year, first.month + 1);
                }),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final name in weekdayNames)
              Expanded(
                child: Text(
                  name,
                  textAlign: TextAlign.center,
                  style: mutedSmall,
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        for (var week = 0; week < 6; week++)
          Row(
            children: [
              for (var d = 0; d < 7; d++)
                Expanded(child: _day(start.add(Duration(days: week * 7 + d)))),
            ],
          ),
      ],
    );
  }

  Widget _day(DateTime day) {
    final inMonth = day.month == _month.month;
    final future = day.isAfter(widget.latest);
    final picked = day == widget.selected;
    final weekend = day.weekday >= DateTime.saturday;
    // Only the chosen day is filled; a day with entries has a dot.
    final ink = picked
        ? Hue.onAccent
        : !inMonth || future
        ? Hue.faint
        : weekend
        ? Hue.negative
        : Hue.ink;
    final dotted = inMonth && !picked && widget.marked.contains(day);
    return Padding(
      padding: const EdgeInsets.all(2.5),
      child: Material(
        color: picked ? Hue.accent : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: future || !inMonth
              ? null
              : () => Navigator.of(context).pop(day),
          child: SizedBox(
            height: 40,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${day.day}',
                  style: TextStyle(
                    color: ink,
                    fontWeight: picked ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
                if (dotted)
                  Container(
                    width: 4,
                    height: 4,
                    margin: const EdgeInsets.only(top: 2),
                    decoration: const BoxDecoration(
                      color: Hue.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
