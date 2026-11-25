import 'dart:math';

import 'package:flutter/material.dart';

import '../../../../design_system/display/amount.dart';
import '../../../core/design_system/glyphs.dart';
import '../../../core/design_system/paint.dart';
import '../../../core/design_system/theme.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/widgets/shown_amounts.dart';
import '../../../core/design_system/shape.dart';
import '../../../core/design_system/spacing.dart';
import '../model/dividend_outlook.dart';
import 'investments.dart';

/// 預計配息: the next twelve months as bars, each stacked by holding, the
/// monthly average dashed across; a tap on a month lists what it holds.
/// Guessed from the past year's dividends and the shares held now.
class InvestReturns extends StatefulWidget {
  const InvestReturns({super.key, required this.ledger});

  final Ledger ledger;

  @override
  State<InvestReturns> createState() => _ReturnsState();
}

class _ReturnsState extends State<InvestReturns> {
  int? _picked;

  /// Holdings' colours in the stacks, by how much each pays.
  static const _colors = [
    Palette.indigo,
    Palette.green,
    Palette.orange,
    Palette.blue,
    Palette.rose,
    Palette.olive,
  ];

  /// The months under the bars, the picked one bold.
  Widget _monthLabels(List<DateTime> months, int picked) => Row(
    children: [
      for (final (k, m) in months.indexed)
        // A twelfth of the width: two digits shrink a little with
        // the phone's largest text rather than wrap.
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '${m.month}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: TextSize.caption,
                fontWeight: k == picked ? FontWeight.w800 : null,
                color: k == picked ? AppColors.ink : AppColors.muted,
              ),
            ),
          ),
        ),
    ],
  );

  /// The stacked bars, a tap picking the month under it.
  Widget _chart(
    DividendOutlook outlook,
    Map<String, Color> colour,
    int picked,
  ) => Semantics(
    label: '預計配息長條圖，點一個月份看那個月',
    child: LayoutBuilder(
      builder: (context, box) => GestureDetector(
        onTapDown: (d) => setState(
          () => _picked = (d.localPosition.dx / box.maxWidth * 12)
              .floor()
              .clamp(0, 11),
        ),
        child: CustomPaint(
          size: Size(box.maxWidth, 170),
          painter: _StackPainter(
            stacks: [
              for (final m in outlook.byMonth)
                [
                  for (final code in outlook.order)
                    if (m[code] case final v?) (v, colour[code]!),
                ],
            ],
            sums: outlook.sums,
            average: outlook.total / 12,
            picked: picked,
            hidden: widget.ledger.amounts.hidden,
            words: AppColors.muted,
            rule: AppColors.line,
            band: tintOf(Palette.gold, 0.18),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final ledger = widget.ledger;
    final guesses = returnsOf(ledger).expectedDividends();
    if (guesses.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: Space.s4),
        child: EmptyState(
          glyph: Glyph.dividend,
          color: Palette.gold,
          message: '記下領到的股息後，這裡會推估接下來 12 個月的配息',
        ),
      );
    }
    final outlook = DividendOutlook.of(guesses, ledger.today);
    final months = outlook.months;
    final colour = {
      for (final (i, code) in outlook.order.indexed)
        code: _colors[i % _colors.length],
    };
    final first = outlook.first;
    final picked = _picked ?? first;
    final average = outlook.total / 12;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: Space.s4),
        _ReturnsHeading(ledger: ledger, outlook: outlook),
        const SizedBox(height: Space.s2),
        _chart(outlook, colour, picked),
        const SizedBox(height: Space.s1),
        _monthLabels(months, picked),
        const SizedBox(height: Space.s2),
        Wrap(
          spacing: 14,
          children: [
            Text(
              '- - - 每月平均 ${ledger.orDots(groupDigits(average.round()))}',
              style: mutedSmall,
            ),
            if (first >= 0)
              Text('${months[first].month} 月是下一次', style: mutedSmall),
          ],
        ),
        if (picked >= 0 && outlook.sums[picked] > 0) ...[
          const SizedBox(height: Space.s2),
          _MonthChips(
            ledger: ledger,
            outlook: outlook,
            colour: colour,
            month: picked,
          ),
        ],
        const Padding(
          padding: EdgeInsets.only(top: Space.s3, left: Space.half),
          child: Text('依去年同月的配息推估，實際以公司公告為準', style: mutedSmall),
        ),
      ],
    );
  }
}

/// 預計配息's heading: the months it covers on the left, 合計約 the twelve
/// months' total on the right.
class _ReturnsHeading extends StatelessWidget {
  const _ReturnsHeading({required this.ledger, required this.outlook});

  final Ledger ledger;
  final DividendOutlook outlook;

  @override
  Widget build(BuildContext context) {
    final months = outlook.months;
    final last = months.last;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '預計配息',
                style: TextStyle(
                  fontSize: TextSize.heading,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                '${months.first.month} 月 – '
                '${last.year == ledger.today.year ? '' : '明年 '}${last.month} 月',
                style: mutedSmall,
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Text('合計約', style: mutedSmall),
            Text(
              ledger.orDots(groupDigits(outlook.total)),
              style: TextStyle(
                fontSize: TextSize.large,
                fontWeight: FontWeight.w800,
                color: deepOf(Palette.gold),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The picked month's chips: its total, then what each holding pays in it.
class _MonthChips extends StatelessWidget {
  const _MonthChips({
    required this.ledger,
    required this.outlook,
    required this.colour,
    required this.month,
  });

  final Ledger ledger;
  final DividendOutlook outlook;

  /// Each holding's colour in the stacks, by its code.
  final Map<String, Color> colour;

  /// Which of the twelve months, from 0.
  final int month;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      _Chip(
        '${outlook.months[month].month} 月 · 約 '
        '${ledger.orDots(groupDigits(outlook.sums[month]))}',
        bold: true,
      ),
      for (final code in outlook.order)
        if (outlook.byMonth[month][code] case final v?)
          _Chip(
            '${outlook.names[code]}  ${ledger.orDots(groupDigits(v))}',
            color: colour[code],
          ),
    ],
  );
}

/// A grey pill with words, and a square of [color] before them.
class _Chip extends StatelessWidget {
  const _Chip(this.label, {this.color, this.bold = false});

  final String label;
  final Color? color;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final mark = color;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.s3,
        vertical: Space.s2,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.medium),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (mark != null) ...[
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: mark,
                borderRadius: BorderRadius.circular(Radii.extraSmall),
              ),
            ),
            const SizedBox(width: Space.s2),
          ],
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: TextSize.body,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Twelve stacked bars with their sums above, a dot for an empty month,
/// the picked month on a band, and the average dashed across.
class _StackPainter extends CustomPainter {
  _StackPainter({
    required this.stacks,
    required this.sums,
    required this.average,
    required this.picked,
    required this.hidden,
    required this.words,
    required this.rule,
    required this.band,
  });

  final List<List<(int, Color)>> stacks;
  final List<int> sums;
  final double average;
  final int picked;
  final bool hidden;
  final Color words;
  final Color rule;
  final Color band;

  static String _short(int v) => countTick(v);

  @override
  void paint(Canvas canvas, Size size) {
    final column = size.width / stacks.length;
    final bar = min(column * 0.62, 26.0);
    // Room above the tallest bar for its sum, inside the band.
    final top = 20.0;
    final high = sums.fold(1, max);
    double h(int v) => v / high * (size.height - top);
    if (picked >= 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(picked * column + 2, 0, column - 4, size.height),
          const Radius.circular(Radii.small),
        ),
        Paint()..color = band,
      );
    }
    for (final (k, stack) in stacks.indexed) {
      final cx = k * column + column / 2;
      if (stack.isEmpty) {
        canvas.drawCircle(
          Offset(cx, size.height - 3),
          2.5,
          Paint()..color = rule,
        );
        continue;
      }
      var y = size.height;
      for (final (i, (value, color)) in stack.indexed) {
        final height = max(h(value), 3.0);
        final rect = Rect.fromLTWH(cx - bar / 2, y - height, bar, height);
        final last = i == stack.length - 1;
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            rect,
            topLeft: last ? const Radius.circular(Radii.small) : Radius.zero,
            topRight: last ? const Radius.circular(Radii.small) : Radius.zero,
            bottomLeft: i == 0
                ? const Radius.circular(Radii.small)
                : Radius.zero,
            bottomRight: i == 0
                ? const Radius.circular(Radii.small)
                : Radius.zero,
          ),
          Paint()..color = color,
        );
        y -= height + 1.5;
      }
      if (!hidden) {
        // Inside its own column, the chosen one's band included: a long
        // sum such as 12.5k is set smaller rather than run over the edge.
        TextStyle style(double size) => TextStyle(
          fontSize: size,
          fontWeight: FontWeight.w700,
          color: words,
        );
        var text = layoutText(_short(sums[k]), style(TextSize.tiny));
        final room = column - 6;
        if (text.width > room) {
          text = layoutText(
            _short(sums[k]),
            style(TextSize.tiny * room / text.width),
          );
        }
        final ty = max(2.0, y - text.height - 2);
        text.paint(canvas, Offset(cx - text.width / 2, ty));
      }
    }
    final ay = size.height - h(average.round());
    final dash = Paint()
      ..color = words
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 8) {
      canvas.drawLine(Offset(x, ay), Offset(min(x + 4, size.width), ay), dash);
    }
  }

  @override
  bool shouldRepaint(_StackPainter old) =>
      old.picked != picked || old.sums != sums || old.hidden != hidden;
}
