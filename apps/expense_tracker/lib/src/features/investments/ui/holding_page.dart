import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/look/figures.dart';
import '../../../core/look/theme.dart';
import '../../../core/look/widgets.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/ui/entry_tile.dart';
import '../../../core/nav.dart';
import '../../../core/connector.dart';
import '../model/returns.dart';
import 'investments.dart' show yearlyRate;

/// One holding: its market value and profit, today's move and the
/// dividends it paid, the lots still held against what they are worth
/// now, and every trade of it.
class HoldingPage extends StatelessWidget {
  const HoldingPage({
    super.key,
    required this.ledger,
    required this.nav,
    required this.code,
  });

  final Ledger ledger;
  final Nav nav;
  final String code;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ledger,
      builder: (context, _) {
        final held = ledger.holding(code);
        final trades = ledger.tradesOf(code);
        if (held == null) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            children: [
              PageHeader(code, onBack: nav.back),
              const Text('已不再持有', style: TextStyle(color: Hue.muted)),
              ..._history(trades),
            ],
          );
        }
        final tone = held.gain < 0 ? Hue.negative : Hue.positive;
        final quoted = ledger.hasQuote(code);
        final lots = ledger.lotsOf(code);
        var largest = 1;
        for (final l in lots) {
          largest = max(largest, max(l.cost, (l.shares * held.price).round()));
        }
        final average = held.shares == 0 ? 0 : held.cost / held.shares;
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          children: [
            CenterHeader('${held.name} $code', onBack: nav.back),
            _PriceCard(ledger: ledger, held: held, quoted: quoted),
            const SizedBox(height: 12),
            _PriceChart(
              ledger: ledger,
              nav: nav,
              code: code,
              average: average.toDouble(),
              buys: [
                for (final e in trades)
                  if (e.type == EntryType.buy && e.shares > 0) e,
              ],
            ),
            const SizedBox(height: 12),
            Builder(
              builder: (context) {
                final rate = returnOf(ledger, code: code);
                final next = expectedDividends(ledger)
                    .where((g) => g.code == code)
                    .firstOrNull;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CardGrid(gap: 10, [
                      _Bento(
                        color: tone,
                        label: held.gain < 0 ? '賠了' : '賺了',
                        value: ledger.orDots(signed(held.gain)),
                        lines: [
                          '${percentOf(held.gain, held.cost)}'
                              '${rate == null ? '' : ' · 年化 ${yearlyRate(rate)}'}',
                        ],
                      ),
                      _Bento(
                        color: Hue.faint,
                        label: '現在值',
                        value: ledger.orDots(groupDigits(held.value)),
                        lines: [
                          '${ledger.orDots(groupDigits(held.shares))} 股 · '
                              '成本 ${ledger.orDots(groupDigits(held.cost))}',
                          if (quoted)
                            '今天 ${ledger.orDots(signed(held.change))}',
                        ],
                      ),
                    ]),
                    const SizedBox(height: 10),
                    _Bento(
                      color: const Shade(0xFFC9A34A, 0xFFDDBE73),
                      label: '股息',
                      value: ledger.orDots(groupDigits(held.dividends)),
                      lines: [
                        if (next != null)
                          '下次 ${next.month.month} 月 約 ${ledger.orDots(groupDigits(next.amount))}',
                        if (held.realized != 0)
                          '已實現 ${ledger.orDots(signed(held.realized))}',
                      ],
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                for (final (i, (type, label, color)) in const [
                  (EntryType.buy, '＋ 買進', Shade(0xFF4A5D99, 0xFF9FAEE0)),
                  (EntryType.sell, '賣出', Shade(0xFF9F4535, 0xFFF1B2A3)),
                  (EntryType.dividend, '記股息', Shade(0xFFC9A34A, 0xFFDDBE73)),
                ].indexed) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: PanelButton(
                      label,
                      onTap: () => nav.compose(
                        type: type,
                        draft: Entry(
                          id: '',
                          date: ledger.today,
                          type: type,
                          amount: 0,
                          account: ledger.mainAccount,
                          category: '',
                          holding: code,
                        ),
                      ),
                      color: color,
                    ),
                  ),
                ],
              ],
            ),
            const SectionHead('持有批次'),
            SoftPanel(
              color: Hue.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: Column(
                children: [
                  for (final (i, lot) in lots.indexed)
                    _LotRow(
                      ledger: ledger,
                      lot: lot,
                      worth: (lot.shares * held.price).round(),
                      largest: largest,
                      first: i == 0,
                      // One lot has nothing to be set against.
                      bars: lots.length > 1,
                    ),
                ],
              ),
            ),
            ..._history(trades),
          ],
        );
      },
    );
  }

  /// Every trade and dividend of the stock, also once it is all sold.
  List<Widget> _history(List<Entry> trades) => [
    if (trades.isNotEmpty) ...[
      const SectionHead('交易紀錄'),
      SoftPanel(
        color: Hue.white,
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Column(
          children: [
            for (final e in trades)
              EntryRow(
                ledger: ledger,
                entry: e,
                onOpen: nav.showEntry,
                divider: !identical(e, trades.last),
              ),
          ],
        ),
      ),
    ],
  ];
}

/// A lot: when it was bought, how many shares, and its cost against what
/// it is worth now as two bars.
class _LotRow extends StatelessWidget {
  const _LotRow({
    required this.ledger,
    required this.lot,
    required this.worth,
    required this.largest,
    required this.first,
    required this.bars,
  });

  final Ledger ledger;
  final Lot lot;
  final int worth;
  final int largest;
  final bool first;

  /// Whether to draw cost and worth as bars.
  final bool bars;

  @override
  Widget build(BuildContext context) {
    final opening = lot.isOpening;
    final gain = worth - lot.cost;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: first ? null : ruleAbove,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                opening ? '期初持有' : '${lot.date.month}/${lot.date.day} 買進',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${ledger.orDots(groupDigits(lot.shares))} 股',
                style: mutedSmall,
              ),
              const Spacer(),
              Text(
                ledger.moneySigned(gain),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: gain < 0 ? Hue.negative : Hue.positive,
                ),
              ),
            ],
          ),
          if (bars) ...[
            const SizedBox(height: 6),
            PairBars(
              now: worth / largest,
              then: lot.cost / largest,
              color: Hue.investment,
              thenOpacity: 0.7,
            ),
          ],
          const SizedBox(height: 4),
          Text(
            '市值 ${ledger.money(worth)} · 成本 ${ledger.money(lot.cost)}',
            style: const TextStyle(fontSize: 12.5, color: Hue.muted),
          ),
        ],
      ),
    );
  }
}

/// The close in big figures with today's move on a solid block.
class _PriceCard extends StatelessWidget {
  const _PriceCard({
    required this.ledger,
    required this.held,
    required this.quoted,
  });

  final Ledger ledger;
  final Holding held;
  final bool quoted;

  @override
  Widget build(BuildContext context) {
    final up = held.change >= 0;
    final before = held.value - held.change;
    final perShare = held.shares == 0 ? 0.0 : held.change / held.shares;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 14, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(colors: [Hue.hero, Hue.tile]),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  held.price.toStringAsFixed(held.price < 100 ? 2 : 0),
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (!quoted)
                  Text('尚無收盤價，以成本估算', style: mutedSmall)
                else if (ledger.quotedOn case final d?)
                  Text('${d.month}/${d.day} 收盤', style: mutedSmall),
              ],
            ),
          ),
          if (quoted)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: up ? Hue.positive : Hue.negative,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  Text(
                    before == 0 ? '—' : percentOf(held.change, before),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Hue.onAccent,
                    ),
                  ),
                  Text(
                    '${up ? '▲' : '▼'} ${perShare.abs().toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 12.5, color: Hue.onAccent),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A block of the holding's bento: a label, a big figure and a line or
/// two, on [color]'s tint.
class _Bento extends StatelessWidget {
  const _Bento({
    required this.color,
    required this.label,
    required this.value,
    required this.lines,
  });

  final Color color;
  final String label;
  final String value;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final ink = deepOf(color);
    return ColorCard(
      color: color,
      amount: 0.22,
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: ink,
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
          ),
          for (final line in lines)
            Text(line, style: TextStyle(fontSize: 12.5, color: ink)),
        ],
      ),
    );
  }
}

/// The holding's daily closes as a line over 1月, 3月, 1年 or 全部: the
/// average cost as a dashed line, the buys as dots; a finger on the
/// chart reads the day and close under it. The closes come from the
/// exchanges through [Nav.market], kept on the phone once read.
class _PriceChart extends StatefulWidget {
  const _PriceChart({
    required this.ledger,
    required this.nav,
    required this.code,
    required this.average,
    required this.buys,
  });

  final Ledger ledger;
  final Nav nav;
  final String code;
  final double average;
  final List<Entry> buys;

  @override
  State<_PriceChart> createState() => _PriceChartState();
}

class _PriceChartState extends State<_PriceChart> {
  var _range = 3;
  List<(DateTime, double)>? _closes;
  int? _touched;
  var _loading = false;

  static const _ranges = ['1月', '3月', '1年', '全部'];

  DateTime get _from {
    final today = widget.ledger.today;
    final first = widget.buys.isEmpty
        ? DateTime.utc(today.year - 1, today.month)
        : widget.buys
              .map((e) => e.date)
              .reduce((a, b) => a.isBefore(b) ? a : b);
    return switch (_range) {
      0 => DateTime.utc(today.year, today.month - 1, today.day),
      1 => DateTime.utc(today.year, today.month - 3, today.day),
      2 => DateTime.utc(today.year - 1, today.month, today.day),
      _ => first,
    };
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final market = widget.nav.market;
    if (market is! PriceHistory) return;
    final feed = market as PriceHistory;
    setState(() => _loading = true);
    final from = _from;
    final all = await feed.history(widget.code, from);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _closes = [
        for (final c in all)
          if (!c.$1.isBefore(from)) c,
      ];
      _touched = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final closes = _closes;
    final touched = _touched;
    final shown = closes == null || touched == null || touched >= closes.length
        ? null
        : closes[touched];
    final first = closes == null || closes.isEmpty ? null : closes.first.$2;
    final last = closes == null || closes.isEmpty ? null : closes.last.$2;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Hue.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: Hue.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (final (i, label) in _ranges.indexed)
                Expanded(
                  child: TextButton(
                    onPressed: () {
                      setState(() => _range = i);
                      _load();
                    },
                    style: TextButton.styleFrom(
                      backgroundColor: i == _range ? Hue.surface : null,
                      foregroundColor: i == _range ? Hue.ink : Hue.muted,
                      minimumSize: const Size(0, 40),
                    ),
                    child: Text(
                      label,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  shown == null
                      ? (_range == 3 ? '從第一次買到現在' : '這段期間')
                      : '${shown.$1.year}/${shown.$1.month}/${shown.$1.day} '
                            '收盤 ${shown.$2}',
                  style: mutedSmall,
                ),
              ),
              if (first != null && last != null && first > 0)
                Text(
                  '${last >= first ? '+' : ''}'
                  '${((last - first) * 100 / first).toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: last >= first ? Hue.positive : Hue.negative,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 170,
            child: closes == null || closes.length < 2
                ? Center(
                    child: Text(
                      _loading
                          ? '讀取收盤價…'
                          : widget.nav.market is PriceHistory
                          ? '這段期間沒有收盤價'
                          : '連上證交所、櫃買中心後才有走勢',
                      style: mutedSmall,
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, box) {
                      void touch(Offset at) {
                        final i = (at.dx / box.maxWidth * (closes.length - 1))
                            .round()
                            .clamp(0, closes.length - 1);
                        setState(() => _touched = i);
                      }

                      return Semantics(
                        label: '走勢圖',
                        child: GestureDetector(
                          onTapDown: (d) => touch(d.localPosition),
                          onHorizontalDragUpdate: (d) => touch(d.localPosition),
                          child: CustomPaint(
                            size: Size(box.maxWidth, 170),
                            painter: _LinePainter(
                              closes: closes,
                              average: widget.average,
                              buys: {
                                for (final e in widget.buys)
                                  DateTime.utc(
                                    e.date.year,
                                    e.date.month,
                                    e.date.day,
                                  ),
                              },
                              touched: touched,
                              line: Hue.positive,
                              fill: tintOf(Hue.positive, 0.25),
                              dash: Hue.investment,
                              dot: Hue.investment,
                              rule: Hue.line,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 6),
          const Row(
            children: [
              LegendKey(Hue.investment, '買進的時候'),
              SizedBox(width: 12),
              LegendKey(Hue.investment, '均價', line: true),
            ],
          ),
        ],
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({
    required this.closes,
    required this.average,
    required this.buys,
    required this.touched,
    required this.line,
    required this.fill,
    required this.dash,
    required this.dot,
    required this.rule,
  });

  final List<(DateTime, double)> closes;
  final double average;
  final Set<DateTime> buys;
  final int? touched;
  final Color line;
  final Color fill;
  final Color dash;
  final Color dot;
  final Color rule;

  @override
  void paint(Canvas canvas, Size size) {
    var low = closes.map((c) => c.$2).reduce(min);
    var high = closes.map((c) => c.$2).reduce(max);
    if (average > 0) {
      low = min(low, average);
      high = max(high, average);
    }
    if (high == low) high = low + 1;
    final pad = (high - low) * 0.08;
    low -= pad;
    high += pad;
    double x(int i) => i * size.width / (closes.length - 1);
    double y(double v) => size.height * (1 - (v - low) / (high - low));
    final path = Path()..moveTo(0, y(closes.first.$2));
    for (var i = 1; i < closes.length; i++) {
      path.lineTo(x(i), y(closes[i].$2));
    }
    final area = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(area, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeJoin = StrokeJoin.round,
    );
    if (average > 0) {
      final ay = y(average);
      final paint = Paint()
        ..color = dash
        ..strokeWidth = 1.4;
      for (var dx = 0.0; dx < size.width; dx += 10) {
        canvas.drawLine(
          Offset(dx, ay),
          Offset(min(dx + 5, size.width), ay),
          paint,
        );
      }
    }
    for (final (i, (day, price)) in closes.indexed) {
      if (!buys.contains(day)) continue;
      canvas.drawCircle(Offset(x(i), y(price)), 5, Paint()..color = dot);
    }
    final t = touched;
    if (t != null && t < closes.length) {
      final at = Offset(x(t), y(closes[t].$2));
      canvas.drawLine(
        Offset(at.dx, 0),
        Offset(at.dx, size.height),
        Paint()
          ..color = rule
          ..strokeWidth = 1.5,
      );
      canvas.drawCircle(at, 6, Paint()..color = line);
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.closes != closes || old.touched != touched || old.average != average;
}
