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
    this.gateway,
  });

  final InvestmentInstrument instrument;
  final bool showAmounts;

  /// Null means authoritative holdings have not been loaded, not zero shares.
  final PublicId? investmentAccountId;
  final List<InvestmentHoldingLot>? openLots;
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
    var invalidHoldings = false;
    if (widget.showAmounts &&
        result?.state == MarketState.available &&
        result?.value != null &&
        widget.openLots != null &&
        widget.investmentAccountId != null) {
      try {
        valuation = InvestmentPerformance.calculate(
          investmentAccountId: widget.investmentAccountId!,
          instrumentId: widget.instrument.id,
          currency: widget.instrument.tradingCurrency,
          openLots: widget.openLots!,
          realizedResults: const [],
          netDividends: const [],
          usablePrice: ShareUnitPrice.parse(
            widget.instrument.tradingCurrency,
            result!.value!.decimalPrice,
          ),
        );
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
            if (valuation != null) ...[
              Text(
                '目前持股估值 ${valuation.marketValue!.majorText} ${widget.instrument.tradingCurrency.code} · 剩餘成本 ${valuation.remainingCost.majorText}',
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
