import 'dart:math';

import 'package:flutter/material.dart';

import '../look/figures.dart';
import '../look/paint.dart';
import '../look/theme.dart';

/// An account's balance over recent weeks: each bar rises or falls by the
/// week's net change from where the last one ended, finishing on today's
/// balance. The chosen week's change sits above its bar.
class Waterfall extends StatelessWidget {
  const Waterfall({
    super.key,
    required this.weeks,
    required this.balance,
    required this.selected,
    required this.onSelect,
    this.currency = 'TWD',
  });

  /// Each week's Monday and net change, oldest first.
  final List<(DateTime, int)> weeks;

  /// The balance after the last week.
  final int balance;
  final int selected;
  final ValueChanged<int> onSelect;

  /// The account's currency, which the changes are counted in.
  final String currency;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 120,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return GestureDetector(
            // Picking by position means nothing to a screen reader, which
            // reads the summary the page gives the chart.
            excludeFromSemantics: true,
            onTapDown: (d) {
              final index = (d.localPosition.dx / width * weeks.length).floor();
              if (index >= 0 && index < weeks.length) onSelect(index);
            },
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: 1),
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutCubic,
              builder: (context, grow, _) => CustomPaint(
                size: Size.infinite,
                painter: _WaterfallPainter(
                  weeks: weeks,
                  balance: balance,
                  selected: selected,
                  grow: grow,
                  currency: currency,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _WaterfallPainter extends CustomPainter {
  _WaterfallPainter({
    required this.weeks,
    required this.balance,
    required this.selected,
    required this.grow,
    required this.currency,
  });

  final List<(DateTime, int)> weeks;
  final int balance;
  final int selected;
  final double grow;
  final String currency;

  @override
  void paint(Canvas canvas, Size size) {
    if (weeks.isEmpty) return;
    const top = 22.0;
    final bottom = size.height - 22;
    var level = balance - weeks.fold<int>(0, (sum, w) => sum + w.$2);
    final levels = <int>[level];
    for (final (_, change) in weeks) {
      level += change;
      levels.add(level);
    }
    final low = min(0, levels.reduce(min));
    final high = max(0, levels.reduce(max));
    final span = max(1, high - low);
    double y(num v) => bottom - (bottom - top) * (v - low) / span;

    final slot = size.width / weeks.length;
    final bar = min(36.0, slot * 0.46);
    final connector = Paint()
      ..color = Hue.faint
      ..strokeWidth = 1;
    for (final (i, (monday, change)) in weeks.indexed) {
      final centre = slot * (i + 0.5);
      final from = y(levels[i]);
      final to = from + (y(levels[i + 1]) - from) * grow;
      final picked = i == selected;
      final color = change > 0
          ? Hue.positive
          : change < 0
          ? Hue.negative
          : Hue.muted;
      final rect = Rect.fromLTRB(
        centre - bar / 2,
        min(from, to),
        centre + bar / 2,
        max(max(from, to), min(from, to) + 2),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        Paint()
          ..color = picked || selected < 0
              ? color
              : color.withValues(alpha: 0.5),
      );
      if (i < weeks.length - 1) {
        canvas.drawLine(
          Offset(centre + bar / 2, to),
          Offset(centre + slot - bar / 2, to),
          connector,
        );
      }
      final label = '${monday.month}/${monday.day}';
      paintText(
        canvas,
        label,
        TextStyle(
          fontSize: 11,
          color: picked ? Hue.ink : Hue.muted,
          fontWeight: picked ? FontWeight.w700 : FontWeight.w400,
        ),
        Offset(centre, size.height - 6),
        anchor: const Offset(0.5, 1),
      );
      if (picked) {
        canvas.drawLine(
          Offset(centre - 10, size.height - 1),
          Offset(centre + 10, size.height - 1),
          Paint()
            ..color = Hue.ink
            ..strokeWidth = 2,
        );
        paintText(
          canvas,
          currency == 'TWD'
              ? signed(change)
              : '${change > 0 ? '+' : ''}${amountIn(change, currency)}',
          TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color),
          Offset(centre, rect.top - 4),
          anchor: const Offset(0.5, 1),
          maxWidth: slot - 4,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_WaterfallPainter old) =>
      old.selected != selected || old.grow != grow || old.weeks != weeks;
}
