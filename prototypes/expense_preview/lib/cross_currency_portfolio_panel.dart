import 'package:flutter/material.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:investments/investments.dart';
import 'package:market_data/market_data.dart';

import 'privacy_presentation.dart';

final class CrossCurrencyPortfolioRead {
  const CrossCurrencyPortfolioRead({
    required this.summary,
    required this.routes,
  });

  final CrossCurrencyInvestmentSummary summary;
  final Map<Currency, RoutedMarketResult<ReferenceRate>> routes;
}

abstract interface class CrossCurrencyPortfolioController {
  List<Currency> get reportingCurrencies;

  Future<CrossCurrencyPortfolioRead> load({
    required Currency reportingCurrency,
    required bool allowEarlier,
  });
}

final class RoutedCrossCurrencyPortfolioController
    implements CrossCurrencyPortfolioController {
  RoutedCrossCurrencyPortfolioController({
    required this.original,
    required this.router,
    required this.valuationDate,
    required Iterable<Currency> reportingCurrencies,
    this.policy = const MarketRoutingPolicy.automatic(),
  }) : reportingCurrencies = List.unmodifiable(reportingCurrencies) {
    if (this.reportingCurrencies.isEmpty ||
        this.reportingCurrencies.toSet().length !=
            this.reportingCurrencies.length) {
      throw ArgumentError('Reporting currencies must be unique and nonempty');
    }
  }

  final InvestmentPortfolioSummary original;
  final MarketDataRouter router;
  final BusinessDate valuationDate;
  @override
  final List<Currency> reportingCurrencies;
  final MarketRoutingPolicy policy;

  @override
  Future<CrossCurrencyPortfolioRead> load({
    required Currency reportingCurrency,
    required bool allowEarlier,
  }) async {
    if (!reportingCurrencies.contains(reportingCurrency)) {
      throw ArgumentError('Unsupported reporting currency');
    }
    final observations = <PortfolioFxInput>[];
    final routes = <Currency, RoutedMarketResult<ReferenceRate>>{};
    for (final currency in original.byCurrency.keys) {
      if (currency == reportingCurrency) continue;
      final routed = allowEarlier
          ? await router.historicalFxRate(
              currency,
              reportingCurrency,
              date: valuationDate,
              policy: policy,
            )
          : await router.fxRate(
              currency,
              reportingCurrency,
              requiredAsOf: valuationDate,
              policy: policy,
            );
      routes[currency] = routed;
      final value = routed.result.value;
      if (value != null &&
          (routed.result.state == MarketState.available ||
              (allowEarlier && routed.result.state == MarketState.stale))) {
        observations.add(
          PortfolioFxInput(
            observation: value.observation,
            derivedInverse: value.derivedInverse,
          ),
        );
      }
    }
    return CrossCurrencyPortfolioRead(
      summary: CrossCurrencyInvestmentSummary.convert(
        original: original,
        reportingCurrency: reportingCurrency,
        valuationDate: valuationDate,
        observations: observations,
        allowEarlier: allowEarlier,
      ),
      routes: Map.unmodifiable(routes),
    );
  }
}

final class CrossCurrencyPortfolioPanel extends StatefulWidget {
  const CrossCurrencyPortfolioPanel({
    required this.controller,
    required this.privacy,
    super.key,
  });

  final CrossCurrencyPortfolioController controller;
  final PrivacyMode privacy;

  @override
  State<CrossCurrencyPortfolioPanel> createState() =>
      _CrossCurrencyPortfolioPanelState();
}

final class _CrossCurrencyPortfolioPanelState
    extends State<CrossCurrencyPortfolioPanel> {
  late Currency _reportingCurrency =
      widget.controller.reportingCurrencies.first;
  bool _allowEarlier = false;
  bool _busy = false;
  CrossCurrencyPortfolioRead? _read;
  String? _error;
  var _request = 0;

  @override
  void didUpdateWidget(covariant CrossCurrencyPortfolioPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller) ||
        oldWidget.privacy != widget.privacy) {
      _request++;
      _read = null;
      _error = null;
      _busy = false;
      if (!widget.controller.reportingCurrencies.contains(_reportingCurrency)) {
        _reportingCurrency = widget.controller.reportingCurrencies.first;
      }
    }
  }

  Future<void> _load() async {
    if (_busy || widget.privacy != PrivacyMode.visible) return;
    final request = ++_request;
    setState(() {
      _busy = true;
      _read = null;
      _error = null;
    });
    try {
      final read = await widget.controller.load(
        reportingCurrency: _reportingCurrency,
        allowEarlier: _allowEarlier,
      );
      if (!mounted || request != _request) return;
      setState(() {
        _read = read;
        _busy = false;
      });
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() {
        _busy = false;
        _error = '無法完整核對跨幣摘要；不顯示部分總額。';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.privacy != PrivacyMode.visible) {
      return const Text('跨幣別投資摘要已隱藏。');
    }
    final summary = _read?.summary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<Currency>(
          key: const ValueKey('cross-currency-reporting-currency'),
          initialValue: _reportingCurrency,
          decoration: const InputDecoration(labelText: '報表幣別'),
          items: [
            for (final currency in widget.controller.reportingCurrencies)
              DropdownMenuItem(value: currency, child: Text(currency.code)),
          ],
          onChanged: _busy
              ? null
              : (value) {
                  if (value != null) {
                    setState(() {
                      _reportingCurrency = value;
                      _read = null;
                    });
                  }
                },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('允許使用七日內較早的實際匯率'),
          subtitle: const Text('較早值會保留原觀測日並標示，不會冒充指定日期。'),
          value: _allowEarlier,
          onChanged: _busy
              ? null
              : (value) => setState(() {
                  _allowEarlier = value;
                  _read = null;
                }),
        ),
        FilledButton(
          key: const ValueKey('load-cross-currency-summary'),
          onPressed: _busy ? null : _load,
          child: Text(_busy ? '核對中…' : '產生跨幣摘要'),
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null)
          Text(_error!, key: const ValueKey('cross-currency-error')),
        if (summary != null) ...[
          const Divider(),
          Text(
            summary.hasCompleteFx ? '匯率資料完整' : '跨幣總額不可用：至少一個幣別缺少可用匯率。',
            key: const ValueKey('cross-currency-status'),
          ),
          if (summary.remainingCost != null) ...[
            Text('合計剩餘成本 ${_money(summary.remainingCost!)}'),
            Text('合計已實現 ${_money(summary.realizedResult!)}'),
            Text('合計淨股息 ${_money(summary.netDividends!)}'),
          ],
          if (summary.hasCompleteValuation) ...[
            Text('合計參考市值 ${_money(summary.marketValue!)}'),
            Text('合計未實現 ${_money(summary.unrealizedResult!)}'),
            Text('合計總報酬 ${_money(summary.totalReturn!)}'),
          ] else if (summary.hasCompleteFx)
            const Text('至少一個原幣持倉缺價格；不顯示跨幣市值、未實現或總報酬。'),
          for (final entry in summary.rows.entries)
            _row(entry.key, entry.value, _read!.routes[entry.key]),
        ],
        const Text('換算只供報表參考；原幣帳本、成交與現金不會被改寫。'),
      ],
    );
  }

  String _money(Money value) => '${value.currency.code} ${value.majorText}';

  Widget _row(
    Currency currency,
    ConvertedInvestmentCurrencySummary row,
    RoutedMarketResult<ReferenceRate>? routed,
  ) {
    final observation = row.observation;
    final provider = routed?.selectedProvider;
    final state = switch (row.state) {
      PortfolioFxState.identity => '同幣別，不需換算',
      PortfolioFxState.exact => '指定日匯率',
      PortfolioFxState.earlier => '較早匯率',
      PortfolioFxState.missing => '缺少可用匯率',
    };
    return Card(
      key: ValueKey('cross-currency-row-${currency.code}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${currency.code} → ${_reportingCurrency.code}：$state'),
            if (row.remainingCost != null)
              Text('換算成本 ${_money(row.remainingCost!)}'),
            if (provider != null) Text('實際來源：${provider.label}'),
            if (observation != null) ...[
              Text('Provider ID：${observation.source}'),
              Text('觀測日：${observation.asOf}'),
              if (row.derivedInverse) const Text('衍生方式：使用來源匯率的反向值'),
            ],
            if (routed != null && routed.result.reason != null)
              Text('來源狀態：${routed.result.reason}'),
          ],
        ),
      ),
    );
  }
}
