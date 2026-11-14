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
              CenterHeader(code, onBack: nav.back),
              _SoldOut(ledger: ledger, trades: trades),
              _TradeBoard(
                ledger: ledger,
                nav: nav,
                trades: trades,
                lots: const [],
              ),
            ],
          );
        }
        final tone = held.gain < 0 ? Hue.negative : Hue.positive;
        final quoted = ledger.hasQuote(code);
        final lots = ledger.lotsOf(code);
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
                    _DividendCard(
                      ledger: ledger,
                      total: held.dividends,
                      next: next,
                      months: payingMonths(ledger, code),
                      realized: held.realized,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                for (final (i, (type, label, color)) in const [
                  (EntryType.buy, '＋ 買進', _buyHue),
                  (EntryType.sell, '賣出', _sellHue),
                  (EntryType.dividend, '記股息', _dividendHue),
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
                      tinted: true,
                    ),
                  ),
                ],
              ],
            ),
            _TradeBoard(ledger: ledger, nav: nav, trades: trades, lots: lots),
          ],
        );
      },
    );
  }
}

const _buyHue = Palette.indigo;
const _sellHue = Palette.brick;
const _dividendHue = Palette.gold;

/// 股息 on its gold tint: the total, when the next one is due and about
/// how much, and the twelve months with those it pays in filled.
class _DividendCard extends StatelessWidget {
  const _DividendCard({
    required this.ledger,
    required this.total,
    required this.next,
    required this.months,
    required this.realized,
  });

  final Ledger ledger;
  final int total;
  final DividendGuess? next;
  final List<int> months;
  final int realized;

  @override
  Widget build(BuildContext context) {
    final ink = deepOf(_dividendHue);
    final coming = next;
    return ColorCard(
      color: _dividendHue,
      amount: 0.22,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '股息',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: ink,
                      ),
                    ),
                    Text(
                      ledger.orDots(groupDigits(total)),
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              if (coming != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '下次 ${coming.month.month} 月',
                      style: TextStyle(fontSize: 12.5, color: ink),
                    ),
                    Text(
                      '約 ${ledger.orDots(groupDigits(coming.amount))}',
                      style: TextStyle(fontSize: 12.5, color: ink),
                    ),
                  ],
                ),
            ],
          ),
          if (realized != 0)
            Text(
              '已實現 ${ledger.orDots(signed(realized))}',
              style: TextStyle(fontSize: 12.5, color: ink),
            ),
          if (months.isNotEmpty) ...[
            const SizedBox(height: 10),
            Semantics(
              label: '配息月份 ${months.join('、')} 月',
              child: ExcludeSemantics(
                child: Row(
                  children: [
                    for (var m = 1; m <= 12; m++) ...[
                      if (m > 1) const SizedBox(width: 4),
                      Expanded(
                        child: Container(
                          height: 12,
                          decoration: BoxDecoration(
                            color: months.contains(m)
                                ? _dividendHue
                                : Hue.white.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 交易紀錄 on a white board: each buy, sale and dividend with its date,
/// shares and price, and what was held from the start, newest first.
class _TradeBoard extends StatelessWidget {
  const _TradeBoard({
    required this.ledger,
    required this.nav,
    required this.trades,
    required this.lots,
  });

  final Ledger ledger;
  final Nav nav;
  final List<Entry> trades;
  final List<Lot> lots;

  @override
  Widget build(BuildContext context) {
    final opening = [
      for (final l in lots)
        if (l.isOpening) l,
    ];
    final shown = [...trades]..sort((a, b) => b.date.compareTo(a.date));
    final count = shown.length + opening.length;
    if (count == 0) return const SizedBox.shrink();
    String day(DateTime d) => '${d.year}/${d.month}/${d.day}';
    final rows = <Widget>[
      for (final e in shown)
        _TradeRow(
          glyph: switch (e.type) {
            EntryType.sell => Glyph.payout,
            EntryType.dividend => Glyph.dividend,
            _ => Glyph.add,
          },
          color: switch (e.type) {
            EntryType.sell => _sellHue,
            EntryType.dividend => _dividendHue,
            _ => _buyHue,
          },
          title: switch (e.type) {
            EntryType.buy => '買進',
            EntryType.sell => '賣出',
            _ when e.isReduction => '減資',
            _ when e.shares > 0 => '配股',
            _ => '股息',
          },
          when: e.type == EntryType.dividend
              ? '${e.date.month}/${e.date.day}'
              : day(e.date),
          detail: e.shares != 0 && e.type != EntryType.dividend
              ? '${groupDigits(e.shares)} 股 × '
                    '${_price(e.amount / e.shares.abs())}'
              : e.shares != 0
              ? '${groupDigits(e.shares.abs())} 股'
              : null,
          amount: switch (e.type) {
            EntryType.buy => ledger.orDots(signed(-(e.amount + e.fee))),
            EntryType.sell => ledger.orDots(signed(e.amount - e.fee)),
            _ => ledger.orDots(signed(e.dividendNet)),
          },
          amountColor: e.type == EntryType.buy ? Hue.ink : Hue.positive,
          onTap: () => nav.showEntry(e),
        ),
      for (final l in opening)
        _TradeRow(
          glyph: Glyph.add,
          color: _buyHue,
          title: '期初持有',
          when: '',
          detail: '${ledger.orDots(groupDigits(l.shares))} 股',
          amount: '成本 ${ledger.orDots(groupDigits(l.cost))}',
          amountColor: Hue.ink,
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        TitleRow('交易紀錄', trailing: Text('共 $count 筆', style: mutedSmall)),
        QuoteBoard([
          for (final (i, row) in rows.indexed)
            Container(decoration: i == 0 ? null : ruleAbove, child: row),
        ]),
      ],
    );
  }

  static String _price(double p) =>
      p == p.roundToDouble() ? groupDigits(p.round()) : p.toStringAsFixed(2);
}

class _TradeRow extends StatelessWidget {
  const _TradeRow({
    required this.glyph,
    required this.color,
    required this.title,
    required this.when,
    required this.detail,
    required this.amount,
    required this.amountColor,
    this.onTap,
  });

  final Glyph glyph;
  final Color color;
  final String title;
  final String when;
  final String? detail;
  final String amount;
  final Color amountColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final line = detail;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tintOf(color, 0.22),
                borderRadius: BorderRadius.circular(14),
              ),
              child: GlyphIcon(glyph, size: 20, color: deepOf(color)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    TextSpan(
                      text: title,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                      children: [
                        if (when.isNotEmpty)
                          TextSpan(
                            text: '  $when',
                            style: const TextStyle(
                              fontWeight: FontWeight.w400,
                              color: Hue.muted,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (line != null) OneLine(line, style: mutedSmall),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              amount,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: amountColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A stock no longer held: 已賣光, what the sales brought in all and the
/// dividends it paid.
class _SoldOut extends StatelessWidget {
  const _SoldOut({required this.ledger, required this.trades});

  final Ledger ledger;
  final List<Entry> trades;

  @override
  Widget build(BuildContext context) {
    var sold = 0;
    var paid = 0;
    var dividends = 0;
    for (final e in trades) {
      switch (e.type) {
        case EntryType.sell:
          sold += e.amount - e.fee;
        case EntryType.buy:
          paid += e.amount + e.fee;
        case EntryType.dividend:
          dividends += e.dividendNet;
        default:
          break;
      }
    }
    final made = sold + dividends - paid;
    return HeroCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '已賣光',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: Hue.accent,
            ),
          ),
          Text(
            ledger.orDots(signed(made)),
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color: made < 0 ? Hue.negative : Hue.positive,
            ),
          ),
          Text(
            '賣出 ${ledger.orDots(groupDigits(sold))} · '
            '買進 ${ledger.orDots(groupDigits(paid))}'
            '${dividends == 0 ? '' : ' · 股息 ${ledger.orDots(groupDigits(dividends))}'}',
            style: mutedSmall,
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
    return HeroCard(
      padding: const EdgeInsets.fromLTRB(20, 14, 14, 14),
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

/// The holding's daily closes as a line over 1月, 3月, 1年 or 全部, on
/// the page itself: the average cost as a dashed line, the buys as dots,
/// today's close and the average named on the right. A finger on the line
/// reads the day and close under it; on a buy, that buy: when, how many
/// at what price, and how it stands now. The closes come from the
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
  Entry? _buy;
  var _loading = false;

  static const _ranges = ['1月', '3月', '1年', '全部'];
  static const _gutter = 46.0;
  static const _height = 190.0;

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
    final feed = widget.nav.prices;
    if (feed == null) return;
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
      _buy = null;
    });
  }

  static DateTime _day(DateTime d) => DateTime.utc(d.year, d.month, d.day);

  String _price(double p) => p.toStringAsFixed(p < 100 ? 2 : 0);

  @override
  Widget build(BuildContext context) {
    final closes = _closes;
    final touched = _touched;
    final buy = _buy;
    final shown = closes == null || touched == null || touched >= closes.length
        ? null
        : closes[touched];
    final first = closes == null || closes.isEmpty ? null : closes.first.$2;
    final last = closes == null || closes.isEmpty ? null : closes.last.$2;
    final price = widget.ledger.holding(widget.code)?.price ?? last ?? 0;
    final buyPrice = buy == null || buy.shares == 0
        ? null
        : buy.amount / buy.shares;
    Widget change(double from, double to, String prefix) {
      final up = to >= from;
      return Text(
        '$prefix${up ? '+' : ''}${((to - from) * 100 / from).toStringAsFixed(1)}%',
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: up ? Hue.positive : Hue.negative,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Segments(
          labels: _ranges,
          selected: _range,
          onChanged: (i) {
            setState(() => _range = i);
            _load();
          },
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            if (buy != null) ...[
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: Hue.investment,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: buy != null
                  ? Text.rich(
                      TextSpan(
                        text:
                            '${buy.date.year}/${buy.date.month}/${buy.date.day} '
                            '買 ${groupDigits(buy.shares)} 股',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                        children: [
                          if (buyPrice != null)
                            TextSpan(
                              text: '  @ ${_price(buyPrice)}',
                              style: mutedSmall,
                            ),
                        ],
                      ),
                    )
                  : Text(
                      shown == null
                          ? (_range == 3 ? '從第一次買到現在' : '這段期間')
                          : '${shown.$1.year}/${shown.$1.month}/${shown.$1.day} '
                                '收盤 ${_price(shown.$2)}',
                      style: mutedSmall,
                    ),
            ),
            if (buyPrice != null && buyPrice > 0)
              change(buyPrice, price, '這批 ')
            else if (first != null && last != null && first > 0)
              change(first, last, ''),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: _height,
          child: closes == null || closes.length < 2
              ? Center(
                  child: Text(
                    _loading
                        ? '讀取收盤價…'
                        : widget.nav.prices != null
                        ? '這段期間沒有收盤價'
                        : '連上證交所、櫃買中心後才有走勢',
                    style: mutedSmall,
                  ),
                )
              : LayoutBuilder(
                  builder: (context, box) {
                    final plot = box.maxWidth - _gutter;
                    final scale = _Scale.of(closes, widget.average, _height);
                    final buys = {for (final e in widget.buys) _day(e.date): e};
                    void touch(Offset at) {
                      final i = (at.dx / plot * (closes.length - 1))
                          .round()
                          .clamp(0, closes.length - 1);
                      // A buy within a finger's reach is read as that buy.
                      Entry? near;
                      var nearest = 24.0;
                      for (final (j, (day, close)) in closes.indexed) {
                        final hit = buys[day];
                        if (hit == null) continue;
                        final d =
                            (Offset(
                                      j * plot / (closes.length - 1),
                                      scale.y(close),
                                    ) -
                                    at)
                                .distance;
                        if (d < nearest) {
                          nearest = d;
                          near = hit;
                        }
                      }
                      setState(() {
                        _buy = near;
                        _touched = near == null ? i : null;
                      });
                    }

                    return Semantics(
                      label: '走勢圖',
                      child: GestureDetector(
                        onTapDown: (d) => touch(d.localPosition),
                        onHorizontalDragUpdate: (d) => touch(d.localPosition),
                        child: CustomPaint(
                          size: Size(box.maxWidth, _height),
                          painter: _LinePainter(
                            closes: closes,
                            scale: scale,
                            gutter: _gutter,
                            average: widget.average,
                            price: price,
                            buys: buys.keys.toSet(),
                            chosen: buy == null ? null : _day(buy.date),
                            touched: touched,
                            line: Hue.positive,
                            fill: tintOf(Hue.positive, 0.25),
                            dash: Hue.investment,
                            rule: Hue.line,
                            words: Hue.muted,
                            onTag: Hue.onAccent,
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        if (closes != null && closes.length >= 2) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(right: _gutter),
            child: Row(
              children: [
                for (final (i, label) in _ticks(closes).indexed) ...[
                  if (i > 0) const Spacer(),
                  Text(
                    label,
                    style: const TextStyle(fontSize: 11.5, color: Hue.muted),
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [
            LegendKey(
              Hue.investment,
              widget.buys.isEmpty ? '我買的時候' : '我買的時候（點一下看那批）',
            ),
            const LegendKey(Hue.investment, '均價', line: true),
          ],
        ),
      ],
    );
  }

  /// Three dates under the line: its start, middle and 現在; years for a
  /// long span, month and day for a short one.
  List<String> _ticks(List<(DateTime, double)> closes) {
    final start = closes.first.$1;
    final middle = closes[closes.length ~/ 2].$1;
    final long = closes.last.$1.difference(start).inDays > 400;
    String at(DateTime d) =>
        long ? '${d.year}/${d.month}' : '${d.month}/${d.day}';
    return [at(start), at(middle), '現在'];
  }
}

/// Where a price sits on the chart: the closes and the average, with a
/// little room above and below.
final class _Scale {
  const _Scale(this.low, this.high, this.height);

  factory _Scale.of(
    List<(DateTime, double)> closes,
    double average,
    double height,
  ) {
    var low = closes.map((c) => c.$2).reduce(min);
    var high = closes.map((c) => c.$2).reduce(max);
    if (average > 0) {
      low = min(low, average);
      high = max(high, average);
    }
    if (high == low) high = low + 1;
    final pad = (high - low) * 0.08;
    return _Scale(low - pad, high + pad, height);
  }

  final double low;
  final double high;
  final double height;

  double y(double v) => height * (1 - (v - low) / (high - low));
}

class _LinePainter extends CustomPainter {
  _LinePainter({
    required this.closes,
    required this.scale,
    required this.gutter,
    required this.average,
    required this.price,
    required this.buys,
    required this.chosen,
    required this.touched,
    required this.line,
    required this.fill,
    required this.dash,
    required this.rule,
    required this.words,
    required this.onTag,
  });

  final List<(DateTime, double)> closes;
  final _Scale scale;
  final double gutter;
  final double average;
  final double price;
  final Set<DateTime> buys;
  final DateTime? chosen;
  final int? touched;
  final Color line;
  final Color fill;
  final Color dash;
  final Color rule;
  final Color words;
  final Color onTag;

  String _label(double v) => v.toStringAsFixed(v < 100 ? 1 : 0);

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width - gutter;
    double x(int i) => i * width / (closes.length - 1);
    final y = scale.y;
    // Three faint levels with their prices on the right.
    final tagged = [if (average > 0) y(average), if (price > 0) y(price)];
    for (var k = 0; k < 3; k++) {
      final v = scale.low + (scale.high - scale.low) * (0.15 + k * 0.35);
      final at = y(v);
      // A level under a price's tag keeps its line, not its words.
      final hidden = tagged.any((t) => (t - at).abs() < 18);
      canvas.drawLine(
        Offset(0, at),
        Offset(width, at),
        Paint()
          ..color = rule
          ..strokeWidth = 1,
      );
      if (hidden) continue;
      final text = layoutText(_label(v), TextStyle(fontSize: 11, color: words));
      text.paint(canvas, Offset(width + 6, at - text.height / 2));
    }
    final path = Path()..moveTo(0, y(closes.first.$2));
    for (var i = 1; i < closes.length; i++) {
      path.lineTo(x(i), y(closes[i].$2));
    }
    final area = Path.from(path)
      ..lineTo(width, size.height)
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
    void tag(double v, Color color) {
      final text = layoutText(
        _label(v),
        TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: onTag),
      );
      final at = y(v);
      final box = RRect.fromRectAndRadius(
        Rect.fromLTWH(width + 2, at - 10, gutter - 2, 20),
        const Radius.circular(6),
      );
      canvas.drawRRect(box, Paint()..color = color);
      text.paint(
        canvas,
        Offset(width + 2 + (gutter - 2 - text.width) / 2, at - text.height / 2),
      );
    }

    if (average > 0) {
      final ay = y(average);
      final paint = Paint()
        ..color = dash
        ..strokeWidth = 1.4;
      for (var dx = 0.0; dx < width; dx += 10) {
        canvas.drawLine(Offset(dx, ay), Offset(min(dx + 5, width), ay), paint);
      }
      tag(average, dash);
    }
    if (price > 0) tag(price, line);
    for (final (i, (day, close)) in closes.indexed) {
      if (!buys.contains(day)) continue;
      final at = Offset(x(i), y(close));
      if (day == chosen) {
        canvas.drawLine(
          Offset(at.dx, 0),
          Offset(at.dx, size.height),
          Paint()
            ..color = rule
            ..strokeWidth = 1.5,
        );
        canvas.drawCircle(
          at,
          10,
          Paint()..color = dash.withValues(alpha: 0.25),
        );
        canvas.drawCircle(at, 6.5, Paint()..color = dash);
      } else {
        canvas.drawCircle(at, 5, Paint()..color = dash);
      }
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
      old.closes != closes ||
      old.touched != touched ||
      old.chosen != chosen ||
      old.average != average ||
      old.price != price;
}
