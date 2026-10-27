import 'dart:math';

import 'package:flutter/material.dart';

import '../../../../core/look/figures.dart';
import '../../../../core/look/glyphs.dart';
import '../../../../core/look/theme.dart';
import '../../../../core/look/widgets.dart';
import '../../../../core/ledger/ledger.dart';
import '../../../../core/ui/entry_tile.dart';
import '../../../../core/nav.dart';

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
  var _dayPage = 0;

  static const _perPage = 6;

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
    _dayPage = 0;
  }

  void _moveWeek(int by) {
    final today = widget.ledger.today;
    var next = _day.add(Duration(days: 7 * by));
    if (next.isAfter(today)) next = today;
    setState(() {
      _day = next;
      _dayPage = 0;
    });
    widget.onMonth((next.year, next.month));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.ledger,
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
      weekSpent += ledger.spentOn(monday.add(Duration(days: d)));
    }
    final entries = ledger.entriesOn(_day);
    final pages = max(1, (entries.length / _perPage).ceil());
    final page = _dayPage.clamp(0, pages - 1);
    final shown = entries.skip(page * _perPage).take(_perPage).toList();
    final last = min(entries.length, (page + 1) * _perPage);
    final atToday = !sunday.isBefore(ledger.today);
    final from = '${monday.month} / ${monday.day}';
    final to = '${sunday.month} / ${sunday.day}';
    return [
      SectionHead(
        '每日紀錄',
        trailing: Text('本週 ${ledger.money(weekSpent)}', style: mutedSmall),
      ),
      StepSwitch(
        label: '$from 至 $to',
        previousLabel: '上一週',
        nextLabel: '下一週',
        expand: true,
        style: const TextStyle(fontSize: 14, color: Hue.muted),
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
              _dayPage = 0;
            }),
          ),
        ),
      ),
      const Padding(
        padding: EdgeInsets.only(top: 6),
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
      const SizedBox(height: 14),
      Row(
        children: [
          Flexible(
            child: Text(
              '${_day.month} 月 ${_day.day} 日',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 8),
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
                      text: ledger.money(ledger.spentOn(_day)),
                      style: const TextStyle(
                        fontSize: 17,
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
      const SizedBox(height: 8),
      GestureDetector(
        onHorizontalDragEnd: (details) {
          final speed = details.primaryVelocity ?? 0.0;
          if (speed.abs() < 150 || pages < 2) return;
          setState(() {
            _dayPage = (page + (speed < 0 ? 1 : pages - 1)) % pages;
          });
        },
        child: _DayGrid(
          ledger: ledger,
          entries: shown,
          onTap: widget.nav.showEntry,
          onAdd: () => widget.nav.compose(),
        ),
      ),
      if (pages > 1)
        Center(
          child: TextButton(
            onPressed: () => setState(() => _dayPage = (page + 1) % pages),
            style: TextButton.styleFrom(
              foregroundColor: Hue.accent,
              minimumSize: const Size(44, 44),
            ),
            child: Text(
              last < entries.length
                  ? '還有 ${entries.length - last} 筆 ›'
                  : '‹ 回到前 $_perPage 筆',
            ),
          ),
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
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Hue.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: Hue.cardShadow,
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
    final kinds = {for (final e in ledger.entriesOn(day)) e.type};
    final dots = [
      if (kinds.contains(EntryType.expense)) Hue.negative,
      if (kinds.contains(EntryType.income)) Hue.positive,
      if (kinds.contains(EntryType.transfer)) Hue.transfer,
      if (kinds.any((k) => k.index >= EntryType.buy.index)) Hue.investment,
    ];
    final ink = picked
        ? Hue.accent
        : future || outside
        ? Hue.faint
        : Hue.ink;
    final tap = future ? null : () => onSelect(day);
    return Semantics(
      button: true,
      enabled: !future,
      selected: picked,
      label: kinds.isEmpty ? longDay(day) : '${longDay(day)}，有紀錄',
      onTap: tap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: tap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: picked ? Hue.selected : null,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Text(
                weekdayNames[day.weekday - 1],
                style: TextStyle(fontSize: 13, color: ink),
              ),
              const SizedBox(height: 4),
              Text(
                '${day.day}',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w500,
                  color: ink,
                ),
              ),
              const SizedBox(height: 4),
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
                          color: color,
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

/// A day's entries three to a row: icon and name above the amount.
class _DayGrid extends StatelessWidget {
  const _DayGrid({
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
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          children: [
            const Text('這天沒有紀錄', style: TextStyle(color: Hue.muted)),
            const Spacer(),
            TextButton(
              onPressed: onAdd,
              style: TextButton.styleFrom(foregroundColor: Hue.accent),
              child: const Text('＋ 記一筆'),
            ),
          ],
        ),
      );
    }
    // Three to a row on a white card, each set apart by thin rules.
    const across = 3;
    final rows = <Widget>[];
    for (var i = 0; i < entries.length; i += across) {
      if (i > 0) rows.add(const Divider(height: 1, indent: 12, endIndent: 12));
      rows.add(
        IntrinsicHeight(
          child: Row(
            children: [
              for (var k = i; k < i + across; k++) ...[
                if (k > i)
                  VerticalDivider(
                    width: 1,
                    indent: 10,
                    endIndent: 10,
                    color: k < entries.length ? Hue.line : Colors.transparent,
                  ),
                Expanded(
                  child: k < entries.length
                      ? InkWell(
                          onTap: () => onTap(entries[k]),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                            child: _cell(entries[k]),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return SoftPanel(
      color: Hue.white,
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(children: rows),
    );
  }

  Widget _cell(Entry e) {
    final (icon, mark) = entryMark(ledger, e);
    final color = entryTone(e);
    final letter = entryLetter(e);
    final currency = ledger.account(e.account).currency;
    final amount = ledger.orDots(entryAmount(e, currency: currency));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (letter != null)
              IconBadge.letter(letter, mark, size: 18)
            else
              GlyphIcon(icon, size: 16, color: mark),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                e.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
        Text(
          amount,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}
