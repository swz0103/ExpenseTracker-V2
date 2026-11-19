import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/formatting/figures.dart';
import '../../../core/design_system/glyphs.dart';
import '../../../core/design_system/paint.dart';
import '../../../core/design_system/theme.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/navigation/nav.dart';
import '../model/returns.dart';
import '../../../core/widgets/shown_amounts.dart';
import '../../../core/formatting/dates.dart';
import '../../../core/design_system/shape.dart';
import '../../../core/design_system/spacing.dart';
import '../../../core/formatting/words.dart';
import '../../../core/platform/sync_job.dart';
import '../model/dividend_outlook.dart';

part 'investments_hero.dart';
part 'investments_returns.dart';

/// 投資與股息: unrealised and realised profit, dividends by month, and
/// each holding's profit as a bar on a shared scale.
class InvestmentsPage extends StatefulWidget {
  const InvestmentsPage({super.key, required this.ledger, required this.nav});

  final Ledger ledger;
  final Nav nav;

  @override
  State<InvestmentsPage> createState() => _InvestmentsPageState();
}

class _InvestmentsPageState extends State<InvestmentsPage> {
  /// Opens one holding's page.
  void _holding(String code) => widget.nav.open(AppRoutes.holding(code));

  /// 持股 or 股息.
  var _tab = 0;

  late final _month = (widget.ledger.today.year, widget.ledger.today.month);

  /// 持股: the holdings by kind, with the cost and when the closes came.
  /// 持股, its cost, and when the closes came or why they did not.
  Widget _holdingsHead(SyncJob? market) {
    final ledger = widget.ledger;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.s1, 0, Space.s1, Space.s2),
      child: Row(
        children: [
          const Text(
            '持股',
            style: TextStyle(
              fontSize: TextSize.heading,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: Space.s2),
          // The cost lives here rather than on the main card.
          Text(
            '成本 ${ledger.orDots(groupDigits(ledger.holdings.costBasis))}',
            style: mutedSmall,
          ),
          const SizedBox(width: Space.s2),
          Expanded(
            child: Text(
              switch ((market?.problem, ledger.marketData.quotedOn)) {
                (final problem?, _) => problem,
                (_, null) => '連上網路後更新收盤價',
                _ when market?.busy ?? false => '更新收盤價中…',
                (_, final d?) => '${formatMd(d)} 收盤 · 下拉更新',
              },
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: mutedSmall,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _holdingsTab(SyncJob? market) {
    final ledger = widget.ledger;
    final holdings = ledger.holdings;
    return [
      _holdingsHead(market),
      if (holdings.all.isEmpty)
        EmptyState(
          glyph: Glyph.pie,
          color: Palette.indigo,
          message: '還沒有持股',
          action: '記一筆買進',
          onAction: () => widget.nav.compose(type: EntryType.buy),
        )
      else
        for (final (name, group) in [
          (
            '個股',
            [
              for (final h in holdings.all)
                if (!h.code.startsWith('00')) h,
            ],
          ),
          (
            'ETF',
            [
              for (final h in holdings.all)
                if (h.code.startsWith('00')) h,
            ],
          ),
        ])
          if (group.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.s1,
                Space.s2,
                Space.s1,
                Space.s2,
              ),
              child: Text(
                '$name · ${group.length} 檔',
                style: const TextStyle(
                  fontSize: TextSize.small,
                  fontWeight: FontWeight.w800,
                  color: Hue.muted,
                ),
              ),
            ),
            QuoteBoard([
              for (final h in group..sort((a, b) => b.value.compareTo(a.value)))
                _HoldingRow(
                  ledger: ledger,
                  held: h,
                  onTap: () => _holding(h.code),
                ),
            ]),
            const SizedBox(height: Space.s2),
          ],
    ];
  }

  /// 股息: this month's and all the dividends, then what they return.
  List<Widget> _dividendsTab(int year, int month) {
    final ledger = widget.ledger;
    return [
      Container(
        padding: const EdgeInsets.fromLTRB(
          Space.s4,
          Space.s3,
          Space.s4,
          Space.s3,
        ),
        decoration: BoxDecoration(
          color: Hue.group,
          borderRadius: BorderRadius.circular(Radii.largeIncreased),
        ),
        child: Row(
          children: [
            const SquareIcon(Glyph.dividend, Palette.gold, size: 44),
            const SizedBox(width: Space.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$month 月領到', style: mutedSmall),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      ledger.orDots(
                        groupDigits(
                          ledger.reportService.dividends(year, month),
                        ),
                      ),
                      style: const TextStyle(
                        fontSize: TextSize.large,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Space.s2),
            // Long sums shrink to fit rather than run into each other.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('累計', style: mutedSmall),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      ledger.orDots(groupDigits(ledger.holdings.dividends)),
                      style: const TextStyle(
                        fontSize: TextSize.heading,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      _Returns(ledger: ledger),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final ledger = widget.ledger;
    final market = widget.nav.market;
    return ListenableBuilder(
      listenable: Listenable.merge([
        ledger.watch(const {Topic.entries, Topic.market}),
        ?market,
      ]),
      builder: (context, _) {
        final (year, month) = _month;
        final list = HeadedList(
          // Pulled down to fetch the closes again, even when empty.
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(Space.s5, 0, Space.s5, Space.s4),
          header: CenterHeader('投資與股息', onBack: widget.nav.back),
          children: [
            _InvestHero(ledger: ledger),
            const SizedBox(height: Space.s3),
            BigSegments(
              items: const [
                (Glyph.pie, '持股', Palette.indigo),
                (Glyph.dividend, Words.dividend, Palette.gold),
              ],
              selected: _tab,
              onChanged: (i) => setState(() => _tab = i),
            ),
            const SizedBox(height: Space.s4),
            if (_tab == 0)
              ..._holdingsTab(market)
            else
              ..._dividendsTab(year, month),
          ],
        );
        if (market == null) return list;
        return RefreshIndicator(
          onRefresh: () => market.refresh(force: true),
          child: list,
        );
      },
    );
  }
}

/// A rate as 「+8.4%」.
String yearlyRate(double rate) =>
    '${rate > 0 ? '+' : ''}${(rate * 100).toStringAsFixed(1)}%';

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
        color: Hue.surface,
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

  static String _short(int v) =>
      v >= 1000 ? '${(v / 1000).toStringAsFixed(1)}k' : '$v';

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
