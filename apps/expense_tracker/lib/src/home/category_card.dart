import 'package:flutter/material.dart';

import '../charts/chart_data.dart';
import '../theme.dart';
import 'home_data.dart';

/// Where this month's money went, as one thin strip split by category.
/// Tap a piece to see its amount, last month's, and what it was spent on.
class CategoryCard extends StatefulWidget {
  const CategoryCard({super.key, required this.data});

  final HomeData data;

  @override
  State<CategoryCard> createState() => _CategoryCardState();
}

class _CategoryCardState extends State<CategoryCard> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final slices = widget.data.categories;
    final total = slices.fold(0, (sum, s) => sum + s.amount);
    final muted = text.bodySmall?.copyWith(color: Palette.muted);
    final selected = _selected;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('花在哪裡', style: muted),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final pieces = stripPieces([
                  for (final s in slices) s.amount,
                ], width);
                return GestureDetector(
                  onTapUp: (details) {
                    final x = details.localPosition.dx;
                    for (final (i, (left, right)) in pieces.indexed) {
                      if (x >= left - 1 && x <= right + 1) {
                        setState(() => _selected = i == _selected ? null : i);
                        return;
                      }
                    }
                  },
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(end: selected == null ? 0.0 : 1.0),
                    duration: const Duration(milliseconds: 250),
                    builder: (context, focus, _) => CustomPaint(
                      size: Size(width, 28),
                      painter: _StripPainter(
                        slices: slices,
                        pieces: pieces,
                        selected: selected,
                        focus: focus,
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.topLeft,
                children: [...previous, if (current != null) current],
              ),
              child: selected == null
                  ? Text(
                      [
                        for (final s in slices.take(3))
                          '${s.name} ${(s.amount * 100 / total).round()}%',
                      ].join('　'),
                      key: const ValueKey('summary'),
                      style: muted,
                    )
                  : _Detail(
                      key: ValueKey(selected),
                      slice: slices[selected],
                      total: total,
                      last: widget.data.lastMonth[slices[selected].name],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The left and right edge of each piece of a strip [width] wide, with a
/// small gap between pieces. Every piece is at least 3 wide, so a small
/// category can still be tapped.
List<(double, double)> stripPieces(List<int> amounts, double width) {
  const gap = 2.0;
  const least = 3.0;
  final total = amounts.fold(0, (sum, a) => sum + a);
  if (total == 0 || amounts.isEmpty) return const [];
  final room = width - gap * (amounts.length - 1) - least * amounts.length;
  final pieces = <(double, double)>[];
  var left = 0.0;
  for (final amount in amounts) {
    final right = left + least + room * amount / total;
    pieces.add((left, right));
    left = right + gap;
  }
  return pieces;
}

class _StripPainter extends CustomPainter {
  _StripPainter({
    required this.slices,
    required this.pieces,
    required this.selected,
    required this.focus,
  });

  final List<CategorySlice> slices;
  final List<(double, double)> pieces;
  final int? selected;

  /// 0 with nothing selected, easing to 1 when a piece is.
  final double focus;

  @override
  void paint(Canvas canvas, Size size) {
    final middle = size.height / 2;
    for (final (i, (left, right)) in pieces.indexed) {
      final picked = i == selected;
      final half = 5 + (picked ? 6 * focus : 0);
      final color = picked || selected == null
          ? slices[i].color
          : slices[i].color.withValues(alpha: 1 - 0.7 * focus);
      canvas.drawRRect(
        RRect.fromLTRBR(
          left,
          middle - half,
          right,
          middle + half,
          const Radius.circular(3),
        ),
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_StripPainter old) =>
      old.selected != selected || old.focus != focus || old.pieces != pieces;
}

class _Detail extends StatelessWidget {
  const _Detail({
    super.key,
    required this.slice,
    required this.total,
    required this.last,
  });

  final CategorySlice slice;
  final int total;
  final int? last;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: Palette.muted);
    final share = (slice.amount * 100 / total).round();
    final before = last;
    final compared = before == null || before == 0
        ? '上月沒有'
        : '上月 ${groupDigits(before)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(slice.name, style: text.titleSmall),
            const SizedBox(width: 8),
            Text('$share%', style: muted),
            const Spacer(),
            Text(groupDigits(slice.amount), style: text.titleMedium),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          [
            for (final child in slice.children)
              '${child.name} ${groupDigits(child.amount)}',
          ].join('・'),
          style: muted,
        ),
        const SizedBox(height: 2),
        Text(compared, style: muted),
      ],
    );
  }
}
