import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/look/figures.dart';
import '../../../core/look/glyphs.dart';
import '../../../core/look/paint.dart';
import '../../../core/look/theme.dart';
import '../../../core/look/widgets.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/nav.dart';
import '../model/returns.dart';

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
        final list = ListView(
          // Pulled down to fetch the closes again, even when empty.
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          children: [
            CenterHeader('投資與股息', onBack: widget.nav.back),
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
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    Text(switch ((market?.problem, ledger.quotedOn)) {
                      (final problem?, _) => problem,
                      (_, null) => '連上網路後更新收盤價',
                      _ when market?.busy ?? false => '更新收盤價中…',
                      (_, final d?) => '${d.month}/${d.day} 收盤 · 下拉更新',
                    }, style: mutedSmall),
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
                QuoteBoard([
                  for (final h in [
                    ...holdings,
                  ]..sort((a, b) => b.value.compareTo(a.value)))
                    _HoldingRow(
                      ledger: ledger,
                      held: h,
                      onTap: () => widget.nav.open(Pages.holding(h.code)),
                    ),
                ]),
            ] else ...[
              Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
                decoration: BoxDecoration(
                  color: Hue.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: Hue.cardShadow,
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
                          Text(
                            ledger.orDots(
                              groupDigits(ledger.dividends(year, month)),
                            ),
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text('累計', style: mutedSmall),
                        Text(
                          ledger.orDots(groupDigits(ledger.totalDividends)),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
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
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
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
                    fontSize: 22,
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
                  hidden: ledger.hidden,
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
                    fontSize: 12.5,
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
              fontSize: 14,
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
    final top = 18.0;
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
        final text = layoutText(
          _short(sums[k]),
          TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: words),
        );
        text.paint(canvas, Offset(cx - text.width / 2, y - text.height - 2));
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

/// 市值 big with today's move on a solid block, and under a rule what is
/// unrealized, realized, and the yearly return.
class _InvestHero extends StatelessWidget {
  const _InvestHero({required this.ledger});

  final Ledger ledger;

  @override
  Widget build(BuildContext context) {
    final value = ledger.investValue;
    final cost = ledger.investCost;
    final gain = value - cost;
    final day = ledger.dayChange;
    final before = value - day;
    final rate = returnOf(ledger);
    Widget column(String label, String figure, Color color, String sub) =>
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: mutedSmall),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  figure,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
              Text(
                sub,
                style: const TextStyle(fontSize: 11.5, color: Hue.muted),
              ),
            ],
          ),
        );
    return HeroCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '市值',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: Hue.accent,
            ),
          ),
          // The chip goes under the figure when both do not fit on a line,
          // rather than shrinking the figure.
          Wrap(
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                ledger.orDots(groupDigits(value)),
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (ledger.quotedOn != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: day < 0 ? Hue.negative : Hue.positive,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '今日 ${ledger.orDots(signed(day))}'
                    '${before == 0 ? '' : ' · ${percentOf(day, before)}'}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Hue.onAccent,
                    ),
                  ),
                ),
            ],
          ),
          const Divider(height: 22, color: Hue.accentRule),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              column(
                '未實現',
                ledger.orDots(signed(gain)),
                gain < 0 ? Hue.negative : Hue.positive,
                '${percentOf(gain, cost)} · 成本 ${ledger.orDots(groupDigits(cost))}',
              ),
              column(
                '已實現',
                ledger.orDots(signed(ledger.realized)),
                ledger.realized < 0 ? Hue.negative : Hue.positive,
                '已賣出',
              ),
              column(
                '年化報酬',
                rate == null ? '—' : yearlyRate(rate),
                rate == null || rate >= 0 ? Hue.positive : Hue.negative,
                rate == null ? '有期初持股' : '含股息',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A holding on the quote board: name, code and kind, shares and gain;
/// the close big and today's move on a solid block.
class _HoldingRow extends StatelessWidget {
  const _HoldingRow({
    required this.ledger,
    required this.held,
    required this.onTap,
  });

  final Ledger ledger;
  final Holding held;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final quoted = ledger.hasQuote(held.code);
    final before = held.value - held.change;
    final up = held.change >= 0;
    final perShare = held.shares == 0 ? 0.0 : held.change / held.shares;
    return QuoteRow(
      onTap: onTap,
      title:
          '${held.name}  ${held.code} · ${held.code.startsWith('00') ? 'ETF' : '個股'}',
      detail:
          '${ledger.orDots(groupDigits(held.shares))} 股 · 損益 '
          '${ledger.orDots(signed(held.gain))}',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          RowFigure(held.price.toStringAsFixed(held.price < 100 ? 2 : 0)),
          const SizedBox(width: 10),
          Container(
            width: 72,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: !quoted
                  ? Hue.surface
                  : up
                  ? Hue.positive
                  : Hue.negative,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Text(
                  !quoted || before == 0 ? '—' : percentOf(held.change, before),
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: quoted ? Hue.onAccent : Hue.muted,
                  ),
                ),
                if (quoted)
                  Text(
                    '${up ? '▲' : '▼'}${perShare.abs().toStringAsFixed(2)}',
                    textScaler: TextScaler.noScaling,
                    style: const TextStyle(fontSize: 11.5, color: Hue.onAccent),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
