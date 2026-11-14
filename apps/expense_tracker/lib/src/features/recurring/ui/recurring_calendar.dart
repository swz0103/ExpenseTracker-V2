part of 'recurring_page.dart';

// The month as a calendar and the items of the day chosen.

/// The month as a white calendar: day numbers on one line, a fixed slot
/// under each for its mark, dots or tick, and 到期 under a day due.
class _Calendar extends StatelessWidget {
  const _Calendar({
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
    final first = DateTime.utc(year, month);
    final days = DateTime.utc(year, month + 1, 0).day;
    // Sunday first, as the design reads.
    final lead = first.weekday % 7;
    final cells = <Widget>[
      for (var i = 0; i < lead; i++) const SizedBox(),
      for (var d = 1; d <= days; d++) _dayCell(d, today),
    ];
    while (cells.length % 7 != 0) {
      cells.add(const SizedBox());
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
      decoration: BoxDecoration(
        color: Hue.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: Hue.cardShadow,
      ),
      child: Column(
        children: [
          Row(
            children: [
              for (final w in const ['日', '一', '二', '三', '四', '五', '六'])
                Expanded(
                  child: Center(
                    child: Text(
                      w,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Hue.muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          for (var r = 0; r < cells.length; r += 7)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final cell in cells.sublist(r, r + 7))
                  Expanded(child: cell),
              ],
            ),
        ],
      ),
    );
  }

  Widget _dayCell(int d, DateTime today) {
    final day = DateTime.utc(year, month, d);
    final todayDay = DateTime.utc(today.year, today.month, today.day);
    final isToday = day == todayDay;
    final past = day.isBefore(todayDay);
    final items = plan[d] ?? const <Due>[];
    final allBooked = items.isNotEmpty && items.every((x) => x.settled);
    final due = items.any((x) => !x.settled) && !day.isAfter(todayDay);
    final single = items.length == 1 && !allBooked;
    final (glyph, color) = single
        ? _mark(ledger, items.first.item)
        : (Glyph.other, Hue.muted);
    final isChosen = d == chosen;
    BoxDecoration? fill;
    if (single) {
      fill = BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.lerp(color, const Color(0xFFFFFFFF), 0.15)!, color],
        ),
      );
    } else if (items.isNotEmpty) {
      fill = BoxDecoration(
        color: _busyDay,
        borderRadius: BorderRadius.circular(12),
      );
    }
    final onColor = single ? const Color(0xFFFFFFFF) : Hue.ink;
    final number = Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: isToday
          ? const BoxDecoration(color: Hue.accent, shape: BoxShape.circle)
          : null,
      child: Text(
        '$d',
        textScaler: TextScaler.noScaling,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: isToday
              ? Hue.onAccent
              : single
              ? onColor
              : past && items.isEmpty
              ? Hue.faint
              : Hue.ink,
        ),
      ),
    );
    Widget slot;
    if (allBooked) {
      slot = const GlyphIcon(Glyph.check, size: 14, color: Hue.muted);
    } else if (single) {
      slot = GlyphIcon(
        glyph,
        size: 16,
        color: const Color(0xFFFFFFFF),
        tinted: false,
      );
    } else if (items.isNotEmpty) {
      slot = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final x in items.take(3))
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              decoration: BoxDecoration(
                color: !x.settled ? _mark(ledger, x.item).$2 : Hue.faint,
                shape: BoxShape.circle,
              ),
            ),
        ],
      );
    } else {
      slot = const SizedBox();
    }
    return Semantics(
      button: true,
      selected: isChosen,
      label:
          '$month 月 $d 日'
          '${items.isEmpty ? '' : '，${items.length} 筆${due ? '，到期' : ''}'}',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onPick(d),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Column(
            children: [
              Container(
                height: 50,
                decoration: (fill ?? const BoxDecoration()).copyWith(
                  borderRadius: BorderRadius.circular(12),
                  border: isChosen
                      ? Border.all(color: Hue.accent, width: 2)
                      : null,
                ),
                foregroundDecoration: isChosen
                    ? BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Hue.white, width: 2),
                      )
                    : null,
                padding: const EdgeInsets.only(top: 3),
                child: Column(
                  children: [
                    number,
                    SizedBox(height: 18, child: Center(child: slot)),
                  ],
                ),
              ),
              SizedBox(
                height: 14,
                child: due
                    ? const Text(
                        '到期',
                        textScaler: TextScaler.noScaling,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Hue.negative,
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The chosen day: its date and how far off, then its items as cards
/// (side by side to slide through when several), or a line to add one.
class _DayItems extends StatefulWidget {
  const _DayItems({
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
  final ValueChanged<Recurring> onBook;
  final ValueChanged<Recurring> onEdit;
  final ValueChanged<Entry> onOpen;
  final VoidCallback onAdd;

  @override
  State<_DayItems> createState() => _DayItemsState();
}

class _DayItemsState extends State<_DayItems> {
  @override
  Widget build(BuildContext context) {
    final ledger = widget.ledger;
    final today = ledger.today;
    final todayDay = DateTime.utc(today.year, today.month, today.day);
    final day = widget.day;
    final items = widget.items;
    final away = day.difference(todayDay).inDays;
    final allBooked = items.isNotEmpty && items.every((x) => x.settled);
    final overdue = items.any((x) => !x.settled) && away < 0;
    final total = items.fold(
      0,
      (sum, x) => sum + ledger.recurringWorth(x.item),
    );
    final when = away == 0
        ? '今天'
        : away > 0
        ? '$away 天後'
        : '過了 ${-away} 天';
    final right = items.isEmpty
        ? (away > 0 ? '$away 天後' : '')
        : allBooked
        ? '已入帳'
        : overdue
        ? when
        : items.length > 1
        ? '$when · 合計 ${ledger.orDots(groupDigits(total))}'
        : when;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              Text(
                '${day.month}/${day.day} 週${weekdayNames[day.weekday - 1]}',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Text(
                right,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: overdue ? Hue.negative : Hue.muted,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (items.isEmpty)
          Row(
            children: [
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Text('這天沒有固定交易', style: TextStyle(color: Hue.muted)),
              ),
              const Spacer(),
              TextButton(
                onPressed: widget.onAdd,
                style: TextButton.styleFrom(
                  foregroundColor: Hue.accent,
                  minimumSize: const Size(0, 48),
                ),
                child: const Text(
                  '＋ 新增',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          )
        else
          for (final (i, x) in items.indexed) ...[
            if (i > 0) const SizedBox(height: 8),
            _itemCard(x, todayDay),
          ],
      ],
    );
  }

  Widget _itemCard(Due x, DateTime todayDay) {
    final ledger = widget.ledger;
    final item = x.item;
    final booked = x.booked;
    final (glyph, markColor) = _mark(ledger, item);
    final skipped = x.skipped;
    final color = x.settled ? Hue.faint : markColor;
    final due = !x.settled && !x.day.isAfter(todayDay);
    final away = x.day.difference(todayDay).inDays;
    final account = ledger.account(item.account).name;
    final line = skipped
        ? '已跳過 · 不會再記'
        : booked != null
        ? '已入帳 · ${booked.date.month}/${booked.date.day}'
        : due
        ? '$account · 到期'
        : '$account · ${away == 0 ? '今天' : '$away 天後'}';
    final amount = Text(
      '${item.income ? '+' : ''}'
      '${ledger.orDots(recurringAmount(ledger, item))}',
      style: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w800,
        color: item.income && booked == null ? Hue.positive : Hue.ink,
      ),
    );
    return ColorCard(
      color: color,
      amount: 0.16,
      radius: 18,
      onTap: () => booked == null ? widget.onEdit(item) : widget.onOpen(booked),
      label: '${item.name}，${line.replaceAll(' · ', '，')}',
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      child: Row(
        children: [
          !x.settled
              ? SquareIcon(glyph, color, size: 40)
              : Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Hue.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: GlyphIcon(glyph, size: 20, color: Hue.muted),
                ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: deepOf(color),
                  ),
                ),
                Text(
                  line,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: due ? Hue.negative : Hue.muted,
                    fontWeight: due ? FontWeight.w800 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          amount,
          if (due) ...[
            const SizedBox(width: 10),
            FilledButton(
              onPressed: () => widget.onBook(item),
              style: FilledButton.styleFrom(
                backgroundColor: markColor,
                foregroundColor: wordsOn(markColor),
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                '入帳',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ] else if (skipped) ...[
            const SizedBox(width: 10),
            FilledButton(
              onPressed: () => ledger.unskip(item, x.day),
              style: FilledButton.styleFrom(
                backgroundColor: Hue.white,
                foregroundColor: Hue.accent,
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                '恢復',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ] else if (booked != null) ...[
            const SizedBox(width: 8),
            const GlyphIcon(Glyph.check, size: 20, color: Hue.muted),
          ],
        ],
      ),
    );
  }
}

/// A small grey cell along the bottom: a label over a figure.
class _Cell extends StatelessWidget {
  const _Cell({required this.label, required this.value, this.onTap});

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ColorCard(
      color: Hue.faint,
      amount: 0.22,
      radius: 16,
      onTap: onTap,
      label: '$label $value',
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OneLine(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          OneLine(
            value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

/// A small rounded tag in [color]'s tint: the next date.
class _Tag extends StatelessWidget {
  const _Tag(this.text, {required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: tintOf(color, 0.22),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        color: deepOf(color),
      ),
    ),
  );
}

/// An item as one row in its colour: mark, name over how often and from
/// where, the amount over a small tag with the next date (or [lines] in
/// place of the second line, and [trailing] after it all).
class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.ledger,
    required this.item,
    required this.onTap,
    this.grey = false,
    this.trailing,
    this.lines,
  });

  final Ledger ledger;
  final Recurring item;
  final VoidCallback onTap;
  final bool grey;
  final Widget? trailing;
  final List<String>? lines;

  @override
  Widget build(BuildContext context) {
    final (glyph, mark) = _mark(ledger, item);
    final color = grey ? Hue.faint : mark;
    final next = grey || lines != null ? '' : ledger.nextLabel(item);
    final sub =
        lines?.join(' · ') ??
        '${item.rhythm} · ${ledger.account(item.account).name}';
    return ColorCard(
      color: color,
      amount: 0.16,
      radius: 18,
      onTap: onTap,
      label: '${item.name}，$sub${next.isEmpty ? '' : '，下次 $next'}',
      padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
      child: Row(
        children: [
          grey
              ? Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Hue.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: GlyphIcon(glyph, size: 20, color: Hue.muted),
                )
              : SquareIcon(glyph, color, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: deepOf(color),
                  ),
                ),
                Text(
                  sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Hue.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${item.income ? '+' : ''}'
                '${ledger.orDots(recurringAmount(ledger, item))}',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: item.income && !grey ? Hue.positive : Hue.ink,
                ),
              ),
              if (next.isNotEmpty) ...[
                const SizedBox(height: 2),
                _Tag('下次 $next', color: color),
              ],
            ],
          ),
          if (trailing case final t?) ...[const SizedBox(width: 10), t],
        ],
      ),
    );
  }
}
