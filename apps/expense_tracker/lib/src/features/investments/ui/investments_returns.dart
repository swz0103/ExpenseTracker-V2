part of 'investments.dart';

/// 預計配息: the next twelve months as bars, each stacked by holding, the
/// monthly average dashed across; a tap on a month lists what it holds.
/// Guessed from the past year's dividends and the shares held now.
class _Returns extends StatefulWidget {
  const _Returns({required this.ledger});

  final Ledger ledger;

  @override
  State<_Returns> createState() => _ReturnsState();
}

class _ReturnsState extends State<_Returns> {
  int? _picked;

  /// Holdings' colours in the stacks, by how much each pays.
  static const _colors = [
    Palette.indigo,
    Palette.green,
    Palette.orange,
    Palette.blue,
    Palette.rose,
    Palette.olive,
  ];

  @override
  Widget build(BuildContext context) {
    final ledger = widget.ledger;
    final guesses = expectedDividends(ledger);
    if (guesses.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: Space.s4),
        child: EmptyState(
          glyph: Glyph.dividend,
          color: Palette.gold,
          message: '記下領到的股息後，這裡會推估接下來 12 個月的配息',
        ),
      );
    }
    final today = ledger.today;
    final months = [
      for (var k = 1; k <= 12; k++) DateTime.utc(today.year, today.month + k),
    ];
    // By month, then by holding.
    final byMonth = [
      for (final m in months)
        <String, int>{
          for (final g in guesses)
            if (g.month.year == m.year && g.month.month == m.month)
              g.code: g.amount,
        },
    ];
    // Several from one holding in a month add up.
    for (final g in guesses) {
      final k = months.indexWhere(
        (m) => m.year == g.month.year && m.month == g.month.month,
      );
      if (k < 0) continue;
      byMonth[k][g.code] = guesses
          .where((x) => x.code == g.code && x.month == g.month)
          .fold(0, (sum, x) => sum + x.amount);
    }
    final names = {for (final g in guesses) g.code: g.name};
    final totals = <String, int>{};
    for (final month in byMonth) {
      for (final MapEntry(:key, :value) in month.entries) {
        totals[key] = (totals[key] ?? 0) + value;
      }
    }
    final order = totals.keys.toList()
      ..sort((a, b) => totals[b]!.compareTo(totals[a]!));
    final colour = {
      for (final (i, code) in order.indexed) code: _colors[i % _colors.length],
    };
    final sums = [for (final m in byMonth) m.values.fold(0, (a, b) => a + b)];
    final total = sums.fold(0, (a, b) => a + b);
    final first = sums.indexWhere((s) => s > 0);
    final picked = _picked ?? first;
    final average = total / 12;
    final last = months.last;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: Space.s4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '預計配息',
                    style: TextStyle(
                      fontSize: TextSize.heading,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    '${months.first.month} 月 – '
                    '${last.year == today.year ? '' : '明年 '}${last.month} 月',
                    style: mutedSmall,
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text('合計約', style: mutedSmall),
                Text(
                  ledger.orDots(groupDigits(total)),
                  style: TextStyle(
                    fontSize: TextSize.large,
                    fontWeight: FontWeight.w800,
                    color: deepOf(Palette.gold),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: Space.s2),
        Semantics(
          label: '預計配息長條圖，點一個月份看那個月',
          child: LayoutBuilder(
            builder: (context, box) => GestureDetector(
              onTapDown: (d) => setState(
                () => _picked = (d.localPosition.dx / box.maxWidth * 12)
                    .floor()
                    .clamp(0, 11),
              ),
              child: CustomPaint(
                size: Size(box.maxWidth, 170),
                painter: _StackPainter(
                  stacks: [
                    for (final m in byMonth)
                      [
                        for (final code in order)
                          if (m[code] case final v?) (v, colour[code]!),
                      ],
                  ],
                  sums: sums,
                  average: average,
                  picked: picked,
                  hidden: ledger.amounts.hidden,
                  words: Hue.muted,
                  rule: Hue.line,
                  band: tintOf(Palette.gold, 0.18),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: Space.s1),
        Row(
          children: [
            for (final (k, m) in months.indexed)
              Expanded(
                child: Text(
                  '${m.month}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: TextSize.caption,
                    fontWeight: k == picked ? FontWeight.w800 : null,
                    color: k == picked ? Hue.ink : Hue.muted,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: Space.s2),
        Wrap(
          spacing: 14,
          children: [
            Text(
              '- - - 每月平均 ${ledger.orDots(groupDigits(average.round()))}',
              style: mutedSmall,
            ),
            if (first >= 0)
              Text('${months[first].month} 月是下一次', style: mutedSmall),
          ],
        ),
        if (picked >= 0 && sums[picked] > 0) ...[
          const SizedBox(height: Space.s2),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Chip(
                '${months[picked].month} 月 · 約 '
                '${ledger.orDots(groupDigits(sums[picked]))}',
                bold: true,
              ),
              for (final code in order)
                if (byMonth[picked][code] case final v?)
                  _Chip(
                    '${names[code]}  ${ledger.orDots(groupDigits(v))}',
                    color: colour[code],
                  ),
            ],
          ),
        ],
        const Padding(
          padding: EdgeInsets.only(top: Space.s3, left: Space.half),
          child: Text('依去年同月的配息推估，實際以公司公告為準', style: mutedSmall),
        ),
      ],
    );
  }
}
