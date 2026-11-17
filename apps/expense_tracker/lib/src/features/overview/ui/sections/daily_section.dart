import 'dart:math';

import 'package:flutter/material.dart';

import '../../../../core/look/theme.dart';
import '../../../../core/look/widgets.dart';
import '../../../../core/ledger/ledger.dart';
import '../../../../core/ui/entry_tile.dart';
import '../../../../core/nav.dart';
import '../../../../core/ui/shown_amounts.dart';
import '../../../../core/text/dates.dart';
import '../../../../core/look/shape.dart';
import '../../../../core/look/spacing.dart';

/// 每日紀錄: a week of days with marks for what each holds, and the chosen
/// day's entries three to a row, six at a time.
class DailySection extends StatefulWidget {
  const DailySection({
    super.key,
    required this.ledger,
    required this.nav,
    required this.month,
    required this.onMonth,
  });

  final Ledger ledger;
  final Nav nav;

  /// The month the page shows; the week follows it when it changes.
  final (int, int) month;

  /// Tells the page when moving by weeks has reached another month.
  final ValueChanged<(int, int)> onMonth;

  @override
  State<DailySection> createState() => _DailySectionState();
}

class _DailySectionState extends State<DailySection> {
  late DateTime _day = widget.ledger.today;

  DateTime get _monday => _day.subtract(Duration(days: _day.weekday - 1));

  @override
  void didUpdateWidget(DailySection old) {
    super.didUpdateWidget(old);
    final (year, month) = widget.month;
    if (widget.month == old.month || (_day.year, _day.month) == (year, month)) {
      return;
    }
    // Another month was chosen above: the same day of that month, or its
    // last, and never a day still to come.
    final last = DateTime.utc(year, month + 1, 0).day;
    var day = DateTime.utc(year, month, min(_day.day, last));
    final today = widget.ledger.today;
    if (day.isAfter(today)) day = today;
    _day = day;
  }

  void _moveWeek(int by) {
    final today = widget.ledger.today;
    var next = _day.add(Duration(days: 7 * by));
    if (next.isAfter(today)) next = today;
    setState(() {
      _day = next;
    });
    widget.onMonth((next.year, next.month));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      // Only what it shows: a change elsewhere leaves it as it is.
      listenable: widget.ledger.watch(const {
        Topic.entries,
        Topic.accounts,
        Topic.categories,
      }),
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _daily(),
      ),
    );
  }

  List<Widget> _daily() {
    final ledger = widget.ledger;
    final monday = _monday;
    final sunday = monday.add(const Duration(days: 6));
    var weekSpent = 0;
    for (var d = 0; d < 7; d++) {
      weekSpent += ledger.reportService.spentOn(monday.add(Duration(days: d)));
    }
    final entries = ledger.entries.onDay(_day);
    final atToday = !sunday.isBefore(ledger.today);
    final from = '${monday.month} / ${monday.day}';
    final to = '${sunday.month} / ${sunday.day}';
    return [
      SectionTitle(
        '每日紀錄',
        trailing: Text('本週 ${ledger.money(weekSpent)}', style: mutedSmall),
      ),
      StepSwitch(
        label: '$from 至 $to',
        previousLabel: '上一週',
        nextLabel: '下一週',
        expand: true,
        style: const TextStyle(fontSize: TextSize.body, color: Hue.muted),
        onPrevious: () => _moveWeek(-1),
        onNext: atToday ? null : () => _moveWeek(1),
      ),
      // A swipe across the week goes to the week before or after.
      GestureDetector(
        onHorizontalDragEnd: (details) {
          final speed = details.primaryVelocity ?? 0.0;
          if (speed.abs() < 150) return;
          if (speed < 0 && atToday) return;
          _moveWeek(speed < 0 ? 1 : -1);
        },
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          // Only the new week shows: two faded strips read as a smear.
          layoutBuilder: (current, previous) => current ?? const SizedBox(),
          child: _WeekStrip(
            key: ValueKey(monday),
            ledger: ledger,
            monday: monday,
            selected: _day,
            month: widget.month.$2,
            onSelect: (day) => setState(() {
              _day = day;
            }),
          ),
        ),
      ),
      const Padding(
        padding: EdgeInsets.only(top: Space.s2),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 10,
          children: [
            LegendKey(Hue.negative, '支出'),
            LegendKey(Hue.positive, '收入'),
            LegendKey(Hue.transfer, '轉帳'),
            LegendKey(Hue.investment, '投資'),
          ],
        ),
      ),
      const SizedBox(height: Space.s4),
      Row(
        children: [
          Flexible(
            child: Text(
              formatMMMd(_day),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: TextSize.body,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: Space.s2),
          Text('${entries.length} 筆', style: mutedSmall),
          const Spacer(),
          // Shrinks rather than overflows when the phone's text is large.
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: '支出 ', style: mutedSmall),
                    TextSpan(
                      text: ledger.money(ledger.reportService.spentOn(_day)),
                      style: const TextStyle(
                        fontSize: TextSize.title,
                        fontWeight: FontWeight.w700,
                        color: Hue.negative,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: Space.s2),
      _DayCards(
        ledger: ledger,
        entries: entries,
        onTap: widget.nav.showEntry,
        onAdd: () => widget.nav.compose(),
      ),
    ];
  }
}

class _WeekStrip extends StatelessWidget {
  const _WeekStrip({
    super.key,
    required this.ledger,
    required this.monday,
    required this.selected,
    required this.month,
    required this.onSelect,
  });

  final Ledger ledger;
  final DateTime monday;
  final DateTime selected;
  final int month;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Space.s1),
      decoration: BoxDecoration(
        color: Hue.group,
        borderRadius: BorderRadius.circular(Radii.large),
      ),
      child: Row(
        children: [
          for (var d = 0; d < 7; d++)
            Expanded(child: _dayCell(monday.add(Duration(days: d)))),
        ],
      ),
    );
  }

  /// A day: its weekday, its date and a dot for each kind of entry. A
  /// button named with the full date for a screen reader, at least 48 dp
  /// tall; days still to come cannot be chosen.
  Widget _dayCell(DateTime day) {
    final picked = day == selected;
    final future = day.isAfter(ledger.today);
    final outside = day.month != month;
    final kinds = {for (final e in ledger.entries.onDay(day)) e.type};
    final dots = [
      if (kinds.contains(EntryType.expense)) Hue.negative,
      if (kinds.contains(EntryType.income)) Hue.positive,
      if (kinds.contains(EntryType.transfer)) Hue.transfer,
      if (kinds.any((k) => k.index >= EntryType.buy.index)) Hue.investment,
    ];
    // The chosen day in the app's own colour: solid on the light theme,
    // a deep tint with a ring on the dark one.
    final ink = picked
        ? chosenInk(Hue.accent)
        : future || outside
        ? Hue.faint
        : Hue.ink;
    final tap = future ? null : () => onSelect(day);
    return Semantics(
      button: true,
      enabled: !future,
      selected: picked,
      label: kinds.isEmpty ? formatMMMEd(day) : '${formatMMMEd(day)}，有紀錄',
      onTap: tap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: tap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(vertical: Space.s2),
          decoration: BoxDecoration(
            color: picked ? chosenFill(Hue.accent) : null,
            borderRadius: BorderRadius.circular(Radii.medium),
            border: picked && Shade.dark
                ? Border.fromBorderSide(chosenEdge(Hue.accent))
                : null,
          ),
          child: Column(
            children: [
              Text(
                weekdayNames[day.weekday - 1],
                style: TextStyle(fontSize: TextSize.small, color: ink),
              ),
              const SizedBox(height: Space.s1),
              Text(
                '${day.day}',
                style: TextStyle(
                  fontSize: TextSize.large,
                  fontWeight: FontWeight.w500,
                  color: ink,
                ),
              ),
              const SizedBox(height: Space.s1),
              SizedBox(
                height: 6,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final color in dots)
                      Container(
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.symmetric(horizontal: 1.5),
                        decoration: BoxDecoration(
                          // On the solid day, in its words' colour.
                          color: picked ? ink : color,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A day's entries as small cards in a row that slides sideways, one
/// card an entry: its mark on a solid square, its name and its amount,
/// on its colour's tint. A tap opens it.
class _DayCards extends StatelessWidget {
  const _DayCards({
    required this.ledger,
    required this.entries,
    required this.onTap,
    required this.onAdd,
  });

  final Ledger ledger;
  final List<Entry> entries;
  final ValueChanged<Entry> onTap;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.s2),
        child: Row(
          children: [
            const Text('這天沒有紀錄', style: TextStyle(color: Hue.muted)),
            const Spacer(),
            TextButton(
              onPressed: onAdd,
              style: wordButton(Hue.accent),
              child: const Text('＋ 記一筆'),
            ),
          ],
        ),
      );
    }
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return SizedBox(
      height: 96 * scale.clamp(1.0, 1.6),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        // Out to the screen's edge, so the row reads as going on.
        clipBehavior: Clip.none,
        itemCount: entries.length,
        separatorBuilder: (_, _) => const SizedBox(width: Space.s2),
        itemBuilder: (context, i) => _card(entries[i]),
      ),
    );
  }

  Widget _card(Entry e) {
    final (icon, mark) = entryMark(ledger, e);
    final tone = entryTone(e);
    final currency = ledger.account(e.account).currency;
    final amount = ledger.orDots(entryAmount(e, currency: currency));
    return SizedBox(
      width: 84,
      child: ColorCard(
        color: mark,
        radius: 16,
        amount: 0.16,
        label: '${e.title}，$amount',
        onTap: () => onTap(e),
        padding: const EdgeInsets.fromLTRB(
          Space.s2,
          Space.s2,
          Space.s2,
          Space.s2,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SquareIcon(icon, mark, size: 28),
            const Spacer(),
            OneLine(
              e.title,
              style: const TextStyle(
                fontSize: TextSize.caption,
                fontWeight: FontWeight.w700,
              ),
            ),
            OneLine(
              amount,
              style: TextStyle(
                fontSize: TextSize.body,
                fontWeight: FontWeight.w800,
                color: tone,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
