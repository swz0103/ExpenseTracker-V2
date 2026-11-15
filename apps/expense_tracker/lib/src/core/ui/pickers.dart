import 'package:flutter/material.dart';

import '../text/figures.dart';
import '../look/glyphs.dart';
import 'icons.dart';
import '../look/theme.dart';
import '../look/widgets.dart';
import '../ledger/ledger.dart';
import 'shown_amounts.dart';

part 'pickers_days.dart';

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
            style: const TextStyle(
              fontSize: TextSize.title,
              fontWeight: FontWeight.w700,
            ),
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
      Option(a.id, a.name, accountIcon(a), accountHue(a)),
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
      Option(c.name, c.name, iconFor(c.icon), shownColor(Color(c.color))),
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
    builder: (context) => SingleChildScrollView(
      child: OptionGrid<T>(
        options: options,
        selected: selected,
        columns: columns,
        onPick: (value) => Navigator.of(context).pop(value),
      ),
    ),
  );
}

/// The choices of [pickOption] as a grid, for a page of its own or one
/// opened inside another sheet. The chosen one is tinted and ringed in
/// [ring] when given, or has a soft background.
class OptionGrid<T> extends StatelessWidget {
  const OptionGrid({
    super.key,
    required this.options,
    required this.selected,
    required this.onPick,
    this.columns = 4,
    this.ring,
    this.chosen,
  });

  final List<Option<T>> options;
  final T? selected;

  /// Every one chosen when any number can be, in place of [selected].
  final Set<T>? chosen;
  final ValueChanged<T> onPick;
  final int columns;
  final Color? ring;

  @override
  Widget build(BuildContext context) {
    final rows = [
      for (var i = 0; i < options.length; i += columns)
        options.sublist(
          i,
          i + columns < options.length ? i + columns : options.length,
        ),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                for (var i = 0; i < columns; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: i < row.length
                        ? _OptionCell(
                            option: row[i],
                            picked:
                                chosen?.contains(row[i].value) ??
                                row[i].value == selected,
                            ring: ring,
                            onTap: () => onPick(row[i].value),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _OptionCell<T> extends StatelessWidget {
  const _OptionCell({
    required this.option,
    required this.picked,
    required this.onTap,
    this.ring,
  });

  final Option<T> option;
  final bool picked;
  final VoidCallback onTap;
  final Color? ring;

  @override
  Widget build(BuildContext context) {
    final edge = ring;
    final radius = BorderRadius.circular(14);
    return Material(
      color: picked
          ? (edge == null ? Hue.selected : edge.withValues(alpha: 0.12))
          : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: picked && edge != null
            ? BorderSide(color: edge, width: 1.5)
            : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RoundIcon(option.icon, option.color, size: 40),
              const SizedBox(height: 6),
              Text(
                option.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: TextSize.small,
                  fontWeight: picked ? FontWeight.w700 : FontWeight.w500,
                  color: picked ? (edge ?? Hue.ink) : Hue.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
  return showChildPage<String>(
    context,
    title: title,
    height: height,
    builder: (context) => SingleChildScrollView(
      child: AccountChoices(
        ledger: ledger,
        selected: selected,
        currency: currency,
        among: among,
        onPick: (id) => Navigator.of(context).pop(id),
      ),
    ),
  );
}

/// The accounts of [pickAccount], for a page of its own or one opened
/// inside another sheet; the chosen one ringed in [ring].
class AccountChoices extends StatelessWidget {
  const AccountChoices({
    super.key,
    required this.ledger,
    required this.selected,
    required this.onPick,
    this.currency,
    this.among,
    this.ring = Hue.accent,
  });

  final Ledger ledger;
  final String? selected;
  final ValueChanged<String> onPick;
  final String? currency;
  final List<Account>? among;
  final Color ring;

  @override
  Widget build(BuildContext context) {
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (name, kinds) in groups)
          if (open.any((a) => kinds.contains(a.kind))) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 8, 2, 6),
              child: Text(
                name,
                style: const TextStyle(
                  fontSize: TextSize.caption,
                  fontWeight: FontWeight.w700,
                  color: Hue.muted,
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
                    ring: ring,
                    onTap: () => onPick(a.id),
                  ),
            ]),
          ],
      ],
    );
  }
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

/// One account in [AccountChoices]: its mark, name and balance; the mark
/// grey until chosen.
class _AccountChoice extends StatelessWidget {
  const _AccountChoice({
    required this.account,
    required this.balance,
    required this.picked,
    required this.ring,
    required this.onTap,
  });

  final Account account;
  final String balance;
  final bool picked;
  final Color ring;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(14);
    return Material(
      color: picked ? ring.withValues(alpha: 0.12) : Hue.surface,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: picked ? BorderSide(color: ring, width: 1.5) : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Hue.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: GlyphIcon(
                    accountIcon(account),
                    size: 17,
                    color: picked ? ring : Hue.muted,
                  ),
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
                          fontSize: TextSize.body,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        balance,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: TextSize.caption,
                          color: Hue.muted,
                        ),
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
/// be chosen and days in [marked] have a dot.
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
    builder: (context) => SingleChildScrollView(
      child: DayChoices(
        selected: selected,
        latest: latest,
        marked: marked,
        today: today,
        onPick: (day) => Navigator.of(context).pop(day),
      ),
    ),
  );
}

/// The calendar of [pickDate], for a page of its own or one opened inside
/// another sheet, the chosen day filled with [color].
class DayChoices extends StatefulWidget {
  const DayChoices({
    super.key,
    required this.selected,
    required this.latest,
    required this.onPick,
    this.marked = const {},
    this.today,
    this.color = Hue.accent,
  });

  final DateTime selected;
  final DateTime latest;
  final ValueChanged<DateTime> onPick;
  final Set<DateTime> marked;

  /// Given, 今天, 昨天 and 前天 are cards above the calendar, each with
  /// its date and day of the week.
  final DateTime? today;
  final Color color;

  @override
  State<DayChoices> createState() => _DayChoicesState();
}
