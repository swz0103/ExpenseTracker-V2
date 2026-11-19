part of 'budgets.dart';

/// A year of months, each saying how much of its budget was used: red
/// when over, gold from nine in ten.
class _MonthPicker extends StatefulWidget {
  const _MonthPicker({
    required this.ledger,
    required this.chosen,
    required this.first,
    required this.last,
  });

  final Ledger ledger;
  final (int, int) chosen;
  final (int, int) first;
  final (int, int) last;

  @override
  State<_MonthPicker> createState() => _MonthPickerState();
}

class _MonthPickerState extends State<_MonthPicker> {
  late var _year = widget.chosen.$1;

  @override
  Widget build(BuildContext context) {
    final ledger = widget.ledger;
    const key = BudgetMonths.key;
    Widget arrow(Glyph glyph, String label, bool on, int by) => Material(
      color: on ? Hue.surface : Hue.paper,
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: label,
        onPressed: on ? () => setState(() => _year += by) : null,
        icon: GlyphIcon(glyph, size: 20, color: on ? Hue.ink : Hue.faint),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.s5, 0, Space.s5, Space.s5),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              arrow(Glyph.back, '前一年', _year > widget.first.$1, -1),
              Expanded(
                child: Text(
                  '$_year',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: TextSize.heading,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              arrow(Glyph.next, '下一年', _year < widget.last.$1, 1),
            ],
          ),
          const SizedBox(height: Space.s4),
          CardGrid(columns: 4, gap: 8, [
            for (var m = 1; m <= 12; m++)
              () {
                final on =
                    key((_year, m)) >= key(widget.first) &&
                    key((_year, m)) <= key(widget.last);
                final sums = BudgetMonth.of(ledger, (_year, m));
                final total = sums.total;
                final share = total == 0 ? null : sums.spent * 100 ~/ total;
                final chosen = (_year, m) == widget.chosen;
                final tone = share == null
                    ? Hue.muted
                    : share > 100
                    ? Hue.negative
                    : share >= 90
                    ? Hue.goldText
                    : Hue.muted;
                return Semantics(
                  button: true,
                  selected: chosen,
                  enabled: on,
                  label: '$m 月',
                  excludeSemantics: true,
                  child: Material(
                    color: chosen ? Hue.selected : Hue.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(Radii.large),
                      side: chosen
                          ? const BorderSide(color: Hue.accent, width: 2)
                          : BorderSide.none,
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(Radii.large),
                      onTap: on
                          ? () => Navigator.of(context).pop((_year, m))
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: Space.s2),
                        child: Column(
                          children: [
                            Text(
                              '$m 月',
                              style: TextStyle(
                                fontSize: TextSize.title,
                                fontWeight: FontWeight.w800,
                                color: on ? Hue.ink : Hue.faint,
                              ),
                            ),
                            Text(
                              !on || share == null
                                  ? ' '
                                  : share > 100
                                  ? '超支'
                                  : '$share%',
                              style: TextStyle(
                                fontSize: TextSize.small,
                                fontWeight: FontWeight.w700,
                                color: tone,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }(),
          ]),
          const SizedBox(height: Space.s3),
          const Text(
            '每個月下面寫用了幾成；超支紅、九成以上金色',
            textAlign: TextAlign.center,
            style: mutedSmall,
          ),
        ],
      ),
    );
  }
}

/// 幫哪個設額度: the spending categories without one, as squares, and the
/// tags without one, as chips.
class _AddLimit extends StatelessWidget {
  const _AddLimit({required this.ledger});

  final Ledger ledger;

  @override
  Widget build(BuildContext context) {
    final categories = [
      for (final c in ledger.categories.forEntries(income: false))
        if (ledger.budgets.forCategory(c.name).limit == 0) c,
    ];
    final tags = [
      for (final tag in ledger.reportService.tags)
        if (ledger.budgets.forCategory('#$tag').limit == 0) tag,
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Space.s5, 0, Space.s5, Space.s5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(
            child: Text(
              '幫哪個設額度',
              style: TextStyle(
                fontSize: TextSize.heading,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (categories.isNotEmpty) ...[
            const RuleHead(Words.category),
            CardGrid(columns: 4, gap: 8, [
              for (final c in categories)
                ColorCard(
                  color: shownColor(Color(c.color)),
                  radius: Radii.large,
                  label: c.name,
                  onTap: () => Navigator.of(context).pop(c.name),
                  padding: const EdgeInsets.symmetric(
                    vertical: Space.s2,
                    horizontal: Space.half,
                  ),
                  child: Column(
                    children: [
                      GlyphIcon(
                        iconFor(c.icon),
                        size: 26,
                        color: shownColor(Color(c.color)),
                      ),
                      const SizedBox(height: Space.s2),
                      Text(
                        c.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: TextSize.small,
                          fontWeight: FontWeight.w700,
                          color: deepOf(shownColor(Color(c.color))),
                        ),
                      ),
                    ],
                  ),
                ),
            ]),
          ],
          if (tags.isNotEmpty) ...[
            const RuleHead(Words.tag),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tag in tags)
                  ActionChip(
                    backgroundColor: Hue.surface,
                    side: BorderSide.none,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(Radii.large),
                    ),
                    label: Text(
                      '#$tag',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    onPressed: () => Navigator.of(context).pop('#$tag'),
                  ),
              ],
            ),
          ],
          const SizedBox(height: Space.s4),
          const Text(
            '已經設過額度的不會出現在這裡',
            textAlign: TextAlign.center,
            style: mutedSmall,
          ),
        ],
      ),
    );
  }
}
