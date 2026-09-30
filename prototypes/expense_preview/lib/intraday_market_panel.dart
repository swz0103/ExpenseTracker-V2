import 'dart:async';

import 'package:flutter/material.dart';
import 'package:investments/investments.dart';
import 'package:market_data/market_data.dart';

abstract interface class IntradayRefreshControllerFactory {
  IntradayRefreshController create({
    required IntradayInterval interval,
    required Duration refreshEvery,
  });
}

final class RoutedIntradayRefreshControllerFactory
    implements IntradayRefreshControllerFactory {
  const RoutedIntradayRefreshControllerFactory({
    required this.router,
    required this.instrument,
    this.fixedProviderId,
  });

  final MarketDataRouter router;
  final InvestmentInstrument instrument;
  final String? fixedProviderId;

  @override
  IntradayRefreshController create({
    required IntradayInterval interval,
    required Duration refreshEvery,
  }) => IntradayRefreshController(
    fetch: () => router.intradayBar(
      instrument,
      interval: interval,
      policy: fixedProviderId == null
          ? const MarketRoutingPolicy.automatic()
          : MarketRoutingPolicy.fixed(fixedProviderId!),
    ),
    policy: IntradayRefreshPolicy(refreshEvery: refreshEvery),
  );
}

final class IntradayMarketPanel extends StatefulWidget {
  const IntradayMarketPanel({required this.factory, super.key});

  final IntradayRefreshControllerFactory factory;

  @override
  State<IntradayMarketPanel> createState() => _IntradayMarketPanelState();
}

final class _IntradayMarketPanelState extends State<IntradayMarketPanel> {
  IntradayInterval _interval = IntradayInterval.oneMinute;
  int _refreshMinutes = 1;
  IntradayRefreshController? _controller;
  StreamSubscription<IntradayRefreshSnapshot>? _subscription;
  IntradayRefreshSnapshot? _snapshot;
  bool _running = false;

  void _start() {
    if (_running) return;
    final controller = widget.factory.create(
      interval: _interval,
      refreshEvery: Duration(minutes: _refreshMinutes),
    );
    _controller = controller;
    _subscription = controller.snapshots.listen((snapshot) {
      if (mounted) setState(() => _snapshot = snapshot);
    });
    setState(() => _running = true);
    controller.start();
  }

  Future<void> _stop() async {
    final controller = _controller;
    final subscription = _subscription;
    _controller = null;
    _subscription = null;
    if (mounted) setState(() => _running = false);
    controller?.stop();
    await subscription?.cancel();
    await controller?.dispose();
  }

  @override
  void dispose() {
    final controller = _controller;
    final subscription = _subscription;
    controller?.stop();
    unawaited(subscription?.cancel());
    if (controller != null) unawaited(controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final result = snapshot?.result;
    final bar = result?.value;
    final provider = snapshot?.routed.selectedProvider;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<IntradayInterval>(
          key: const ValueKey('intraday-bar-interval'),
          initialValue: _interval,
          decoration: const InputDecoration(labelText: 'K 線週期'),
          items: const [
            DropdownMenuItem(
              value: IntradayInterval.oneMinute,
              child: Text('1 分鐘'),
            ),
            DropdownMenuItem(
              value: IntradayInterval.fiveMinutes,
              child: Text('5 分鐘'),
            ),
          ],
          onChanged: _running
              ? null
              : (value) {
                  if (value != null) setState(() => _interval = value);
                },
        ),
        DropdownButtonFormField<int>(
          key: const ValueKey('intraday-refresh-interval'),
          initialValue: _refreshMinutes,
          decoration: const InputDecoration(labelText: '更新頻率'),
          items: [
            for (var minute = 1; minute <= 5; minute++)
              DropdownMenuItem(value: minute, child: Text('每 $minute 分鐘')),
          ],
          onChanged: _running
              ? null
              : (value) {
                  if (value != null) setState(() => _refreshMinutes = value);
                },
        ),
        FilledButton(
          key: const ValueKey('intraday-toggle'),
          onPressed: _running ? _stop : _start,
          child: Text(_running ? '停止更新' : '開始更新'),
        ),
        OutlinedButton(
          onPressed: _running && !(_controller?.isFetching ?? true)
              ? _controller?.refreshNow
              : null,
          child: const Text('立即更新'),
        ),
        if (_running && snapshot == null) const LinearProgressIndicator(),
        if (snapshot != null) ...[
          const Divider(),
          Text('狀態：${_stateText(result!.state)}'),
          if (bar != null) ...[
            Text('最新價：${bar.close}', key: const ValueKey('intraday-price')),
            Text('觀測時間：${bar.startsAt.value.toLocal().toIso8601String()}'),
            Text('成交量：${bar.volume}'),
          ],
          if (provider != null) ...[
            Text('實際來源：${provider.label}'),
            Text('資料集：${provider.dataset}'),
            Text('來源註記：${provider.attribution}'),
            if (provider.id == TwelveDataIntradayStockProvider.providerId)
              const Text(
                '免費方案目前約 8 credits/分鐘、800 次/日；持倉較多時請改用 5 分鐘或較高方案。',
                key: ValueKey('twelve-data-quota-note'),
              ),
            if (provider.id == FugleIntradayStockProvider.providerId)
              const Text(
                '基本方案目前為 60 次/分鐘；WebSocket 同時訂閱數另有限制。',
                key: ValueKey('fugle-quota-note'),
              ),
          ],
          if (result.reason != null) Text('說明：${result.reason}'),
          Text('下次嘗試：${snapshot.nextAttemptAt.toLocal().toIso8601String()}'),
          if (snapshot.consecutiveFailures > 0)
            Text('連續失敗：${snapshot.consecutiveFailures}；已自動降低請求頻率。'),
          for (final attempt in snapshot.routed.attempts)
            Text(
              '${attempt.provider.label}：${_stateText(attempt.state)}',
              key: ValueKey('intraday-attempt-${attempt.provider.id}'),
            ),
        ],
        const Text('盤中行情只供估值參考，不會改寫成交、成本、換匯或現金。'),
      ],
    );
  }
}

String _stateText(MarketState state) => switch (state) {
  MarketState.available => '可用',
  MarketState.stale => '已過期',
  MarketState.missing => '無資料',
  MarketState.unsupported => '不支援',
  MarketState.failed => '失敗',
  MarketState.throttled => '暫時受限',
};
