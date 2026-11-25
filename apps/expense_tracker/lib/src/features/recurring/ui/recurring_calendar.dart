import 'package:core/time/utc_days.dart';
import 'package:flutter/material.dart';

import '../../../../design_system/display/amount.dart';
import '../../../../design_system/display/status.dart';
import '../../../core/design_system/glyphs.dart';
import '../../../core/design_system/theme.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/widgets/entry_tile.dart';
import '../../../core/widgets/problem_note.dart';
import '../model/recurring_schedule.dart';
import '../../../core/widgets/shown_amounts.dart';
import '../../../../design_system/display/date.dart';
import '../../../core/design_system/shape.dart';
import '../../../core/design_system/spacing.dart';
import '../../../core/design_system/month_grid.dart';
import '../../../core/design_system/motion.dart';
import '../../../core/formatting/words.dart';
import 'recurring_rows.dart';

/// The grey of a day with several items, or with all of them booked.
const _busyDay = AppColors.surface;

// The month as a calendar and the items of the day chosen.

/// The month as a white calendar: day numbers on one line, a fixed slot
/// under each for its mark, dots or tick, and 到期 under a day due.
class RecurringCalendar extends StatelessWidget {
  const RecurringCalendar({
    super.key,
    required this.ledger,
    required this.year,
    required this.month,
    required this.plan,
    required this.chosen,
    required this.onPick,
  });

  final Ledger ledger;
  final int year;
  final int month;
  final Map<int, List<Due>> plan;
  final int? chosen;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    final today = ledger.today;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        Space.s2,
        Space.s3,
        Space.s2,
        Space.s2,
      ),
      decoration: BoxDecoration(
        color: AppColors.group,
        borderRadius: BorderRadius.circular(Radii.largeIncreased),
      ),
      child: MonthGrid(
        year: year,
        month: month,
        sixWeeks: false,
        // A day due is taller by its 到期: the others sit at the top.
        top: true,
        gap: Space.s2,
        weekdayStyle: const TextStyle(
          fontSize: TextSize.caption,
          color: AppColors.muted,
          fontWeight: FontWeight.w700,
        ),
        day: (d) => _dayCell(context, d, today),
      ),
    );
  }

  /// A day's fill: solid in its one item's colour on the light theme, a
  /// deep tint of it on the dark one, as an account's card, not a pale
  /// block; grey with several items; none without.
  static BoxDecoration? _fillOf(
    Color color, {
    required bool single,
    required bool busy,
  }) {
    if (single) {
      return Shade.dark
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.medium),
              color: tintOf(color, 0.34),
            )
          : BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.medium),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color.lerp(color, AppColors.onSolid, 0.15)!, color],
              ),
            );
    }
    if (!busy) return null;
    return BoxDecoration(
      color: _busyDay,
      borderRadius: BorderRadius.circular(Radii.medium),
    );
  }

  Widget _dayCell(BuildContext context, int d, DateTime today) {
    final day = DateTime.utc(year, month, d);
    final todayDay = dayOf(today);
    final isToday = day == todayDay;
    final past = day.isBefore(todayDay);
    final items = plan[d] ?? const <Due>[];
    final allBooked = items.isNotEmpty && items.every((x) => x.settled);
    final due = items.any(
      (x) => x.statusOn(todayDay) == RecurringPeriodStatus.due,
    );
    final single = items.length == 1 && !allBooked;
    final (glyph, color) = single
        ? recurringMark(ledger, items.first.item)
        : (Glyph.other, AppColors.muted);
    final isChosen = d == chosen;
    final fill = _fillOf(color, single: single, busy: items.isNotEmpty);
    final onColor = single && !Shade.dark ? AppColors.onSolid : AppColors.ink;
    final number = _number(
      d,
      today: isToday,
      ink: single
          ? onColor
          : past && items.isEmpty
          ? AppColors.faint
          : AppColors.ink,
    );
    final slot = _slot(
      items,
      allBooked: allBooked,
      single: single,
      glyph: glyph,
      color: color,
    );
    return ReadAsButton(
      selected: isChosen,
      label:
          '$month 月 $d 日'
          '${items.isEmpty ? '' : '，${countOf(items.length, CountUnit.entries)}${due ? '，${StatusWords.due}' : ''}'}',
      onTap: () => onPick(d),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onPick(d),
        child: Padding(
          padding: const EdgeInsets.all(Space.half),
          child: Column(
            children: [
              _ring(
                context,
                chosen: isChosen,
                edge: single ? deepOf(color) : AppColors.accent,
                fill: fill,
                number: number,
                slot: slot,
              ),
              // 到期 under a day due, as tall as its letters (a fixed box
              // cut their bottom off); a week with none takes no room for it.
              if (due)
                const Text(
                  StatusWords.due,
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                    fontSize: TextSize.tiny,
                    fontWeight: FontWeight.w800,
                    color: AppColors.negative,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Day [d]'s number in [ink], or on the accent's circle when it is
  /// [today].
  static Widget _number(int d, {required bool today, required Color ink}) {
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: today
          ? const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle)
          : null,
      child: Text(
        '$d',
        textScaler: TextScaler.noScaling,
        style: TextStyle(
          fontSize: TextSize.small,
          fontWeight: FontWeight.w800,
          color: today ? AppColors.onAccent : ink,
        ),
      ),
    );
  }

  /// What sits under a day's number: a tick when all its [items] are
  /// booked, the one item's mark, a dot for each of the first three, or
  /// nothing.
  Widget _slot(
    List<Due> items, {
    required bool allBooked,
    required bool single,
    required Glyph glyph,
    required Color color,
  }) {
    if (allBooked) {
      return const GlyphIcon(Glyph.check, size: 14, color: AppColors.muted);
    }
    if (single) {
      return GlyphIcon(
        glyph,
        size: 16,
        color: Shade.dark ? color : AppColors.onSolid,
        tinted: false,
      );
    }
    if (items.isEmpty) return const SizedBox();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final x in items.take(3))
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            decoration: BoxDecoration(
              color: !x.settled
                  ? recurringMark(ledger, x.item).$2
                  : AppColors.faint,
              shape: BoxShape.circle,
            ),
          ),
      ],
    );
  }

  /// A day's block: its [number] over its [slot] on its [fill], inside a
  /// ring in [edge] when [chosen].
  Widget _ring(
    BuildContext context, {
    required bool chosen,
    required Color edge,
    required BoxDecoration? fill,
    required Widget number,
    required Widget slot,
  }) {
    // Every day keeps the room of the ring, so the chosen one is as large
    // as the rest and the row stays even.
    return AnimatedContainer(
      duration: Motion.of(context, Motion.short4),
      padding: const EdgeInsets.all(Space.half),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.large),
        border: Border.all(color: chosen ? edge : AppColors.none, width: 2.5),
      ),
      child: Container(
        height: 46,
        decoration:
            fill ??
            BoxDecoration(
              color: chosen ? AppColors.selected : null,
              borderRadius: BorderRadius.circular(Radii.medium),
            ),
        padding: const EdgeInsets.only(top: Space.half),
        child: Column(
          children: [
            number,
            SizedBox(
              height: Space.s4,
              child: Center(child: slot),
            ),
          ],
        ),
      ),
    );
  }
}

/// The chosen day: its date and how far off, then its items as cards
/// (side by side to slide through when several), or a line to add one.
class RecurringDayItems extends StatefulWidget {
  const RecurringDayItems({
    super.key,
    required this.ledger,
    required this.day,
    required this.items,
    required this.onBook,
    required this.onEdit,
    required this.onOpen,
    required this.onAdd,
  });

  final Ledger ledger;
  final DateTime day;
  final List<Due> items;

  /// 入帳 pressed on an item's period: the item and the day it falls on.
  final void Function(Recurring item, DateTime day) onBook;
  final ValueChanged<Recurring> onEdit;
  final ValueChanged<Entry> onOpen;
  final VoidCallback onAdd;

  @override
  State<RecurringDayItems> createState() => _DayItemsState();
}

class _DayItemsState extends State<RecurringDayItems> {
  @override
  Widget build(BuildContext context) {
    final ledger = widget.ledger;
    final today = ledger.today;
    final todayDay = dayOf(today);
    final day = widget.day;
    final items = widget.items;
    final away = day.difference(todayDay).inDays;
    final allSettled = items.isNotEmpty && items.every((x) => x.settled);
    final overdue = items.any((x) => !x.settled) && away < 0;
    final total = items.fold(
      0,
      (sum, x) => sum + ledger.recurringService.worth(x.item),
    );
    final when = away == 0
        ? Words.today
        : away > 0
        ? '${countOf(away, CountUnit.days)}後'
        : '過了 ${countOf(-away, CountUnit.days)}';
    final right = items.isEmpty
        ? (away > 0 ? '${countOf(away, CountUnit.days)}後' : '')
        : allSettled
        ? settledDayWords([for (final x in items) x.statusOn(todayDay)])
        : overdue
        ? when
        : items.length > 1
        ? '$when · 合計 ${ledger.orDots(groupDigits(total))}'
        : when;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.s1),
          child: Row(
            children: [
              Text(
                formatMEd(day),
                style: const TextStyle(
                  fontSize: TextSize.title,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Text(
                right,
                style: TextStyle(
                  fontSize: TextSize.body,
                  fontWeight: FontWeight.w700,
                  color: overdue ? AppColors.negative : AppColors.muted,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.s2),
        if (items.isEmpty)
          Row(
            children: [
              const Padding(
                padding: EdgeInsets.only(left: Space.s1),
                child: Text('這天沒有固定交易', style: mutedText),
              ),
              const Spacer(),
              TextButton(
                onPressed: widget.onAdd,
                style: wordButton(AppColors.accent, minimumSize: Size(0, 48)),
                child: const Text(
                  '＋ 新增',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          )
        else
          for (final (i, x) in items.indexed) ...[
            if (i > 0) const SizedBox(height: Space.s2),
            _itemCard(x, todayDay),
          ],
      ],
    );
  }

  /// The item's name over its line, read in the card's label already.
  static Widget _itemWords(
    String name,
    String line,
    Color color, {
    required bool due,
  }) => ExcludeSemantics(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: TextSize.body,
            fontWeight: FontWeight.w800,
            color: deepOf(color),
          ),
        ),
        Text(
          line,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: TextSize.caption,
            color: due ? AppColors.negative : AppColors.muted,
            fontWeight: due ? FontWeight.w800 : FontWeight.w400,
          ),
        ),
      ],
    ),
  );

  /// The small button at a row's end: 入帳 or 恢復.
  Widget _rowButton(
    String label,
    Color fill,
    VoidCallback onPressed, {
    Color? ink,
  }) => FilledButton(
    onPressed: onPressed,
    style: solidButton(
      fill,
      ink: ink,
      minimumSize: Size(0, 44),
      radius: Radii.medium,
      padding: const EdgeInsets.symmetric(horizontal: Space.s4),
    ),
    child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
  );

  Widget _itemCard(Due x, DateTime todayDay) {
    final ledger = widget.ledger;
    final item = x.item;
    final booked = x.booked;
    final (glyph, markColor) = recurringMark(ledger, item);
    final skipped = x.skipped;
    final color = x.settled ? AppColors.faint : markColor;
    final status = x.statusOn(todayDay);
    final due = status == RecurringPeriodStatus.due;
    final words = recurringLook(status).words;
    final away = x.day.difference(todayDay).inDays;
    final account = ledger.account(item.account).name;
    final line = switch (status) {
      RecurringPeriodStatus.skipped => '$words · 不會再記',
      RecurringPeriodStatus.booked => '$words · ${formatMd(booked!.date)}',
      RecurringPeriodStatus.due => '$account · $words',
      _ =>
        '$account · ${away == 0 ? Words.today : '${countOf(away, CountUnit.days)}後'}',
    };
    final amount = Text(
      '${item.income ? '+' : ''}'
      '${ledger.orDots(recurringAmount(ledger, item))}',
      semanticsLabel: ledger.spoken(
        item.amount,
        currency: ledger.account(item.account).currency,
        sense: item.income ? AmountSense.income : AmountSense.spending,
      ),
      style: TextStyle(
        fontSize: TextSize.title,
        fontWeight: FontWeight.w800,
        color: item.income && booked == null
            ? AppColors.positive
            : AppColors.ink,
      ),
    );
    return ColorCard(
      controlsInside: true,
      color: color,
      amount: 0.16,
      radius: Radii.large,
      onTap: () => booked == null ? widget.onEdit(item) : widget.onOpen(booked),
      label: '${item.name}，${line.replaceAll(' · ', '，')}',
      padding: const EdgeInsets.all(Space.s2),
      child: Row(
        children: [
          !x.settled
              ? SquareIcon(glyph, color, size: 40)
              : Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(Radii.medium),
                  ),
                  alignment: Alignment.center,
                  child: GlyphIcon(glyph, size: 20, color: AppColors.muted),
                ),
          const SizedBox(width: Space.s3),
          Expanded(child: _itemWords(item.name, line, color, due: due)),
          const SizedBox(width: Space.s2),
          amount,
          if (due) ...[
            const SizedBox(width: Space.s2),
            _rowButton('入帳', markColor, () => widget.onBook(item, x.day)),
          ] else if (skipped) ...[
            const SizedBox(width: Space.s2),
            _rowButton(
              Words.unarchive,
              AppColors.white,
              ink: AppColors.accent,
              () => refusalShown(
                context,
                () => ledger.recurringCommands.unskip(item, x.day),
              ),
            ),
          ] else if (booked != null) ...[
            const SizedBox(width: Space.s2),
            const GlyphIcon(Glyph.check, size: 20, color: AppColors.muted),
          ],
        ],
      ),
    );
  }
}

/// A small grey cell along the bottom: a label over a figure.
class RecurringFigureCell extends StatelessWidget {
  const RecurringFigureCell({
    super.key,
    required this.label,
    required this.value,
    this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ColorCard(
      color: AppColors.faint,
      amount: 0.22,
      radius: Radii.large,
      onTap: onTap,
      label: '$label $value',
      padding: const EdgeInsets.fromLTRB(
        Space.s3,
        Space.s2,
        Space.s2,
        Space.s2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OneLine(
            label,
            style: const TextStyle(
              fontSize: TextSize.caption,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: Space.half),
          OneLine(
            value,
            style: const TextStyle(
              fontSize: TextSize.body,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
