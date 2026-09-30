import 'package:flutter/material.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:investments/investments.dart';
import 'package:market_data/market_data.dart';

final class MarketSourceResultView {
  const MarketSourceResultView({
    required this.state,
    required this.valueText,
    required this.observationText,
    required this.provider,
    required this.attempts,
  });

  final MarketState state;
  final String? valueText;
  final String? observationText;
  final MarketProviderDescriptor? provider;
  final List<MarketProviderAttempt> attempts;
}

final class MarketCrossCheckRowView {
  const MarketCrossCheckRowView({
    required this.provider,
    required this.state,
    required this.valueText,
    required this.observationText,
  });

  final MarketProviderDescriptor provider;
  final MarketState state;
  final String? valueText;
  final String? observationText;
}

final class MarketCrossCheckView {
  const MarketCrossCheckView({
    required this.rows,
    required this.conflict,
    this.reason,
  });

  final List<MarketCrossCheckRowView> rows;
  final bool conflict;
  final String? reason;
}

abstract interface class MarketSourcePanelController {
  List<MarketProviderDescriptor> get providers;

  Future<MarketSourceResultView> fetch({String? fixedProviderId});

  Future<MarketCrossCheckView> crossCheck();
}

final class StockCloseSourceController implements MarketSourcePanelController {
  const StockCloseSourceController({
    required this.router,
    required this.instrument,
    this.requiredAsOf,
  });

  final MarketDataRouter router;
  final InvestmentInstrument instrument;
  final BusinessDate? requiredAsOf;

  @override
  List<MarketProviderDescriptor> get providers => router.registry
      .stockCloseProviders(instrument)
      .map((provider) => provider.descriptor)
      .toList(growable: false);

  @override
  Future<MarketSourceResultView> fetch({String? fixedProviderId}) async {
    final routed = await router.stockClose(
      instrument,
      requiredAsOf: requiredAsOf,
      policy: fixedProviderId == null
          ? const MarketRoutingPolicy.automatic()
          : MarketRoutingPolicy.fixed(fixedProviderId),
    );
    final value = routed.result.value;
    return MarketSourceResultView(
      state: routed.result.state,
      valueText: value?.decimalPrice,
      observationText: value == null
          ? null
          : '${value.asOf} · ${value.fetchedAt.value.toUtc().toIso8601String()}',
      provider: routed.selectedProvider,
      attempts: routed.attempts,
    );
  }

  @override
  Future<MarketCrossCheckView> crossCheck() async {
    final checked = await router.crossCheckStockClose(
      instrument,
      requiredAsOf: requiredAsOf,
    );
    return MarketCrossCheckView(
      rows: [
        for (final item in checked.items)
          MarketCrossCheckRowView(
            provider: item.provider,
            state: item.result.state,
            valueText: item.result.value?.decimalPrice,
            observationText: item.result.value?.asOf.toString(),
          ),
      ],
      conflict: checked.conflict,
      reason: checked.reason,
    );
  }
}

final class MarketSourcePanel extends StatefulWidget {
  const MarketSourcePanel({required this.controller, super.key});

  final MarketSourcePanelController controller;

  @override
  State<MarketSourcePanel> createState() => _MarketSourcePanelState();
}

final class _MarketSourcePanelState extends State<MarketSourcePanel> {
  String? _fixedProviderId;
  MarketSourceResultView? _result;
  MarketCrossCheckView? _crossCheck;
  bool _busy = false;
  String? _error;

  Future<void> _run(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await operation();
    } catch (_) {
      if (mounted) setState(() => _error = '市場資料目前無法取得，帳本內容未變更。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _fetch() => _run(() async {
    final result = await widget.controller.fetch(
      fixedProviderId: _fixedProviderId,
    );
    if (mounted) {
      setState(() {
        _result = result;
        _crossCheck = null;
      });
    }
  });

  Future<void> _compare() => _run(() async {
    final result = await widget.controller.crossCheck();
    if (mounted) setState(() => _crossCheck = result);
  });

  @override
  Widget build(BuildContext context) {
    final providers = widget.controller.providers;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          key: const ValueKey('market-provider-choice'),
          initialValue: _fixedProviderId ?? 'automatic',
          decoration: const InputDecoration(labelText: '市場資料來源'),
          items: [
            const DropdownMenuItem(value: 'automatic', child: Text('自動選擇')),
            for (final provider in providers)
              DropdownMenuItem(value: provider.id, child: Text(provider.label)),
          ],
          onChanged: _busy
              ? null
              : (value) => setState(() {
                  _fixedProviderId = value == 'automatic' ? null : value;
                  _result = null;
                  _crossCheck = null;
                }),
        ),
        FilledButton(
          onPressed: _busy ? null : _fetch,
          child: const Text('查詢參考資料'),
        ),
        OutlinedButton(
          onPressed: _busy || providers.length < 2 ? null : _compare,
          child: const Text('核對所有可用來源'),
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) Text(_error!, key: const ValueKey('market-error')),
        if (_result case final result?) ...[
          const Divider(),
          Text('狀態：${_stateText(result.state)}'),
          if (result.valueText != null) Text('參考值：${result.valueText}'),
          if (result.observationText != null)
            Text('觀測／取得：${result.observationText}'),
          if (result.provider case final provider?) ...[
            Text('實際來源：${provider.label}'),
            Text('資料集：${provider.dataset}'),
            Text('來源註記：${provider.attribution}'),
          ],
          if (result.attempts.length > 1) const Text('已使用備援來源；嘗試紀錄：'),
          for (final attempt in result.attempts)
            Text(
              '${attempt.provider.label}：${_stateText(attempt.state)}'
              '${attempt.reason == null ? '' : '（${attempt.reason}）'}',
              key: ValueKey('market-attempt-${attempt.provider.id}'),
            ),
        ],
        if (_crossCheck case final checked?) ...[
          const Divider(),
          Text(
            checked.conflict ? '來源資料有衝突，不自動選值或平均。' : '各來源在可比較欄位上一致。',
            key: const ValueKey('market-cross-check-status'),
          ),
          if (checked.reason != null) Text(checked.reason!),
          for (final row in checked.rows)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(row.provider.label),
              subtitle: Text(
                '${_stateText(row.state)} · ${row.observationText ?? '無觀測日'}',
              ),
              trailing: Text(row.valueText ?? '—'),
            ),
        ],
        const Text('市場資料只供估值參考，不會改寫成交、成本、換匯或現金。'),
      ],
    );
  }
}

String _stateText(MarketState state) => switch (state) {
  MarketState.available => '可用',
  MarketState.stale => '較舊',
  MarketState.missing => '無資料',
  MarketState.unsupported => '不支援',
  MarketState.failed => '失敗',
  MarketState.throttled => '暫時受限',
};
