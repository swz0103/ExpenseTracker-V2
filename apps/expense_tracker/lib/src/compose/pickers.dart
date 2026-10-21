import 'package:flutter/material.dart';

import '../look/figures.dart';
import '../look/glyphs.dart';
import '../look/icons.dart';
import '../look/theme.dart';
import '../look/widgets.dart';
import '../model/ledger.dart';

/// A bottom sheet with a back arrow and a title over [builder]'s content.
Future<T?> showChildPage<T>(
  BuildContext context, {
  required String title,
  required Widget Function(BuildContext) builder,
}) {
  return showSheet<T>(
    context,
    (context) => Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: '返回',
                onPressed: () => Navigator.of(context).pop(),
                icon: const GlyphIcon(Glyph.back),
              ),
              Expanded(
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 48),
            ],
          ),
          const SizedBox(height: 8),
          Flexible(child: builder(context)),
        ],
      ),
    ),
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
}) {
  return showChildPage<T>(
    context,
    title: title,
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

/// A month calendar, six rows from Monday; days after [latest] cannot
/// be chosen and days in [marked] have a soft background.
Future<DateTime?> pickDate(
  BuildContext context, {
  required String title,
  required DateTime selected,
  required DateTime latest,
  Set<DateTime> marked = const {},
}) {
  return showChildPage<DateTime>(
    context,
    title: title,
    builder: (context) =>
        _Calendar(selected: selected, latest: latest, marked: marked),
  );
}

class _Calendar extends StatefulWidget {
  const _Calendar({
    required this.selected,
    required this.latest,
    required this.marked,
  });

  final DateTime selected;
  final DateTime latest;
  final Set<DateTime> marked;

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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
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
    final background = picked
        ? Hue.accent
        : !inMonth
        ? Colors.transparent
        : widget.marked.contains(day)
        ? Hue.selected
        : Hue.surface;
    final ink = picked
        ? Hue.onAccent
        : !inMonth || future
        ? Hue.faint
        : weekend
        ? Hue.negative
        : Hue.ink;
    return Padding(
      padding: const EdgeInsets.all(2.5),
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: future || !inMonth
              ? null
              : () => Navigator.of(context).pop(day),
          child: SizedBox(
            height: 40,
            child: Center(
              child: Text('${day.day}', style: TextStyle(color: ink)),
            ),
          ),
        ),
      ),
    );
  }
}
