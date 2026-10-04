import 'dart:math';

import 'package:flutter/material.dart';

import '../charts/chart_data.dart';
import '../theme.dart';
import 'home_data.dart';

/// Investments: the total and today's move, over a field of 100 dots
/// shared out by market value. Tap the dots to see one holding.
class HoldingsCard extends StatefulWidget {
  const HoldingsCard({super.key, required this.data});

  final HomeData data;

  @override
  State<HoldingsCard> createState() => _HoldingsCardState();
}

class _HoldingsCardState extends State<HoldingsCard> {
  int? _selected;

  static const _columns = 20;
  static const _rows = 5;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final holdings = widget.data.holdings;
    final value = holdings.fold(0, (sum, h) => sum + h.value);
    final cost = holdings.fold(0, (sum, h) => sum + h.cost);
    final change = holdings.fold(0, (sum, h) => sum + h.change);
    final counts = waffleCounts([
      for (final h in holdings) h.value,
    ], _columns * _rows);
    final owners = [
      for (final (i, count) in counts.indexed) ...List.filled(count, i),
    ];
    final muted = text.bodySmall?.copyWith(color: Palette.muted);
    final gain = '${signed(value - cost)}（${percent(value - cost, cost)}）';
    final selected = _selected;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('投資市值', style: muted),
                const Spacer(),
                Text(
                  '今日 ${signed(change)}',
                  style: text.bodySmall?.copyWith(color: gainColor(change)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              groupDigits(value),
              style: text.headlineMedium?.copyWith(
                fontWeight: FontWeight.w300,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '未實現 $gain',
              style: muted,
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final cell = width / _columns;
                return GestureDetector(
                  onTapUp: (details) {
                    final at = details.localPosition;
                    final column = (at.dx / cell).floor();
                    final row = (at.dy / cell).floor();
                    if (column < 0 || column >= _columns) return;
                    if (row < 0 || row >= _rows) return;
                    final index = column * _rows + row;
                    final owner = index < owners.length ? owners[index] : null;
                    setState(() {
                      _selected = owner == _selected ? null : owner;
                    });
                  },
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(end: selected == null ? 0.0 : 1.0),
                    duration: const Duration(milliseconds: 250),
                    builder: (context, focus, _) => CustomPaint(
                      size: Size(width, cell * _rows),
                      painter: _DotsPainter(
                        owners: owners,
                        colors: [for (final h in holdings) h.color],
                        rows: _rows,
                        selected: selected,
                        focus: focus,
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              alignment: Alignment.topLeft,
              child: selected == null
                  ? Text(
                      [
                        for (final h in holdings.take(3))
                          '${h.name} ${(h.value * 100 / value).round()}%',
                      ].join('　'),
                      style: muted,
                    )
                  : _HoldingDetail(holdings[selected], value),
            ),
          ],
        ),
      ),
    );
  }
}

/// `1200` → `+1,200`.
String signed(int value) =>
    value > 0 ? '+${groupDigits(value)}' : groupDigits(value);

/// [part] of [whole] with a sign and one decimal, such as `+12.5%`.
String percent(int part, int whole) {
  if (whole == 0) return '—';
  final value = part * 100 / whole;
  return '${value > 0 ? '+' : ''}${value.toStringAsFixed(1)}%';
}

/// Taiwan's market colours, softened: red for up, green for down.
Color gainColor(int value) => value > 0
    ? Palette.clay
    : value < 0
    ? Palette.olive
    : Palette.muted;

/// [values] shared out as [total] whole dots by largest remainder, so the
/// dots always add up to [total].
List<int> waffleCounts(List<int> values, int total) {
  final sum = values.fold(0, (a, b) => a + b);
  if (sum == 0) return List.filled(values.length, 0);
  final exact = [for (final v in values) v * total / sum];
  final counts = [for (final e in exact) e.floor()];
  final order = [for (var i = 0; i < values.length; i++) i]
    ..sort((a, b) => (exact[b] - counts[b]).compareTo(exact[a] - counts[a]));
  var left = total - counts.fold(0, (a, b) => a + b);
  for (final i in order) {
    if (left == 0) break;
    counts[i]++;
    left--;
  }
  return counts;
}

class _DotsPainter extends CustomPainter {
  _DotsPainter({
    required this.owners,
    required this.colors,
    required this.rows,
    required this.selected,
    required this.focus,
  });

  /// The holding each dot belongs to, filled column by column.
  final List<int> owners;
  final List<Color> colors;
  final int rows;
  final int? selected;
  final double focus;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.height / rows;
    final radius = min(cell * 0.32, 6.0);
    for (final (index, owner) in owners.indexed) {
      final centre = Offset(
        cell * (index ~/ rows + 0.5),
        cell * (index % rows + 0.5),
      );
      final picked = owner == selected;
      final color = selected == null || picked
          ? colors[owner]
          : colors[owner].withValues(alpha: 1 - 0.75 * focus);
      final grow = picked ? 1 + 0.2 * focus : 1.0;
      canvas.drawCircle(centre, radius * grow, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_DotsPainter old) =>
      old.selected != selected || old.focus != focus || old.owners != owners;
}

class _HoldingDetail extends StatelessWidget {
  const _HoldingDetail(this.holding, this.total);

  final Holding holding;
  final int total;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: Palette.muted);
    final share = (holding.value * 100 / total).toStringAsFixed(1);
    final rate = percent(holding.gain, holding.cost);
    final gain = '${signed(holding.gain)}（$rate）';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(holding.name, style: text.titleSmall),
            const SizedBox(width: 6),
            Text(holding.code, style: muted),
            const Spacer(),
            Text(groupDigits(holding.value), style: text.titleMedium),
          ],
        ),
        const SizedBox(height: 4),
        Text.rich(
          TextSpan(
            style: muted,
            children: [
              TextSpan(text: '占 $share%　損益 '),
              TextSpan(
                text: gain,
                style: TextStyle(color: gainColor(holding.gain)),
              ),
              const TextSpan(text: '　今日 '),
              TextSpan(
                text: signed(holding.change),
                style: TextStyle(color: gainColor(holding.change)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
