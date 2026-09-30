import 'package:flutter/material.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:investments/investments.dart';
import 'package:market_data/market_data.dart';

/// User-requested reference price. It never changes an executed trade,
/// account balance, or lot cost. The provider and observation date stay visible.
class MarketQuotePanel extends StatefulWidget {
  const MarketQuotePanel({
    super.key,
    required this.instrument,
    required this.showAmounts,
    this.investmentAccountId,
    this.openLots,
    this.realizedResults = const [],
    this.netDividends = const [],
    this.historicalCashFlows = const [],
    this.gateway,
  });

  final InvestmentInstrument instrument;
  final bool showAmounts;

  /// Null means authoritative holdings have not been loaded, not zero shares.
  final PublicId? investmentAccountId;
  final List<InvestmentHoldingLot>? openLots;

  /// Committed financial facts for this account and instrument only.
  final List<Money> realizedResults;
  final List<Money> netDividends;
  final List<InvestmentCashFlow> historicalCashFlows;
  final MarketDataGateway? gateway;

  @override
  State<MarketQuotePanel> createState() => _MarketQuotePanelState();
}

class _MarketQuotePanelState extends State<MarketQuotePanel> {
  late final MarketDataGateway _ownedGateway = MarketDataGateway();
  MarketResult<StockClose>? _result;
  bool _loading = false;
  int _request = 0;

  MarketDataGateway get _gateway => widget.gateway ?? _ownedGateway;

  @override
  void didUpdateWidget(covariant MarketQuotePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.instrument.id != widget.instrument.id ||
        oldWidget.showAmounts != widget.showAmounts ||
        oldWidget.openLots != widget.openLots ||
        oldWidget.investmentAccountId != widget.investmentAccountId ||
        !identical(oldWidget.gateway, widget.gateway)) {
      _request++;
      _result = null;
      _loading = false;
    }
  }

  Future<void> _refresh() async {
    if (!widget.showAmounts || _loading) return;
    final request = ++_request;
    setState(() {
      _loading = true;
      _result = null;
    });
    final result = await _gateway.stockClose(widget.instrument);
    if (!mounted || request != _request || !widget.showAmounts) return;
    setState(() {
      _loading = false;
      _result = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    InvestmentPerformance? valuation;
    InvestmentXirrResult? xirr;
    var invalidHoldings = false;
    var quotePredatesTrade = false;
    if (widget.showAmounts &&
        widget.openLots != null &&
        widget.investmentAccountId != null) {
      try {
        final quote = result?.state == MarketState.available
            ? result?.value
            : null;
        quotePredatesTrade =
            quote != null &&
            widget.historicalCashFlows.any(
              (flow) => flow.date.compareTo(quote.asOf) > 0,
            );
        valuation = InvestmentPerformance.calculate(
          investmentAccountId: widget.investmentAccountId!,
          instrumentId: widget.instrument.id,
          currency: widget.instrument.tradingCurrency,
          openLots: widget.openLots!,
          realizedResults: widget.realizedResults,
          netDividends: widget.netDividends,
          usablePrice: quote == null || quotePredatesTrade
              ? null
              : ShareUnitPrice.parse(
                  widget.instrument.tradingCurrency,
                  quote.decimalPrice,
                ),
        );
        if (widget.historicalCashFlows.isNotEmpty &&
            (valuation.quantityUnits == BigInt.zero ||
                (valuation.marketValue != null && quote != null))) {
          xirr = calculateInvestmentXirr(
            currency: widget.instrument.tradingCurrency,
            flows: [
              ...widget.historicalCashFlows,
              if (valuation.quantityUnits > BigInt.zero)
                InvestmentCashFlow(quote!.asOf, valuation.marketValue!),
            ],
          );
        }
      } on InvestmentPerformanceException {
        invalidHoldings = true;
      } on MoneyException {
        invalidHoldings = true;
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('參考行情', style: Theme.of(context).textTheme.titleMedium),
        const Text('僅台灣證交所上市股票／ETF 每日收盤價；成交價仍以實際交易為準。'),
        OutlinedButton(
          key: const ValueKey('request-market-close'),
          onPressed: widget.showAmounts && !_loading ? _refresh : null,
          child: Text(_loading ? '查詢中…' : '查詢最新收盤價'),
        ),
        if (!widget.showAmounts) const Text('隱私模式已遮蔽行情金額。'),
        if (valuation != null && widget.showAmounts) ...[
          Text(
            '已實現損益 ${valuation.realizedResult.majorText} ${widget.instrument.tradingCurrency.code} · 現金股息淨額 ${valuation.netDividends.majorText}',
          ),
          if (valuation.totalReturn != null)
            Text(
              '總報酬 ${valuation.totalReturn!.majorText} ${widget.instrument.tradingCurrency.code}（含已實現與股息）',
              key: const ValueKey('market-total-return'),
            ),
          if (xirr case final result?)
            Text(switch (result.status) {
              InvestmentXirrStatus.available =>
                '年化報酬率約 ${(result.annualRate! * 100).toStringAsFixed(2)}%（XIRR，依實際現金流與參考收盤價）',
              InvestmentXirrStatus.multipleRoots => '年化報酬率有多個解，暫不顯示。',
              InvestmentXirrStatus.outsideSearchRange => '年化報酬率超出安全計算範圍。',
              InvestmentXirrStatus.nonConvergent => '年化報酬率未收斂。',
              InvestmentXirrStatus.noSolution => '現金流不足，無法計算年化報酬率。',
            }, key: const ValueKey('market-xirr')),
          if (valuation.quantityUnits > BigInt.zero &&
              valuation.marketValue == null)
            const Text('缺少可用的最新行情，暫不計算未實現損益、總報酬與年化報酬率。'),
          if (quotePredatesTrade) const Text('參考行情早於最新交易，暫不作為目前持股估值。'),
        ],
        if (widget.showAmounts && result != null) ...[
          if (result.value case final quote?) ...[
            Text(
              '來源：台灣證交所 · 交易日 ${quote.asOf} · 取得 ${quote.fetchedAt.value.toLocal().toIso8601String()}',
              key: const ValueKey('market-close-source'),
            ),
            if (result.state == MarketState.available)
              Text(
                '收盤價 ${quote.decimalPrice} ${widget.instrument.tradingCurrency.code}',
                key: const ValueKey('market-close-value'),
              )
            else
              Text(
                '資料已過期：${quote.decimalPrice} ${widget.instrument.tradingCurrency.code}；不可用於目前估值。',
                key: const ValueKey('market-close-stale'),
              ),
            if (valuation?.marketValue != null) ...[
              Text(
                '目前持股估值 ${valuation!.marketValue!.majorText} ${widget.instrument.tradingCurrency.code} · 剩餘成本 ${valuation.remainingCost.majorText}',
                key: const ValueKey('market-holding-value'),
              ),
              Text(
                '未實現損益 ${valuation.unrealizedResult!.majorText} ${widget.instrument.tradingCurrency.code}（僅依此收盤價；不含已實現與股息）',
                key: const ValueKey('market-unrealized'),
              ),
            ],
            if (invalidHoldings) const Text('持股資料未能核對，暫不顯示估值。'),
          ] else
            Text(switch (result.state) {
              MarketState.missing => '證交所目前沒有此標的收盤價。',
              MarketState.unsupported => '此市場、幣別或標的尚無行情來源。',
              MarketState.throttled => '行情查詢稍後再試。',
              MarketState.failed => '行情來源無法使用，請稍後重試。',
              MarketState.stale => '行情已過期，無法顯示目前估值。',
              MarketState.available => '行情資料不足。',
            }, key: const ValueKey('market-close-unavailable')),
        ],
      ],
    );
  }
}
