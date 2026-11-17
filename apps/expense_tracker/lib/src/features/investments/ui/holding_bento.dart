part of 'holding_page.dart';

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
      padding: const EdgeInsets.fromLTRB(
        Space.s4,
        Space.s3,
        Space.s3,
        Space.s3,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: TextSize.small,
              fontWeight: FontWeight.w800,
              color: ink,
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: TextSize.large,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          for (final line in lines)
            Text(
              line,
              style: TextStyle(fontSize: TextSize.caption, color: ink),
            ),
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
        const SizedBox(height: Space.s2),
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
              const SizedBox(width: Space.s2),
            ],
            Expanded(
              child: buy != null
                  ? Text.rich(
                      TextSpan(
                        text:
                            '${formatYMd(buy.date)} '
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
                          : '${formatYMd(shown.$1)} '
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
        const SizedBox(height: Space.s2),
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
          const SizedBox(height: Space.s1),
          Padding(
            padding: const EdgeInsets.only(right: _gutter),
            child: Row(
              children: [
                for (final (i, label) in _ticks(closes).indexed) ...[
                  if (i > 0) const Spacer(),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: TextSize.tiny,
                      color: Hue.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: Space.s2),
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
    String at(DateTime d) => long ? formatYM(d) : formatMd(d);
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
      final text = layoutText(
        _label(v),
        TextStyle(fontSize: TextSize.tiny, color: words),
      );
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
        TextStyle(
          fontSize: TextSize.tiny,
          fontWeight: FontWeight.w800,
          color: onTag,
        ),
      );
      final at = y(v);
      final box = RRect.fromRectAndRadius(
        Rect.fromLTWH(width + 2, at - 10, gutter - 2, 20),
        const Radius.circular(Radii.small),
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
