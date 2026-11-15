import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/text/figures.dart';
import '../../../core/look/glyphs.dart';
import '../../../core/look/paint.dart';
import '../../../core/look/theme.dart';
import '../../../core/look/widgets.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/nav.dart';
import '../model/returns.dart';
import '../../../core/ui/shown_amounts.dart';

part 'investments_hero.dart';

/// 投資與股息: unrealised and realised profit, dividends by month, and
/// each holding's profit as a bar on a shared scale.
class InvestmentsPage extends StatefulWidget {
  const InvestmentsPage({super.key, required this.ledger, required this.nav});

  final Ledger ledger;
  final Nav nav;

  @override
  State<InvestmentsPage> createState() => _InvestmentsPageState();
}

class _InvestmentsPageState extends State<InvestmentsPage> {
  /// 持股 or 股息.
  var _tab = 0;

  late final _month = (widget.ledger.today.year, widget.ledger.today.month);

  @override
  Widget build(BuildContext context) {
    final ledger = widget.ledger;
    final market = widget.nav.market;
    return ListenableBuilder(
      listenable: Listenable.merge([
        ledger.watch(const {Area.entries, Area.market}),
        ?market,
      ]),
      builder: (context, _) {
        final (year, month) = _month;
        final holdings = ledger.holdings;
        final list = HeadedList(
          // Pulled down to fetch the closes again, even when empty.
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          header: CenterHeader('投資與股息', onBack: widget.nav.back),
          children: [
            _InvestHero(ledger: ledger),
            const SizedBox(height: 12),
            BigSegments(
              items: const [
                (Glyph.pie, '持股', Palette.indigo),
                (Glyph.dividend, '股息', Palette.gold),
              ],
              selected: _tab,
              onChanged: (i) => setState(() => _tab = i),
            ),
            const SizedBox(height: 14),
            if (_tab == 0) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                child: Row(
                  children: [
                    const Text(
                      '持股',
                      style: TextStyle(
                        fontSize: TextSize.heading,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // The cost lives here rather than on the main card.
                    Text(
                      '成本 ${ledger.orDots(groupDigits(ledger.investCost))}',
                      style: mutedSmall,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        switch ((market?.problem, ledger.quotedOn)) {
                          (final problem?, _) => problem,
                          (_, null) => '連上網路後更新收盤價',
                          _ when market?.busy ?? false => '更新收盤價中…',
                          (_, final d?) => '${d.month}/${d.day} 收盤 · 下拉更新',
                        },
                        textAlign: TextAlign.end,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: mutedSmall,
                      ),
                    ),
                  ],
                ),
              ),
              if (holdings.isEmpty)
                EmptyState(
                  glyph: Glyph.pie,
                  color: Palette.indigo,
                  message: '還沒有持股',
                  action: '記一筆買進',
                  onAction: () => widget.nav.compose(type: EntryType.buy),
                )
              else
                for (final (name, group) in [
                  (
                    '個股',
                    [
                      for (final h in holdings)
                        if (!h.code.startsWith('00')) h,
                    ],
                  ),
                  (
                    'ETF',
                    [
                      for (final h in holdings)
                        if (h.code.startsWith('00')) h,
                    ],
                  ),
                ])
                  if (group.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
                      child: Text(
                        '$name · ${group.length} 檔',
                        style: const TextStyle(
                          fontSize: TextSize.small,
                          fontWeight: FontWeight.w800,
                          color: Hue.muted,
                        ),
                      ),
                    ),
                    QuoteBoard([
                      for (final h
                          in group..sort((a, b) => b.value.compareTo(a.value)))
                        _HoldingRow(
                          ledger: ledger,
                          held: h,
                          onTap: () => widget.nav.open(Pages.holding(h.code)),
                        ),
                    ]),
                    const SizedBox(height: 8),
                  ],
            ] else ...[
              Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
                decoration: BoxDecoration(
                  color: Hue.group,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    const SquareIcon(Glyph.dividend, Palette.gold, size: 44),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('$month 月領到', style: mutedSmall),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              ledger.orDots(
                                groupDigits(ledger.dividends(year, month)),
                              ),
                              style: const TextStyle(
                                fontSize: TextSize.large,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Long sums shrink to fit rather than run into each other.
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text('累計', style: mutedSmall),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: Text(
                              ledger.orDots(groupDigits(ledger.totalDividends)),
                              style: const TextStyle(
                                fontSize: TextSize.heading,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              _Returns(ledger: ledger),
            ],
          ],
        );
        if (market == null) return list;
        return RefreshIndicator(
          onRefresh: () => market.refresh(force: true),
          child: list,
        );
      },
    );
  }
}

/// A rate as 「+8.4%」.
String yearlyRate(double rate) =>
    '${rate > 0 ? '+' : ''}${(rate * 100).toStringAsFixed(1)}%';

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
        padding: EdgeInsets.only(top: 18),
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
        const SizedBox(height: 18),
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
        const SizedBox(height: 10),
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
        const SizedBox(height: 4),
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
        const SizedBox(height: 6),
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
          const SizedBox(height: 10),
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
          padding: EdgeInsets.only(top: 12, left: 2),
          child: Text('依去年同月的配息推估，實際以公司公告為準', style: mutedSmall),
        ),
      ],
    );
  }
}

/// A grey pill with words, and a square of [color] before them.
class _Chip extends StatelessWidget {
  const _Chip(this.label, {this.color, this.bold = false});

  final String label;
  final Color? color;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final mark = color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Hue.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (mark != null) ...[
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: mark,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: TextSize.body,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Twelve stacked bars with their sums above, a dot for an empty month,
/// the picked month on a band, and the average dashed across.
class _StackPainter extends CustomPainter {
  _StackPainter({
    required this.stacks,
    required this.sums,
    required this.average,
    required this.picked,
    required this.hidden,
    required this.words,
    required this.rule,
    required this.band,
  });

  final List<List<(int, Color)>> stacks;
  final List<int> sums;
  final double average;
  final int picked;
  final bool hidden;
  final Color words;
  final Color rule;
  final Color band;

  static String _short(int v) =>
      v >= 1000 ? '${(v / 1000).toStringAsFixed(1)}k' : '$v';

  @override
  void paint(Canvas canvas, Size size) {
    final column = size.width / stacks.length;
    final bar = min(column * 0.62, 26.0);
    // Room above the tallest bar for its sum, inside the band.
    final top = 20.0;
    final high = sums.fold(1, max);
    double h(int v) => v / high * (size.height - top);
    if (picked >= 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(picked * column + 2, 0, column - 4, size.height),
          const Radius.circular(10),
        ),
        Paint()..color = band,
      );
    }
    for (final (k, stack) in stacks.indexed) {
      final cx = k * column + column / 2;
      if (stack.isEmpty) {
        canvas.drawCircle(
          Offset(cx, size.height - 3),
          2.5,
          Paint()..color = rule,
        );
        continue;
      }
      var y = size.height;
      for (final (i, (value, color)) in stack.indexed) {
        final height = max(h(value), 3.0);
        final rect = Rect.fromLTWH(cx - bar / 2, y - height, bar, height);
        final last = i == stack.length - 1;
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            rect,
            topLeft: last ? const Radius.circular(6) : Radius.zero,
            topRight: last ? const Radius.circular(6) : Radius.zero,
            bottomLeft: i == 0 ? const Radius.circular(6) : Radius.zero,
            bottomRight: i == 0 ? const Radius.circular(6) : Radius.zero,
          ),
          Paint()..color = color,
        );
        y -= height + 1.5;
      }
      if (!hidden) {
        // Inside its own column, the chosen one's band included: a long
        // sum such as 12.5k is set smaller rather than run over the edge.
        TextStyle style(double size) => TextStyle(
          fontSize: size,
          fontWeight: FontWeight.w700,
          color: words,
        );
        var text = layoutText(_short(sums[k]), style(TextSize.tiny));
        final room = column - 6;
        if (text.width > room) {
          text = layoutText(
            _short(sums[k]),
            style(TextSize.tiny * room / text.width),
          );
        }
        final ty = max(2.0, y - text.height - 2);
        text.paint(canvas, Offset(cx - text.width / 2, ty));
      }
    }
    final ay = size.height - h(average.round());
    final dash = Paint()
      ..color = words
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 8) {
      canvas.drawLine(Offset(x, ay), Offset(min(x + 4, size.width), ay), dash);
    }
  }

  @override
  bool shouldRepaint(_StackPainter old) =>
      old.picked != picked || old.sums != sums || old.hidden != hidden;
}
