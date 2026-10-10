import 'dart:math';

import 'package:flutter/material.dart';

import '../look/paint.dart';
import '../look/theme.dart';

/// Spending against a limit as one bar: a coloured piece per category,
/// the rest of the limit left pale, an arrow at the share used, and a
/// dashed line at [pace], how much of the month has gone by, so spending
/// ahead of time shows at a glance. Tap a piece to choose it.
class BudgetBar extends StatelessWidget {
  const BudgetBar({
    super.key,
    required this.pieces,
    required this.limit,
    this.selected,
    this.onSelect,
    this.pace,
    this.height = 26,
  });

  final List<(Color, int)> pieces;
  final int limit;
  final int? selected;
  final ValueChanged<int?>? onSelect;

  /// The share of the month gone by, 0 to 1.
  final double? pace;
  final double height;

  int get _used => pieces.fold(0, (sum, p) => sum + p.$2);

  @override
  Widget build(BuildContext context) {
    final pick = onSelect;
    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return GestureDetector(
            onTapDown: pick == null
                ? null
                : (details) {
                    final span = max(limit, _used).toDouble();
                    var left = 0.0;
                    for (final (i, (_, amount)) in pieces.indexed) {
                      final right = left + width * amount / span;
                      final x = details.localPosition.dx;
                      if (x >= left && x <= right) {
                        pick(i == selected ? null : i);
                        return;
                      }
                      left = right;
                    }
                    pick(null);
                  },
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: 1),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
              builder: (context, grow, _) => CustomPaint(
                size: Size(width, height + 34),
                painter: _BudgetPainter(
                  pieces: pieces,
                  limit: limit,
                  selected: selected,
                  grow: grow,
                  height: height,
                  pace: pace,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _BudgetPainter extends CustomPainter {
  _BudgetPainter({
    required this.pieces,
    required this.limit,
    required this.selected,
    required this.grow,
    required this.height,
    required this.pace,
  });

  final List<(Color, int)> pieces;
  final int limit;
  final int? selected;
  final double grow;
  final double height;
  final double? pace;

  @override
  void paint(Canvas canvas, Size size) {
    final used = pieces.fold(0, (sum, p) => sum + p.$2);
    final span = max(1, max(limit, used)).toDouble();
    final bar = RRect.fromLTRBR(
      0,
      0,
      size.width,
      height,
      const Radius.circular(7),
    );
    canvas.save();
    canvas.clipRRect(bar);
    canvas.drawRect(
      Offset.zero & Size(size.width, height),
      Paint()..color = const Color(0xFFE6E0D2),
    );
    var left = 0.0;
    for (final (i, (color, amount)) in pieces.indexed) {
      final width = size.width * amount / span * grow;
      final faded = selected != null && selected != i;
      canvas.drawRect(
        Rect.fromLTWH(left, 0, width, height),
        Paint()..color = faded ? color.withValues(alpha: 0.35) : color,
      );
      left += width;
    }
    final time = pace;
    if (time != null && limit > 0) {
      final x = size.width * min(1.0, time) * limit / span;
      final dash = Paint()
        ..color = Hue.ink.withValues(alpha: 0.7)
        ..strokeWidth = 1.5;
      for (var y = 2.0; y < height - 2; y += 5) {
        canvas.drawLine(Offset(x, y), Offset(x, min(y + 2.5, height)), dash);
      }
    }
    canvas.restore();

    const small = TextStyle(fontSize: 11, color: Hue.muted);
    if (time != null) {
      paintText(
        canvas,
        '｜時間 ${(min(1.0, time) * 100).round()}%',
        small,
        Offset(size.width, height + 6),
        anchor: const Offset(1, 0),
      );
    }
    if (limit <= 0) return;
    final share = used / limit;
    final x = (size.width * min(1.0, share) * grow).clamp(6.0, size.width - 6);
    final arrow = Path()
      ..moveTo(x, height + 4)
      ..lineTo(x - 5, height + 11)
      ..lineTo(x + 5, height + 11)
      ..close();
    final over = share > 1;
    canvas.drawPath(arrow, Paint()..color = over ? Hue.negative : Hue.ink);
    paintText(
      canvas,
      '${(share * 100).round()}%',
      TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: over ? Hue.negative : Hue.positive,
      ),
      Offset(x, height + 13),
      anchor: const Offset(0.5, 0),
    );
  }

  @override
  bool shouldRepaint(_BudgetPainter old) =>
      old.selected != selected ||
      old.grow != grow ||
      old.pieces != pieces ||
      old.pace != pace;
}
