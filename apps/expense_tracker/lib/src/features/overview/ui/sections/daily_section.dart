import 'dart:math';

import 'package:flutter/material.dart';

import '../../../../../design_system/display/amount.dart';
import '../../../../core/design_system/theme.dart';
import '../../../../core/design_system/design_system.dart';
import '../../../../core/ledger/ledger.dart';
import '../../../../core/widgets/entry_tile.dart';
import '../../../../core/navigation/nav.dart';
import '../../../../core/widgets/shown_amounts.dart';
import '../../../../../design_system/display/date.dart';
import '../../../../core/design_system/shape.dart';
import '../../../../core/design_system/spacing.dart';
import '../../../../core/design_system/motion.dart';
import '../../../../core/formatting/words.dart';

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

  DateTime get _weekStart => startOfWeek(_day);

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

  /// The day's spending, its figure in red.
  Widget _spent(Ledger ledger) {
    return FittedBox(
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
                color: AppColors.negative,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _daily() {
    final ledger = widget.ledger;
    final first = _weekStart;
    final last = first.add(const Duration(days: 6));
    var weekSpent = 0;
    for (var d = 0; d < 7; d++) {
      weekSpent += ledger.reportService.spentOn(first.add(Duration(days: d)));
    }
    // Exception to as-of-today: the day's list shows 預定 entries marked; its
    // sums go through spentOn.
    final entries = ledger.entries.onDay(_day);
    final atToday = !last.isBefore(ledger.today);
    final from = '${first.month} / ${first.day}';
    final to = '${last.month} / ${last.day}';
    final roomy = textGrowth(context) > 1.6;
    final spent = _spent(ledger);
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
        style: mutedBody,
        onPrevious: () => _moveWeek(-1),
        onNext: atToday ? null : () => _moveWeek(1),
      ),
      _week(first, atToday),
      _legend(),
      const SizedBox(height: Space.s4),
      _dayHeading(entries.length, roomy, spent),
      if (roomy) spent,
      const SizedBox(height: Space.s2),
      _DayCards(
        ledger: ledger,
        entries: entries,
        onTap: widget.nav.showEntry,
        onAdd: () => widget.nav.compose(),
      ),
    ];
  }

  /// The week starting on [first]; a swipe across it goes to the week
  /// before or after (not after when [atToday]).
  Widget _week(DateTime first, bool atToday) => GestureDetector(
    onHorizontalDragEnd: (details) {
      final speed = details.primaryVelocity ?? 0.0;
      if (speed.abs() < 150) return;
      if (speed < 0 && atToday) return;
      _moveWeek(speed < 0 ? 1 : -1);
    },
    child: AnimatedSwitcher(
      duration: Motion.of(context, Motion.short4),
      // Only the new week shows: two faded strips read as a smear.
      layoutBuilder: (current, previous) => current ?? const SizedBox(),
      child: _WeekStrip(
        key: ValueKey(first),
        ledger: widget.ledger,
        weekStart: first,
        selected: _day,
        month: widget.month.$2,
        onSelect: (day) => setState(() {
          _day = day;
        }),
      ),
    ),
  );

  /// What each colour of dot under a day stands for.
  Widget _legend() => const Padding(
    padding: EdgeInsets.only(top: Space.s2),
    child: Wrap(
      alignment: WrapAlignment.center,
      spacing: 10,
      children: [
        LegendKey(AppColors.negative, Words.expense),
        LegendKey(AppColors.positive, Words.income),
        LegendKey(AppColors.transfer, Words.transfer),
        LegendKey(AppColors.investment, Words.investment),
      ],
    ),
  );

  /// The chosen day's date and how many entries it has, with its
  /// spending at the end unless the text is [roomy].
  Widget _dayHeading(int count, bool roomy, Widget spent) => Row(
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
      Text(countOf(count, CountUnit.entries), style: mutedSmall),
      const Spacer(),
      // Shrinks a little rather than overflows when the phone's text
      // is large; with its largest, on a line of its own.
      if (!roomy) Flexible(child: spent),
    ],
  );
}

class _WeekStrip extends StatelessWidget {
  const _WeekStrip({
    super.key,
    required this.ledger,
    required this.weekStart,
    required this.selected,
    required this.month,
    required this.onSelect,
  });

  final Ledger ledger;

  /// The Sunday the week starts on.
  final DateTime weekStart;
  final DateTime selected;
  final int month;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Space.s1),
      decoration: BoxDecoration(
        color: AppColors.group,
        borderRadius: BorderRadius.circular(Radii.large),
      ),
      child: Row(
        children: [
          for (var d = 0; d < 7; d++)
            Expanded(child: _dayCell(weekStart.add(Duration(days: d)))),
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
    // Exception to as-of-today: a day's dots show what is written on it, 預定 or
    // not.
    final kinds = {for (final e in ledger.entries.onDay(day)) e.type};
    final dots = [
      if (kinds.contains(EntryType.expense)) AppColors.negative,
      if (kinds.contains(EntryType.income)) AppColors.positive,
      if (kinds.contains(EntryType.transfer)) AppColors.transfer,
      if (kinds.any((k) => k.index >= EntryType.buy.index))
        AppColors.investment,
    ];
    // The chosen day in the app's own colour: solid on the light theme,
    // a deep tint with a ring on the dark one.
    final ink = picked
        ? chosenInk(AppColors.accent)
        : future || outside
        ? AppColors.faint
        : AppColors.ink;
    final tap = future ? null : () => onSelect(day);
    return ReadAsButton(
      enabled: !future,
      selected: picked,
      label: kinds.isEmpty ? formatMMMEd(day) : '${formatMMMEd(day)}，有紀錄',
      onTap: tap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: tap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(vertical: Space.s2),
          decoration: BoxDecoration(
            color: picked ? chosenFill(AppColors.accent) : null,
            borderRadius: BorderRadius.circular(Radii.medium),
            border: picked && Shade.dark
                ? Border.fromBorderSide(chosenEdge(AppColors.accent))
                : null,
          ),
          child: Column(
            children: [
              Text(
                weekdayNames[weekdayIndex(day)],
                style: TextStyle(fontSize: TextSize.small, color: ink),
              ),
              const SizedBox(height: Space.s1),
              // A seventh of a narrow phone is less than two digits take
              // with its largest text: they shrink a little, not wrap,
              // and keep a gap from the next day's.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.s1),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '${day.day}',
                    style: TextStyle(
                      fontSize: TextSize.large,
                      fontWeight: FontWeight.w500,
                      color: ink,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: Space.s1),
              _dotsOf(dots, picked ? ink : null),
            ],
          ),
        ),
      ),
    );
  }

  /// A dot in its kind's colour for each kind of entry on a day; on the
  /// chosen day all in its words' colour, [solid].
  static Widget _dotsOf(List<Color> dots, Color? solid) => SizedBox(
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
              color: solid ?? color,
              shape: BoxShape.circle,
            ),
          ),
      ],
    ),
  );
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
        // The button goes under the words when the text is large.
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('這天沒有紀錄', style: mutedText),
            TextButton(
              onPressed: onAdd,
              style: wordButton(AppColors.accent),
              child: const Text('＋ 記一筆'),
            ),
          ],
        ),
      );
    }
    final scale = textGrowth(context);
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
    final amount = entrySpoken(
      e,
      currency: currency,
      hidden: ledger.amounts.hidden,
    );
    return SizedBox(
      width: 84,
      child: ColorCard(
        color: mark,
        radius: Radii.large,
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
