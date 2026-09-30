import 'package:flutter/material.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:investments/investments.dart';
import 'package:ledger_generation_probe/ledger_store.dart';
import 'package:market_data/market_data.dart';

import 'preview_engine.dart';
import 'privacy_presentation.dart';

/// The App's read-only, committed investment-fact boundary. The interface also
/// lets narrow widget tests simulate one failed read without creating a vault.
abstract interface class InvestmentPortfolioSource {
  bool get isUnlocked;
  bool get supportsSales;
  bool get supportsDividends;
  bool get supportsSplits;
  Future<List<InvestmentBuyFact>> buys();
  Future<List<InvestmentHoldingLot>> openLots(
    PublicId account,
    PublicId instrument,
  );
  Future<List<InvestmentSellFact>> sales(PublicId account, PublicId instrument);
  Future<List<InvestmentDividendFact>> dividends(PublicId account);
  Future<List<InvestmentSplitFact>> splits(PublicId account);
}

final class _EnginePortfolioSource implements InvestmentPortfolioSource {
  const _EnginePortfolioSource(this.engine);
  final PreviewEngine engine;

  @override
  bool get isUnlocked => engine.isUnlocked;
  @override
  bool get supportsSales => engine.capabilities.investmentSales;
  @override
  bool get supportsDividends => engine.capabilities.investmentDividends;
  @override
  bool get supportsSplits => engine.capabilities.investmentSplits;
  @override
  Future<List<InvestmentBuyFact>> buys() => engine.investmentBuys();
  @override
  Future<List<InvestmentHoldingLot>> openLots(
    PublicId account,
    PublicId instrument,
  ) => engine.investmentHoldingLots(account, instrument);
  @override
  Future<List<InvestmentSellFact>> sales(
    PublicId account,
    PublicId instrument,
  ) => engine.investmentSales(account, instrument);
  @override
  Future<List<InvestmentDividendFact>> dividends(PublicId account) =>
      engine.investmentDividends(account);
  @override
  Future<List<InvestmentSplitFact>> splits(PublicId account) =>
      engine.investmentSplits(account);
}

final class _PortfolioPositionFacts {
  _PortfolioPositionFacts(this.first);
  final InvestmentBuyFact first;
  final buys = <InvestmentBuyFact>[];
  PublicId get accountId => first.preview.account.id;
  PublicId get instrumentId => first.preview.instrument.id;
  InvestmentInstrument get instrument => first.preview.instrument;
}

final class _PortfolioRead {
  const _PortfolioRead(this.summary, this.quoteNotes);
  final InvestmentPortfolioSummary summary;
  final List<String> quoteNotes;
}

final class _PortfolioLimit implements Exception {
  const _PortfolioLimit();
}

final class _PositionReadFailure implements Exception {
  const _PositionReadFailure(this.instrument);
  final String instrument;
}

/// User-triggered bounded read. No totals are published until every position
/// has been read and checked. A quote failure makes its open position unpriced.
class InvestmentPortfolioSummaryPanel extends StatefulWidget {
  const InvestmentPortfolioSummaryPanel({
    super.key,
    required this.privacy,
    required this.revision,
    this.engine,
    this.source,
    this.gateway,
    this.router,
    this.onSummary,
  }) : assert(engine != null || source != null);

  final PreviewEngine? engine;
  final InvestmentPortfolioSource? source;
  final MarketDataGateway? gateway;
  final MarketDataRouter? router;
  final ValueChanged<InvestmentPortfolioSummary?>? onSummary;
  final PrivacyMode privacy;

  /// Increment after any committed buy, sale, dividend or split is reloaded.
  final int revision;

  @override
  State<InvestmentPortfolioSummaryPanel> createState() =>
      _InvestmentPortfolioSummaryPanelState();
}

class _InvestmentPortfolioSummaryPanelState
    extends State<InvestmentPortfolioSummaryPanel> {
  static const _maximumPositions = 20;
  static const _maximumBuys = 1000;
  static const _maximumFactsPerRead = 1000;

  late final MarketDataGateway _ownedGateway = MarketDataGateway();
  InvestmentPortfolioSource get _source =>
      widget.source ?? _EnginePortfolioSource(widget.engine!);
  MarketDataGateway get _gateway => widget.gateway ?? _ownedGateway;
  _PortfolioRead? _reading;
  String? _problem;
  bool _loading = false;
  int _request = 0;

  bool _current(int request) =>
      mounted &&
      request == _request &&
      _source.isUnlocked &&
      widget.privacy == PrivacyMode.visible;

  @override
  void didUpdateWidget(covariant InvestmentPortfolioSummaryPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision ||
        oldWidget.privacy != widget.privacy ||
        !identical(oldWidget.engine, widget.engine) ||
        !identical(oldWidget.source, widget.source) ||
        !identical(oldWidget.gateway, widget.gateway) ||
        !identical(oldWidget.router, widget.router) ||
        !_source.isUnlocked) {
      _request++;
      _reading = null;
      _problem = null;
      _loading = false;
    }
  }

  @override
  void dispose() {
    _request++;
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_loading ||
        !_source.isUnlocked ||
        widget.privacy != PrivacyMode.visible ||
        !_source.supportsSales) {
      return;
    }
    final request = ++_request;
    setState(() {
      _loading = true;
      _reading = null;
      _problem = null;
    });
    try {
      final reading = await _readAll(request);
      if (!_current(request)) return;
      setState(() {
        _reading = reading;
        _loading = false;
      });
      widget.onSummary?.call(reading.summary);
    } on _PortfolioLimit {
      if (!_current(request)) return;
      setState(() {
        _reading = null;
        _loading = false;
        _problem = '資料量超過暫時安全上限（20 個持倉或單類紀錄 1,000 筆）；摘要不可用，不顯示部分總數。';
      });
      widget.onSummary?.call(null);
    } on _PositionReadFailure catch (error) {
      if (!_current(request)) return;
      setState(() {
        _reading = null;
        _loading = false;
        _problem = '${error.instrument} 的已提交紀錄或權威持倉讀取失敗；摘要不可用，不顯示部分總數。';
      });
      widget.onSummary?.call(null);
    } catch (_) {
      if (!_current(request)) return;
      setState(() {
        _reading = null;
        _loading = false;
        _problem = '無法完整核對投資紀錄；摘要不可用，請稍後重試。';
      });
      widget.onSummary?.call(null);
    }
  }

  Future<_PortfolioRead> _readAll(int request) async {
    final source = _source;
    final buys = await source.buys();
    if (!_current(request)) throw StateError('Read cancelled');
    if (buys.length > _maximumBuys) throw const _PortfolioLimit();
    final positions = <(PublicId, PublicId), _PortfolioPositionFacts>{};
    for (final fact in buys) {
      final preview = fact.preview;
      final key = (preview.account.id, preview.instrument.id);
      final position = positions.putIfAbsent(
        key,
        () => _PortfolioPositionFacts(fact),
      );
      final first = position.first.preview.instrument;
      if (first.tradingCurrency != preview.instrument.tradingCurrency ||
          first.marketCode != preview.instrument.marketCode ||
          first.symbol != preview.instrument.symbol ||
          first.kind != preview.instrument.kind) {
        throw const FormatException('Inconsistent investment identity');
      }
      position.buys.add(fact);
    }
    if (positions.length > _maximumPositions) throw const _PortfolioLimit();

    final dividendByAccount = <PublicId, List<InvestmentDividendFact>>{};
    final splitByAccount = <PublicId, List<InvestmentSplitFact>>{};
    for (final account in positions.keys.map((key) => key.$1).toSet()) {
      final dividends = source.supportsDividends
          ? await source.dividends(account)
          : <InvestmentDividendFact>[];
      if (!_current(request)) throw StateError('Read cancelled');
      if (dividends.length > _maximumFactsPerRead) {
        throw const _PortfolioLimit();
      }
      for (final fact in dividends) {
        if (fact.preview.account.id != account ||
            !positions.containsKey((account, fact.preview.instrument.id))) {
          throw const FormatException('Orphan dividend in portfolio');
        }
      }
      dividendByAccount[account] = dividends;
      final splits = source.supportsSplits
          ? await source.splits(account)
          : <InvestmentSplitFact>[];
      if (!_current(request)) throw StateError('Read cancelled');
      if (splits.length > _maximumFactsPerRead) throw const _PortfolioLimit();
      for (final fact in splits) {
        if (fact.preview.account.id != account ||
            !positions.containsKey((account, fact.preview.instrument.id))) {
          throw const FormatException('Orphan split in portfolio');
        }
      }
      splitByAccount[account] = splits;
    }

    final valued = <InvestmentPositionPerformance>[];
    final quoteNotes = <String>[];
    for (final position in positions.values) {
      final account = position.accountId;
      final instrument = position.instrument;
      late final List<InvestmentHoldingLot> lots;
      late final List<InvestmentSellFact> sales;
      try {
        lots = await source.openLots(account, instrument.id);
        if (!_current(request)) throw StateError('Read cancelled');
        sales = await source.sales(account, instrument.id);
      } catch (_) {
        if (!_current(request)) throw StateError('Read cancelled');
        throw _PositionReadFailure(
          '${instrument.marketCode}:${instrument.symbol}',
        );
      }
      if (!_current(request)) throw StateError('Read cancelled');
      if (lots.length > _maximumFactsPerRead ||
          sales.length > _maximumFactsPerRead) {
        throw const _PortfolioLimit();
      }
      for (final fact in sales) {
        if (fact.preview.account.id != account ||
            fact.preview.instrument.id != instrument.id) {
          throw const FormatException('Wrong sale in portfolio');
        }
      }
      final dividends = dividendByAccount[account]!
          .where((fact) => fact.preview.instrument.id == instrument.id)
          .toList(growable: false);
      final splits = splitByAccount[account]!
          .where((fact) => fact.preview.instrument.id == instrument.id)
          .toList(growable: false);
      final dates = <BusinessDate>[
        for (final fact in position.buys) fact.preview.tradedOn,
        for (final fact in sales) fact.preview.tradedOn,
        for (final fact in dividends) fact.preview.paidOn,
        for (final fact in splits) fact.preview.effectiveOn,
      ];
      final latest = dates.reduce((a, b) => a.compareTo(b) >= 0 ? a : b);
      ShareUnitPrice? usablePrice;
      if (lots.isNotEmpty) {
        try {
          final routed = widget.router == null
              ? null
              : await widget.router!.stockClose(instrument);
          final result =
              routed?.result ?? await _gateway.stockClose(instrument);
          if (!_current(request)) throw StateError('Read cancelled');
          final quote = result.value;
          if (result.state == MarketState.available &&
              quote != null &&
              quote.asOf.compareTo(latest) >= 0) {
            usablePrice = ShareUnitPrice.parse(
              instrument.tradingCurrency,
              quote.decimalPrice,
            );
            quoteNotes.add(
              '${instrument.marketCode}:${instrument.symbol}：${routed?.selectedProvider?.label ?? '預設來源'}收盤價 '
              '${quote.decimalPrice} ${instrument.tradingCurrency.code} · '
              '交易日 ${quote.asOf} · 取得 '
              '${quote.fetchedAt.value.toLocal().toIso8601String()}',
            );
          } else {
            quoteNotes.add(
              '${instrument.marketCode}:${instrument.symbol}：${quote != null && quote.asOf.compareTo(latest) < 0 ? '行情早於最新交易或拆股' : _marketProblem(result.state)}',
            );
          }
        } catch (_) {
          if (!_current(request)) throw StateError('Read cancelled');
          quoteNotes.add(
            '${instrument.marketCode}:${instrument.symbol}：行情查詢失敗',
          );
        }
      }
      final performance = InvestmentPerformance.calculate(
        investmentAccountId: account,
        instrumentId: instrument.id,
        currency: instrument.tradingCurrency,
        openLots: lots,
        realizedResults: [
          for (final fact in sales) fact.preview.realizedResult,
        ],
        netDividends: [
          for (final fact in dividends) fact.preview.netCashCredit,
        ],
        usablePrice: usablePrice,
      );
      valued.add(
        InvestmentPositionPerformance(
          investmentAccountId: account,
          instrumentId: instrument.id,
          tradingCurrency: instrument.tradingCurrency,
          performance: performance,
        ),
      );
    }
    return _PortfolioRead(
      InvestmentPortfolioSummary.calculate(valued),
      List.unmodifiable(quoteNotes),
    );
  }

  String _marketProblem(MarketState state) => switch (state) {
    MarketState.available => '行情資料不足',
    MarketState.stale => '行情已過期',
    MarketState.missing => '無收盤價',
    MarketState.unsupported => '此市場無支援來源',
    MarketState.failed => '行情來源故障',
    MarketState.throttled => '行情查詢過快',
  };

  @override
  Widget build(BuildContext context) {
    if (widget.privacy != PrivacyMode.visible || !_source.isUnlocked) {
      return const Text('投資組合摘要已隱藏。');
    }
    final summary = _reading?.summary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('投資組合（逐幣別）', style: Theme.of(context).textTheme.titleMedium),
        const Text('按需核對已提交持倉；最多 20 個持倉。不同幣別不相加，收盤價僅供參考。'),
        OutlinedButton(
          key: const ValueKey('refresh-investment-portfolio'),
          onPressed: _loading || !_source.supportsSales ? null : _refresh,
          child: Text(_loading ? '核對中…' : '核對逐幣別摘要'),
        ),
        if (_problem != null)
          Text(
            _problem!,
            key: const ValueKey('investment-portfolio-unavailable'),
          ),
        if (summary != null && summary.byCurrency.isEmpty)
          const Text('尚無已提交的投資持倉。'),
        if (summary != null)
          for (final entry in summary.byCurrency.entries)
            _currencyCard(entry.value),
        if (_reading != null)
          for (final note in _reading!.quoteNotes)
            Text(note, key: ValueKey('investment-portfolio-quote-$note')),
      ],
    );
  }

  Widget _currencyCard(InvestmentCurrencySummary row) {
    String amount(Money value) =>
        presentMoney(value, widget.privacy, MoneyKind.balance).text;
    return Card(
      key: ValueKey('investment-portfolio-${row.currency.code}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${row.currency.code} · ${row.positionCount} 個標的'),
            Text('剩餘成本 ${amount(row.remainingCost)}'),
            Text(
              '已實現 ${amount(row.realizedResult)} · 淨股息 ${amount(row.netDividends)}',
            ),
            if (row.hasCompleteValuation) ...[
              Text('參考市值 ${amount(row.marketValue!)}'),
              Text(
                '未實現 ${amount(row.unrealizedResult!)} · 總報酬 ${amount(row.totalReturn!)}',
              ),
            ] else
              Text(
                '估值不完整：${row.missingPriceCount} 個開放持倉缺可用行情；不顯示部分市值、未實現與總報酬。',
              ),
          ],
        ),
      ),
    );
  }
}
