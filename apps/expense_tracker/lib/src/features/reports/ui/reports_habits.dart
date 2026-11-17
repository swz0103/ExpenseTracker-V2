part of 'reports.dart';

// 習慣: where the money goes most, on which days, and under which tags.

extension _Habits on _ReportsPageState {
  List<Widget> _merchants(_Report report) {
    final rows = report.merchants.take(4).toList();
    if (rows.isEmpty) return const [];
    final ledger = widget.ledger;
    final total = rows.fold(0, (sum, r) => sum + r.$3);
    return [
      TitleRow(
        '常去商家',
        trailing: Text(
          '這 ${rows.length} 家 · 合計 ${ledger.orDots(groupDigits(total))}',
          style: mutedSmall,
        ),
      ),
      Container(
        padding: const EdgeInsets.fromLTRB(
          Space.s4,
          Space.s4,
          Space.s4,
          Space.s4,
        ),
        decoration: BoxDecoration(
          color: Hue.group,
          borderRadius: BorderRadius.circular(Radii.largeIncreased),
        ),
        child: Row(
          children: [
            Donut(
              size: 96,
              thickness: 20,
              slices: [
                for (final (i, r) in rows.indexed)
                  (r.$3, Hue.shades[(i + 2) % Hue.shades.length]),
              ],
            ),
            const SizedBox(width: Space.s4),
            Expanded(
              child: Column(
                children: [
                  for (final (i, (name, count, amount)) in rows.indexed)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: Space.s1),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: Space.s1),
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: Hue.shades[(i + 2) % Hue.shades.length],
                                borderRadius: BorderRadius.circular(
                                  Radii.extraSmall,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: Space.s2),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  '$count 次 · 每次約 '
                                  '${ledger.orDots(groupDigits(amount ~/ count))}',
                                  style: const TextStyle(
                                    fontSize: TextSize.caption,
                                    color: Hue.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            ledger.orDots(groupDigits(amount)),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ];
  }

  /// 星期: what was spent on each day of the week over the period, the
  /// heaviest day in the spending colour.
  List<Widget> _weekdays(_Report report) {
    final days = report.weekdays;
    final most = days.fold(0, max);
    if (most <= 0) return const [];
    final heaviest = days.indexOf(most);
    return [
      TitleRow('星期', trailing: const Text('虛線是每天平均', style: mutedSmall)),
      GroupBox(
        padding: const EdgeInsets.fromLTRB(
          Space.s2,
          Space.s4,
          Space.s2,
          Space.s2,
        ),
        child: Column(
          children: [
            SizedBox(
              height: 96,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final (i, spent) in days.indexed)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: Space.s2,
                              ),
                              child: FractionallySizedBox(
                                heightFactor: spent <= 0
                                    ? 0.03
                                    : max(spent / most, 0.06),
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: i == heaviest
                                        ? Hue.negative
                                        : softOf(Hue.negative),
                                    borderRadius: BorderRadius.circular(
                                      Radii.small,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 96 * (days.fold(0, (s, d) => s + d) / 7 / most),
                    child: CustomPaint(
                      size: const Size(double.infinity, 1),
                      painter: _Dashes(Hue.muted),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Space.s2),
            Row(
              children: [
                for (final (i, name) in weekdayNames.indexed)
                  Expanded(
                    child: Text(
                      name,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: TextSize.caption,
                        fontWeight: i == heaviest
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: i == heaviest ? Hue.negative : Hue.muted,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _tags(_Report report) {
    final rows = report.tags;
    if (rows.isEmpty) return const [];
    final ledger = widget.ledger;
    final counts = {
      for (final (tag, n, _) in ledger.reportService.tagStats) tag: n,
    };
    return [
      const TitleRow('標籤'),
      CardGrid(columns: 3, gap: 8, [
        for (final (tag, amount) in rows.take(9))
          ColorCard(
            color: nameColor(tag),
            radius: 16,
            padding: const EdgeInsets.fromLTRB(
              Space.s3,
              Space.s2,
              Space.s2,
              Space.s2,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '#$tag',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: deepOf(nameColor(tag)),
                  ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    ledger.orDots(groupDigits(amount)),
                    style: const TextStyle(
                      fontSize: TextSize.heading,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (counts[tag] case final n?)
                  Text(
                    '$n 筆',
                    style: const TextStyle(
                      fontSize: TextSize.caption,
                      color: Hue.muted,
                    ),
                  ),
              ],
            ),
          ),
      ]),
    ];
  }
}
