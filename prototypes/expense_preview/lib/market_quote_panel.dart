import 'dart:async';

import 'package:flutter/material.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:investments/investments.dart';
import 'package:market_data/market_data.dart';

import 'price_alert_service.dart';

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
    this.latestPositionDate,
    this.gateway,
    this.router,
    this.priceAlerts,
    this.priceAlertNotifications,
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

  /// A split has no cash flow but a pre-split close cannot mark post-split shares.
  final BusinessDate? latestPositionDate;
  final MarketDataGateway? gateway;
  final MarketDataRouter? router;
  final PriceAlertService? priceAlerts;
  final PriceAlertNotificationPresenter? priceAlertNotifications;

  @override
  State<MarketQuotePanel> createState() => _MarketQuotePanelState();
}

class _MarketQuotePanelState extends State<MarketQuotePanel> {
  late final MarketDataGateway _ownedGateway = MarketDataGateway();
  final _alertTarget = TextEditingController();
  MarketResult<StockClose>? _result;
  MarketProviderDescriptor? _provider;
  SavedPriceAlert? _savedAlert;
  PriceAlertDirection _alertDirection = PriceAlertDirection.atOrAbove;
  String? _alertMessage;
  bool _loading = false;
  bool _alertBusy = false;
  int _request = 0;
  int _alertRequest = 0;

  MarketDataGateway get _gateway => widget.gateway ?? _ownedGateway;

  @override
  void initState() {
    super.initState();
    unawaited(_loadAlert());
  }

  @override
  void didUpdateWidget(covariant MarketQuotePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.instrument.id != widget.instrument.id ||
        oldWidget.showAmounts != widget.showAmounts ||
        oldWidget.openLots != widget.openLots ||
        oldWidget.investmentAccountId != widget.investmentAccountId ||
        !identical(oldWidget.gateway, widget.gateway) ||
        !identical(oldWidget.router, widget.router)) {
      _request++;
      _result = null;
      _provider = null;
      _loading = false;
    }
    if (oldWidget.instrument.id != widget.instrument.id ||
        !identical(oldWidget.priceAlerts, widget.priceAlerts)) {
      _alertRequest++;
      _savedAlert = null;
      _alertTarget.clear();
      _alertDirection = PriceAlertDirection.atOrAbove;
      _alertMessage = null;
      _alertBusy = false;
      unawaited(_loadAlert());
    }
  }

  @override
  void dispose() {
    _request++;
    _alertRequest++;
    _alertTarget.dispose();
    super.dispose();
  }

  Future<void> _loadAlert() async {
    final service = widget.priceAlerts;
    if (service == null) return;
    final request = ++_alertRequest;
    try {
      final saved = await service.load(widget.instrument);
      if (!mounted || request != _alertRequest) return;
      setState(() {
        _savedAlert = saved;
        if (saved != null) {
          _alertTarget.text = saved.alert.target.toString();
          _alertDirection = saved.alert.direction;
        }
      });
    } catch (_) {
      if (!mounted || request != _alertRequest) return;
      setState(() => _alertMessage = '提醒設定無法讀取，請重新設定。');
    }
  }

  Future<void> _saveAlert() async {
    final service = widget.priceAlerts;
    if (service == null || _alertBusy) return;
    ShareUnitPrice target;
    try {
      target = ShareUnitPrice.parse(
        widget.instrument.tradingCurrency,
        _alertTarget.text,
      );
    } catch (_) {
      setState(() => _alertMessage = '請輸入大於 0 的有效價格。');
      return;
    }
    final request = ++_alertRequest;
    setState(() {
      _alertBusy = true;
      _alertMessage = null;
    });
    try {
      final saved = await service.save(
        instrument: widget.instrument,
        target: target,
        direction: _alertDirection,
      );
      if (!mounted || request != _alertRequest) return;
      setState(() {
        _savedAlert = saved;
        _alertBusy = false;
        _alertMessage = '提醒已儲存；下次取得新行情時開始判斷。';
      });
    } catch (_) {
      if (!mounted || request != _alertRequest) return;
      setState(() {
        _alertBusy = false;
        _alertMessage = '提醒設定無法儲存，請稍後重試。';
      });
    }
  }

  Future<void> _deleteAlert() async {
    final service = widget.priceAlerts;
    if (service == null || _alertBusy) return;
    final request = ++_alertRequest;
    setState(() {
      _alertBusy = true;
      _alertMessage = null;
    });
    try {
      await service.delete(widget.instrument);
      if (!mounted || request != _alertRequest) return;
      setState(() {
        _savedAlert = null;
        _alertTarget.clear();
        _alertBusy = false;
        _alertMessage = '提醒已移除。';
      });
    } catch (_) {
      if (!mounted || request != _alertRequest) return;
      setState(() {
        _alertBusy = false;
        _alertMessage = '提醒無法移除，請稍後重試。';
      });
    }
  }

  Future<void> _refresh() async {
    if (!widget.showAmounts || _loading) return;
    final request = ++_request;
    setState(() {
      _loading = true;
      _result = null;
      _provider = null;
    });
    final routed = widget.router == null
        ? null
        : await widget.router!.stockClose(widget.instrument);
    final result =
        routed?.result ?? await _gateway.stockClose(widget.instrument);
    if (!mounted || request != _request || !widget.showAmounts) return;
    PriceAlertNotification? notification;
    final alerts = widget.priceAlerts;
    if (alerts != null) {
      try {
        final evaluation = await alerts.evaluate(
          instrument: widget.instrument,
          result: result,
          providerId: routed?.selectedProvider?.id ?? StockClose.provider,
          now: UtcInstant(DateTime.now().toUtc()),
        );
        notification = evaluation?.notification;
        if (notification != null &&
            mounted &&
            request == _request &&
            widget.showAmounts) {
          await widget.priceAlertNotifications?.show(notification);
        }
      } catch (_) {
        // A failed optional reminder must never hide a successfully read quote.
      }
    }
    if (!mounted || request != _request || !widget.showAmounts) return;
    setState(() {
      _loading = false;
      _result = result;
      _provider = routed?.selectedProvider;
      if (notification != null) {
        _alertMessage =
            '到價提醒：${notification.symbol} 現在是 ${notification.price} ${notification.currency.code}。';
      }
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
            ((widget.latestPositionDate?.compareTo(quote.asOf) ?? 0) > 0 ||
                widget.historicalCashFlows.any(
                  (flow) => flow.date.compareTo(quote.asOf) > 0,
                ));
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
        const Text('依已註冊來源查詢每日收盤價；成交價仍以實際交易為準。'),
        OutlinedButton(
          key: const ValueKey('request-market-close'),
          onPressed: widget.showAmounts && !_loading ? _refresh : null,
          child: Text(_loading ? '查詢中…' : '查詢最新收盤價'),
        ),
        if (widget.showAmounts && widget.priceAlerts != null)
          ExpansionTile(
            key: const ValueKey('price-alert-section'),
            title: const Text('到價提醒'),
            subtitle: Text(
              _savedAlert == null
                  ? '尚未設定；取得新行情時檢查'
                  : '${_savedAlert!.alert.direction == PriceAlertDirection.atOrAbove ? '漲到' : '跌到'} ${_savedAlert!.alert.target} ${widget.instrument.tradingCurrency.code}',
            ),
            childrenPadding: const EdgeInsets.only(bottom: 12),
            children: [
              TextField(
                key: const ValueKey('price-alert-target'),
                controller: _alertTarget,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: '目標價格（${widget.instrument.tradingCurrency.code}）',
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<PriceAlertDirection>(
                key: const ValueKey('price-alert-direction'),
                initialValue: _alertDirection,
                decoration: const InputDecoration(labelText: '提醒條件'),
                items: const [
                  DropdownMenuItem(
                    value: PriceAlertDirection.atOrAbove,
                    child: Text('價格漲到或超過目標'),
                  ),
                  DropdownMenuItem(
                    value: PriceAlertDirection.atOrBelow,
                    child: Text('價格跌到或低於目標'),
                  ),
                ],
                onChanged: _alertBusy
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() => _alertDirection = value);
                        }
                      },
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton(
                    key: const ValueKey('save-price-alert'),
                    onPressed: _alertBusy ? null : _saveAlert,
                    child: Text(_alertBusy ? '處理中…' : '儲存提醒'),
                  ),
                  if (_savedAlert != null)
                    TextButton(
                      key: const ValueKey('delete-price-alert'),
                      onPressed: _alertBusy ? null : _deleteAlert,
                      child: const Text('移除提醒'),
                    ),
                ],
              ),
              const Text('App 取得新鮮行情並跨越門檻時提示；Android 會同時嘗試發出系統通知。'),
              if (_alertMessage != null)
                Text(
                  _alertMessage!,
                  key: const ValueKey('price-alert-message'),
                ),
            ],
          ),
        if (!widget.showAmounts) const Text('隱私模式已遮蔽行情金額。'),
        if (valuation != null && widget.showAmounts) ...[
          Text(
            '已實現損益 ${valuation.realizedResult.majorText} ${widget.instrument.tradingCurrency.code} · 現金股息淨額 ${valuation.netDividends.majorText}',
            key: const ValueKey('investment-factual-return'),
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
              '來源：${_provider?.label ?? '台灣證交所'} · 交易日 ${quote.asOf} · 取得 ${quote.fetchedAt.value.toLocal().toIso8601String()}',
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
              MarketState.missing => '目前來源沒有此標的收盤價。',
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
