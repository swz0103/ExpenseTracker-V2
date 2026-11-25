import 'package:domain/investments.dart' show HoldingStatus;
import 'package:flutter/material.dart';
import 'package:ledger_trade_costs/rules/instruments.dart' show isEtf;

import '../../../../design_system/display/amount.dart';
import '../../../../design_system/display/status.dart';
import '../../../core/design_system/glyphs.dart';
import '../../../core/design_system/theme.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/navigation/nav.dart';
import '../../../core/widgets/shown_amounts.dart';
import '../../../../design_system/display/date.dart';
import '../../../core/design_system/shape.dart';
import '../../../core/design_system/spacing.dart';
import '../../../core/formatting/words.dart';
import '../../../core/platform/sync_job.dart';
import '../model/returns.dart';
import 'investments_hero.dart';
import 'investments_returns.dart';

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
        // Sold-out stocks are listed apart and not counted as holdings.
        for (final (name, group) in [
          (
            '個股',
            [
              for (final h in holdings.held)
                if (!isEtf(h.code)) h,
            ],
          ),
          (
            'ETF',
            [
              for (final h in holdings.held)
                if (isEtf(h.code)) h,
            ],
          ),
          (holdingLook(HoldingStatus.soldOut).words, holdings.soldOut),
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
                '$name · ${countOf(group.length, CountUnit.stocks)}',
                style: const TextStyle(
                  fontSize: TextSize.small,
                  fontWeight: FontWeight.w800,
                  color: AppColors.muted,
                ),
              ),
            ),
            QuoteBoard([
              for (final h in group..sort((a, b) => b.value.compareTo(a.value)))
                HoldingRow(
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
          color: AppColors.group,
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
      InvestReturns(ledger: ledger),
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
            InvestHero(ledger: ledger),
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
String yearlyRate(double rate) => ratioPercent(rate);

/// The returns of [ledger] as the screens show them, from the parts the
/// model reads (docs/adr/0013-models-take-what-they-use.md): one kept by
/// the ledger for the day until the entries or the market change, so
/// every page and rebuild reads what it worked out (review 32 1.1).
Returns returnsOf(Ledger ledger) {
  final today = ledger.today;
  return ledger.remember(
    ('returns', today),
    () => Returns(
      entries: ledger.entries,
      holdings: ledger.holdings,
      trades: ledger.entryQueryService,
      today: today,
    ),
    // The holdings rest on the entries and on the market.
    reads: const {Topic.entries, Topic.market},
  );
}
