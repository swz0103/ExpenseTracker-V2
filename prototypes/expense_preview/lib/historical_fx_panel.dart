import 'package:flutter/material.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:market_adapters/market_adapters.dart';
import 'package:market_data/market_data.dart';

/// Explicit, read-only ECB reference lookup. It never posts or converts Ledger
/// amounts; a bank or broker execution must use its actual agreed rate.
class HistoricalFxPanel extends StatefulWidget {
  const HistoricalFxPanel({super.key, required this.showAmounts, this.gateway});

  final bool showAmounts;
  final MarketDataGateway? gateway;

  @override
  State<HistoricalFxPanel> createState() => _HistoricalFxPanelState();
}

class _HistoricalFxPanelState extends State<HistoricalFxPanel> {
  static const _pairs = [
    'EUR/USD',
    'USD/EUR',
    'EUR/JPY',
    'JPY/EUR',
    'EUR/GBP',
    'GBP/EUR',
    'EUR/CHF',
    'CHF/EUR',
  ];

  late final MarketDataGateway _ownedGateway = MarketDataGateway(
    transport: const IoMarketTransport(),
  );
  late final TextEditingController _date = TextEditingController(
    text: _today(),
  );
  String _pair = _pairs.first;
  MarketResult<ReferenceRate>? _result;
  String? _inputProblem;
  bool _loading = false;
  int _request = 0;

  MarketDataGateway get _gateway => widget.gateway ?? _ownedGateway;

  static String _today() {
    final now = DateTime.now();
    return BusinessDate(now.year, now.month, now.day).toString();
  }

  void _clear() {
    _request++;
    setState(() {
      _result = null;
      _inputProblem = null;
      _loading = false;
    });
  }

  @override
  void didUpdateWidget(covariant HistoricalFxPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.showAmounts != widget.showAmounts ||
        !identical(oldWidget.gateway, widget.gateway)) {
      _request++;
      _result = null;
      _inputProblem = null;
      _loading = false;
    }
  }

  @override
  void dispose() {
    _request++;
    _date.dispose();
    super.dispose();
  }

  Future<void> _lookUp() async {
    if (!widget.showAmounts || _loading) return;
    BusinessDate day;
    try {
      day = BusinessDate.parse(_date.text.trim());
    } on FormatException {
      _clear();
      setState(() => _inputProblem = '請輸入有效日期（YYYY-MM-DD）。');
      return;
    } on ArgumentError {
      _clear();
      setState(() => _inputProblem = '請輸入有效日期（YYYY-MM-DD）。');
      return;
    }
    final request = ++_request;
    final parts = _pair.split('/');
    Currency currency(String code) => Currency.iso(code);
    setState(() {
      _loading = true;
      _result = null;
      _inputProblem = null;
    });
    MarketResult<ReferenceRate> result;
    try {
      result = await _gateway.historicalFxRate(
        currency(parts[0]),
        currency(parts[1]),
        date: day,
      );
    } catch (_) {
      result = const MarketResult(MarketState.failed, reason: 'ECB 查詢失敗');
    }
    if (!mounted || request != _request || !widget.showAmounts) return;
    setState(() {
      _loading = false;
      _result = result;
    });
  }

  String _rateText(FxRate rate) {
    final denominator = rate.denominator;
    final scaled =
        (rate.numerator * BigInt.from(1000000) + denominator ~/ BigInt.two) ~/
        denominator;
    final whole = scaled ~/ BigInt.from(1000000);
    final decimal = (scaled % BigInt.from(1000000)).toString().padLeft(6, '0');
    return '$whole.$decimal';
  }

  String _problem(MarketState state) => switch (state) {
    MarketState.available => '匯率資料不足。',
    MarketState.stale => '只找到較早的觀測日，不能當作指定日期的匯率。',
    MarketState.missing => '指定日期及七日內沒有可用觀測值。',
    MarketState.unsupported => '目前僅支援 EUR 與 USD／JPY／GBP／CHF 的參考匯率。',
    MarketState.failed => '歐洲央行資料目前無法使用，請稍後重試。',
    MarketState.throttled => '查詢過於頻繁，請稍後重試。',
  };

  @override
  Widget build(BuildContext context) {
    if (!widget.showAmounts) {
      return const Text('歷史匯率已由隱私模式遮蔽。');
    }
    final result = _result;
    final observation = result?.value?.observation;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('歷史參考匯率', style: Theme.of(context).textTheme.titleMedium),
        const Text('歐洲央行 EUR 基準日匯率；僅供參考，實際換匯與入帳以銀行或券商成交資料為準。'),
        DropdownButtonFormField<String>(
          key: const ValueKey('historical-fx-pair'),
          initialValue: _pair,
          decoration: const InputDecoration(labelText: '幣對'),
          items: [
            for (final pair in _pairs)
              DropdownMenuItem(value: pair, child: Text(pair)),
          ],
          onChanged: _loading
              ? null
              : (value) {
                  if (value == null || value == _pair) return;
                  setState(() => _pair = value);
                  _clear();
                },
        ),
        TextField(
          key: const ValueKey('historical-fx-date'),
          controller: _date,
          enabled: !_loading,
          keyboardType: TextInputType.datetime,
          decoration: const InputDecoration(labelText: '查詢日期（YYYY-MM-DD）'),
          onChanged: (_) => _clear(),
        ),
        OutlinedButton(
          key: const ValueKey('request-historical-fx'),
          onPressed: _loading ? null : _lookUp,
          child: Text(_loading ? '查詢中…' : '查詢歷史參考匯率'),
        ),
        if (_inputProblem != null) Text(_inputProblem!),
        if (result != null && observation != null) ...[
          Text(
            '來源：歐洲央行 · 觀測日 ${observation.asOf} · 取得 ${observation.retrievedAt.value.toLocal().toIso8601String()}',
            key: const ValueKey('historical-fx-source'),
          ),
          if (result.state == MarketState.available)
            Text(
              '1 ${observation.rate.base.code} ≈ ${_rateText(observation.rate)} ${observation.rate.quote.code}（參考值）',
              key: const ValueKey('historical-fx-value'),
            )
          else
            Text(
              '${_problem(result.state)}較早參考值：1 ${observation.rate.base.code} ≈ ${_rateText(observation.rate)} ${observation.rate.quote.code}；不當作指定日匯率。',
              key: const ValueKey('historical-fx-stale'),
            ),
        ] else if (result != null)
          Text(
            _problem(result.state),
            key: const ValueKey('historical-fx-unavailable'),
          ),
      ],
    );
  }
}
