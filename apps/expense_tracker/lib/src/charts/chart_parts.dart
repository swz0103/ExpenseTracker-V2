import 'package:flutter/material.dart';

import 'chart_data.dart';

/// Lays out one line of [text] for painting on a canvas.
TextPainter layoutText(String text, TextStyle style, {double? maxWidth}) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    maxLines: 1,
    ellipsis: '…',
  );
  painter.layout(maxWidth: maxWidth ?? double.infinity);
  return painter;
}

/// Paints [text] so that its [anchor] point lands on [at]: (0, 0) is the
/// top left of the text, (0.5, 0.5) its centre.
void paintText(
  Canvas canvas,
  String text,
  TextStyle style,
  Offset at, {
  Offset anchor = const Offset(0.5, 0.5),
  double? maxWidth,
}) {
  final painter = layoutText(text, style, maxWidth: maxWidth);
  final size = painter.size;
  final corner = Offset(size.width * anchor.dx, size.height * anchor.dy);
  painter.paint(canvas, at - corner);
  painter.dispose();
}

/// A labelled amount, such as 「支出 12,345」.
class AmountFigure extends StatelessWidget {
  const AmountFigure(this.label, this.amount, this.color, {super.key});

  final String label;
  final int amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: text.labelMedium),
        Text(
          groupDigits(amount),
          style: text.titleMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// One category with its share of [total] as a bar.
class CategoryRow extends StatelessWidget {
  const CategoryRow(
    this.slice,
    this.total, {
    super.key,
    this.selected = false,
    this.onTap,
  });

  final CategorySlice slice;
  final int total;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final share = total == 0 ? 0.0 : slice.amount / total;
    final percent = '${(share * 100).toStringAsFixed(1)}%';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? slice.color.withValues(alpha: 0.12) : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: slice.color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(slice.name)),
                Text(percent, style: theme.textTheme.labelMedium),
                const SizedBox(width: 12),
                SizedBox(
                  width: 72,
                  child: Text(
                    groupDigits(slice.amount),
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: share,
                minHeight: 6,
                color: slice.color,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 「‹ 2026年10月 ›」 for stepping through [months].
class MonthStepper extends StatelessWidget {
  const MonthStepper({
    super.key,
    required this.months,
    required this.index,
    required this.onChanged,
    this.suffix = '',
  });

  final List<MonthPoint> months;
  final int index;
  final ValueChanged<int> onChanged;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    final month = months[index];
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          tooltip: '上個月',
          onPressed: index > 0 ? () => onChanged(index - 1) : null,
          icon: const Icon(Icons.chevron_left),
        ),
        Text(
          '${month.year}年${month.month}月$suffix',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        IconButton(
          tooltip: '下個月',
          onPressed: index < months.length - 1
              ? () => onChanged(index + 1)
              : null,
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }
}
