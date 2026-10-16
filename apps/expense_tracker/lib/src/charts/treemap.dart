import 'dart:math';

import 'package:flutter/material.dart';

import '../look/paint.dart';
import '../look/theme.dart';

/// Splits [bounds] into one rectangle per value, areas in proportion and
/// as close to square as the values allow (the squarified layout of
/// Bruls, Huizing and van Wijk). [values] should be largest first.
List<Rect> treemapLayout(List<int> values, Rect bounds) {
  final total = values.fold(0, (sum, v) => sum + max(0, v));
  if (total <= 0 || bounds.isEmpty) {
    return List.filled(values.length, Rect.zero);
  }
  final scale = bounds.width * bounds.height / total;
  final areas = [for (final v in values) max(0, v) * scale];
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
      final width = rest.height == 0 ? 0.0 : rowArea / rest.height;
      var top = rest.top;
      for (final area in row) {
        final height = width == 0 ? 0.0 : area / width;
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
      final height = rest.width == 0 ? 0.0 : rowArea / rest.width;
      var left = rest.left;
      for (final area in row) {
        final width = height == 0 ? 0.0 : area / height;
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

double _worst(List<double> areas, double side) {
  final sum = areas.fold(0.0, (s, a) => s + a);
  final smallest = areas.reduce(min);
  if (sum <= 0 || side <= 0 || smallest <= 0) return double.infinity;
  final largest = areas.reduce(max);
  final sideSquared = side * side;
  final sumSquared = sum * sum;
  return max(
    sideSquared * largest / sumSquared,
    sumSquared / (sideSquared * smallest),
  );
}

/// Tile sizes for [Treemap]: the order of amounts is kept but small ones
/// are lifted, `1 + log2(amount / smallest) / 6` (as in v114), so a few
/// thousand in cash still gets a tile beside hundreds of thousands.
List<int> _shownWeights(List<int> amounts) {
  final positive = [
    for (final a in amounts)
      if (a > 0) a,
  ];
  if (positive.isEmpty) return amounts;
  final smallest = positive.reduce(min);
  return [
    for (final a in amounts)
      a <= 0 ? 0 : ((1 + log(a / smallest) / ln2 / 6) * 1000).round(),
  ];
}

/// Labelled tiles, larger amounts larger. Tap a tile to pick it (the others
/// fade); tap the picked tile again to open it ([onOpen]), as v114 does.
class Treemap extends StatelessWidget {
  const Treemap({
    super.key,
    required this.tiles,
    required this.selected,
    required this.onSelect,
    this.onOpen,
    this.height = 160,
  });

  final List<(String, int, Color)> tiles;
  final int? selected;
  final ValueChanged<int?> onSelect;
  final ValueChanged<int>? onOpen;
  final double height;

  @override
  Widget build(BuildContext context) {
    // Its own layer: chart animations and taps do not repaint the page.
    return RepaintBoundary(
      child: SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final rects = treemapLayout(
              _shownWeights([for (final t in tiles) t.$2]),
              Offset.zero & constraints.biggest,
            );
            return GestureDetector(
              onTapDown: (details) {
                for (final (i, rect) in rects.indexed) {
                  if (rect.contains(details.localPosition)) {
                    final open = onOpen;
                    if (i == selected && open != null) {
                      open(i);
                    } else {
                      onSelect(i == selected ? null : i);
                    }
                    return;
                  }
                }
              },
              child: CustomPaint(
                size: Size.infinite,
                painter: _TreemapPainter(
                  tiles: tiles,
                  rects: rects,
                  selected: selected,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TreemapPainter extends CustomPainter {
  _TreemapPainter({
    required this.tiles,
    required this.rects,
    required this.selected,
  });

  final List<(String, int, Color)> tiles;
  final List<Rect> rects;
  final int? selected;

  @override
  void paint(Canvas canvas, Size size) {
    for (final (i, (name, _, color)) in tiles.indexed) {
      final rect = rects[i].deflate(2);
      if (rect.isEmpty) continue;
      final picked = i == selected;
      final faded = selected != null && !picked;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        Paint()..color = faded ? color.withValues(alpha: 0.4) : color,
      );
      if (rect.width < 36 || rect.height < 20) continue;
      final label = TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: Hue.ink.withValues(alpha: faded ? 0.5 : 0.9),
      );
      paintText(canvas, name, label, rect.center, maxWidth: rect.width - 8);
    }
  }

  @override
  bool shouldRepaint(_TreemapPainter old) =>
      old.selected != selected || old.rects != rects || old.tiles != tiles;
}
