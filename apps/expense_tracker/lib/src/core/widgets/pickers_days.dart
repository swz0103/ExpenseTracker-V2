part of 'pickers.dart';

class _DayChoicesState extends State<DayChoices> {
  late var _month = DateTime.utc(widget.selected.year, widget.selected.month);

  @override
  Widget build(BuildContext context) {
    final first = _month;
    final latest = widget.latest;
    final atEnd =
        monthIndex(first.year, first.month) >=
        monthIndex(latest.year, latest.month);
    // The days written down most: picked at once, without the calendar.
    final today = widget.today;
    final quick = [
      if (today != null)
        for (final (i, name) in const [Words.today, '昨天', '前天'].indexed)
          (name, today.subtract(Duration(days: i))),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (quick.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.s2),
            child: Row(
              children: [
                for (final (i, (name, day)) in quick.indexed) ...[
                  if (i > 0) const SizedBox(width: Space.s2),
                  Expanded(
                    child: _QuickDay(
                      name: name,
                      day: day,
                      picked: day == widget.selected,
                      color: widget.color,
                      onTap: () => widget.onPick(day),
                    ),
                  ),
                ],
              ],
            ),
          ),
        StepSwitch(
          label: formatYMMM(first),
          previousLabel: Words.previousMonth,
          nextLabel: Words.nextMonth,
          iconSize: 20,
          expand: true,
          onPrevious: () => setState(() {
            _month = monthStart(first, -1);
          }),
          onNext: atEnd
              ? null
              : () => setState(() {
                  _month = monthStart(first, 1);
                }),
        ),
        const SizedBox(height: Space.s1),
        MonthGrid(
          year: first.year,
          month: first.month,
          blank: 48,
          day: (d) => _day(DateTime.utc(first.year, first.month, d)),
        ),
      ],
    );
  }

  Widget _day(DateTime day) {
    final future = day.isAfter(widget.latest);
    final picked = day == widget.selected;
    // Only the chosen day is filled; a day with entries has a dot.
    final ink = picked
        ? chosenInk(widget.color)
        : future
        ? AppColors.faint
        : AppColors.ink;
    final dotted = !picked && widget.marked.contains(day);
    return InkResponse(
      onTap: future ? null : () => widget.onPick(day),
      radius: 24,
      child: SizedBox(
        height: 48,
        child: Center(
          // At least 40 across, and taller with the phone's largest text.
          child: Container(
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            decoration: BoxDecoration(
              color: picked ? chosenFill(widget.color) : null,
              shape: BoxShape.circle,
              border: picked && Shade.dark
                  ? Border.fromBorderSide(chosenEdge(widget.color))
                  : null,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${day.day}',
                  style: TextStyle(
                    fontSize: TextSize.body,
                    color: ink,
                    fontWeight: picked ? FontWeight.w800 : FontWeight.w500,
                  ),
                ),
                if (dotted)
                  Container(
                    width: 4,
                    height: 4,
                    margin: const EdgeInsets.only(top: Space.half),
                    decoration: BoxDecoration(
                      color: widget.color.withValues(alpha: 0.6),
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

/// 今天, 昨天 or 前天 as a card with its date and day of the week, centred.
class _QuickDay extends StatelessWidget {
  const _QuickDay({
    required this.name,
    required this.day,
    required this.picked,
    required this.color,
    required this.onTap,
  });

  final String name;
  final DateTime day;
  final bool picked;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(Radii.large);
    return Material(
      color: picked ? color.withValues(alpha: 0.12) : AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: picked ? BorderSide(color: color, width: 1.5) : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: Space.s2,
            horizontal: Space.s1,
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontSize: TextSize.body,
                    fontWeight: FontWeight.w700,
                    color: picked ? color : AppColors.ink,
                  ),
                ),
                Text(formatMEd(day), style: mutedCaption),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
