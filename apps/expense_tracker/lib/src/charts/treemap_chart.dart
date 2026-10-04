import 'dart:math';

import 'package:flutter/material.dart';

import 'chart_data.dart';
import 'chart_parts.dart';

/// Option E: a month's spending as tiles sized by amount. Tap a category
/// to open its subcategories; tap again or 「全部」 to go back.
class TreemapChart extends StatefulWidget {
  const TreemapChart({super.key, required this.data});

  final ChartData data;

  @override
  State<TreemapChart> createState() => _TreemapChartState();
}

class _TreemapChartState extends State<TreemapChart> {
  late int _month = widget.data.months.length - 1;
  CategorySlice? _open;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categories = widget.data.categories[_month];
    final open = _open;
    final tiles = open?.children ?? categories;
    final total = tiles.fold(0, (sum, tile) => sum + tile.amount);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MonthStepper(
          months: widget.data.months,
          index: _month,
          suffix: ' 支出',
          onChanged: (index) => setState(() {
            _month = index;
            _open = null;
          }),
        ),
        Row(
          children: [
            TextButton(
              onPressed: open == null
                  ? null
                  : () => setState(() => _open = null),
              child: const Text('全部'),
            ),
            if (open != null) ...[
              const Icon(Icons.chevron_right, size: 18),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(open.name, style: theme.textTheme.titleSmall),
              ),
            ],
            const Spacer(),
            Text(groupDigits(total), style: theme.textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 300,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final bounds = Offset.zero & constraints.biggest;
              final rects = treemapLayout([
                for (final tile in tiles) tile.amount,
              ], bounds);
              return GestureDetector(
                onTapUp: (details) {
                  if (open != null) {
                    setState(() => _open = null);
                    return;
                  }
                  for (final (i, rect) in rects.indexed) {
                    if (rect.contains(details.localPosition)) {
                      final tapped = tiles[i];
                      if (tapped.children.isNotEmpty) {
                        setState(() => _open = tapped);
                      }
                      return;
                    }
                  }
                },
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(
                      scale: Tween(begin: 0.92, end: 1.0).animate(animation),
                      child: child,
                    ),
                  ),
                  child: CustomPaint(
                    key: ValueKey((_month, open?.name)),
                    size: Size.infinite,
                    painter: _TreemapPainter(
                      tiles: tiles,
                      rects: rects,
                      total: total,
                      shaded: open != null,
                      text: theme.textTheme,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Splits [bounds] into one rectangle per value, with areas in proportion
/// and as close to square as the values allow (the squarified layout of
/// Bruls, Huizing and van Wijk). [values] should be largest first.
List<Rect> treemapLayout(List<int> values, Rect bounds) {
  final total = values.fold(0, (sum, v) => sum + v);
  if (total <= 0 || bounds.isEmpty) {
    return List.filled(values.length, Rect.zero);
  }
  final scale = bounds.width * bounds.height / total;
  final areas = [for (final v in values) v * scale];
  final rects = <Rect>[];
  var rest = bounds;
  var start = 0;
  while (start < areas.length) {
    final side = min(rest.width, rest.height);
    var end = start + 1;
    var best = _worst(areas.sublist(start, end), side);
    while (end < areas.length) {
      final next = _worst(areas.sublist(start, end + 1), side);
      if (next > best) break;
      best = next;
      end++;
    }
    final row = areas.sublist(start, end);
    final rowArea = row.fold(0.0, (sum, a) => sum + a);
    if (rest.width >= rest.height) {
      final width = rowArea / rest.height;
      var top = rest.top;
      for (final area in row) {
        final height = area / width;
        rects.add(Rect.fromLTWH(rest.left, top, width, height));
        top += height;
      }
      rest = Rect.fromLTRB(
        rest.left + width,
        rest.top,
        rest.right,
        rest.bottom,
      );
    } else {
      final height = rowArea / rest.width;
      var left = rest.left;
      for (final area in row) {
        final width = area / height;
        rects.add(Rect.fromLTWH(left, rest.top, width, height));
        left += width;
      }
      rest = Rect.fromLTRB(
        rest.left,
        rest.top + height,
        rest.right,
        rest.bottom,
      );
    }
    start = end;
  }
  return rects;
}

/// The worst aspect ratio in a row of [areas] laid along [side].
double _worst(List<double> areas, double side) {
  final sum = areas.fold(0.0, (s, a) => s + a);
  if (sum <= 0 || side <= 0) return double.infinity;
  final largest = areas.reduce(max);
  final smallest = areas.reduce(min);
  final sideSquared = side * side;
  final sumSquared = sum * sum;
  return max(
    sideSquared * largest / sumSquared,
    sumSquared / (sideSquared * smallest),
  );
}

class _TreemapPainter extends CustomPainter {
  _TreemapPainter({
    required this.tiles,
    required this.rects,
    required this.total,
    required this.shaded,
    required this.text,
  });

  final List<CategorySlice> tiles;
  final List<Rect> rects;
  final int total;

  /// Subcategories share their parent's colour, so lighten each in turn.
  final bool shaded;
  final TextTheme text;

  @override
  void paint(Canvas canvas, Size size) {
    for (final (i, tile) in tiles.indexed) {
      final rect = rects[i].deflate(2);
      if (rect.isEmpty) continue;
      final color = shaded
          ? Color.lerp(tile.color, Colors.white, min(0.6, i * 0.14))!
          : tile.color;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(8)),
        Paint()..color = color,
      );
      final dark = color.computeLuminance() > 0.5;
      final ink = dark ? Colors.black87 : Colors.white;
      final room = rect.width - 12;
      if (rect.width < 36 || rect.height < 22) continue;
      paintText(
        canvas,
        tile.name,
        text.labelLarge!.copyWith(color: ink, fontWeight: FontWeight.w700),
        rect.topLeft.translate(6, 5),
        anchor: Offset.zero,
        maxWidth: room,
      );
      if (rect.height < 44) continue;
      final share = (tile.amount / total * 100).toStringAsFixed(0);
      paintText(
        canvas,
        '${groupDigits(tile.amount)}・$share%',
        text.labelSmall!.copyWith(color: ink),
        rect.topLeft.translate(6, 25),
        anchor: Offset.zero,
        maxWidth: room,
      );
    }
  }

  @override
  bool shouldRepaint(_TreemapPainter old) =>
      old.tiles != tiles || old.rects != rects || old.text != text;
}
