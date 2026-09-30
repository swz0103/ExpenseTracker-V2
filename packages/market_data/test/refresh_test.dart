import 'dart:async';
import 'dart:collection';

import 'package:foundation_values/foundation_values.dart';
import 'package:market_data/market_data.dart';
import 'package:test/test.dart';

final class FakeTimer implements IntradayRefreshTimer {
  FakeTimer(this.delay, this.callback);

  final Duration delay;
  final void Function() callback;
  var cancelled = false;

  @override
  void cancel() => cancelled = true;

  void fire() {
    if (!cancelled) callback();
  }
}

final class FakeScheduler {
  final timers = <FakeTimer>[];

  IntradayRefreshTimer schedule(Duration delay, void Function() callback) {
    final timer = FakeTimer(delay, callback);
    timers.add(timer);
    return timer;
  }
}

IntradayBar bar() => IntradayBar(
  symbol: '2330',
  interval: IntradayInterval.oneMinute,
  startsAt: UtcInstant(DateTime.utc(2026, 9, 30, 1)),
  open: '100',
  high: '101',
  low: '99',
  close: '100.5',
  volume: BigInt.from(10),
  fetchedAt: UtcInstant(DateTime.utc(2026, 9, 30, 1, 1)),
);

Future<void> pump() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  test('policy accepts only one-to-five-minute refresh cadence', () {
    expect(
      () => IntradayRefreshPolicy(refreshEvery: const Duration(seconds: 59)),
      throwsArgumentError,
    );
    expect(
      () => IntradayRefreshPolicy(refreshEvery: const Duration(minutes: 6)),
      throwsArgumentError,
    );
    expect(
      IntradayRefreshPolicy(refreshEvery: const Duration(minutes: 1))
          .refreshEvery,
      const Duration(minutes: 1),
    );
    expect(
      IntradayRefreshPolicy(refreshEvery: const Duration(minutes: 5))
          .refreshEvery,
      const Duration(minutes: 5),
    );
  });

  test('start fetches immediately then schedules without overlap', () async {
    final scheduler = FakeScheduler();
    var calls = 0;
    final controller = IntradayRefreshController(
      fetch: () async {
        calls++;
        return MarketResult(MarketState.available, value: bar());
      },
      policy: IntradayRefreshPolicy(refreshEvery: const Duration(minutes: 1)),
      clock: () => DateTime.utc(2026, 9, 30, 1, 1),
      scheduler: scheduler.schedule,
    );
    final snapshots = <IntradayRefreshSnapshot>[];
    final subscription = controller.snapshots.listen(snapshots.add);
    controller.start();
    controller.start();
    await pump();
    expect(calls, 1);
    expect(snapshots.single.sequence, 1);
    expect(snapshots.single.nextAttemptAt, DateTime.utc(2026, 9, 30, 1, 2));
    expect(scheduler.timers.single.delay, const Duration(minutes: 1));

    scheduler.timers.single.fire();
    await pump();
    expect(calls, 2);
    expect(snapshots.last.sequence, 2);
    await controller.dispose();
    await subscription.cancel();
  });

  test('throttling backs off and success resets failure count', () async {
    final scheduler = FakeScheduler();
    final results = Queue<MarketResult<IntradayBar>>.of([
      const MarketResult(MarketState.throttled, reason: 'limit'),
      const MarketResult(MarketState.failed, reason: 'offline'),
      MarketResult(MarketState.available, value: bar()),
    ]);
    final controller = IntradayRefreshController(
      fetch: () async => results.removeFirst(),
      policy: IntradayRefreshPolicy(
        refreshEvery: const Duration(minutes: 1),
        maximumBackoff: const Duration(minutes: 5),
      ),
      scheduler: scheduler.schedule,
    );
    final snapshots = <IntradayRefreshSnapshot>[];
    final subscription = controller.snapshots.listen(snapshots.add);
    controller.start();
    await pump();
    expect(snapshots.last.consecutiveFailures, 1);
    expect(scheduler.timers.last.delay, const Duration(minutes: 2));

    scheduler.timers.last.fire();
    await pump();
    expect(snapshots.last.consecutiveFailures, 2);
    expect(scheduler.timers.last.delay, const Duration(minutes: 4));

    scheduler.timers.last.fire();
    await pump();
    expect(snapshots.last.consecutiveFailures, 0);
    expect(scheduler.timers.last.delay, const Duration(minutes: 1));
    await controller.dispose();
    await subscription.cancel();
  });

  test('stop ignores an in-flight result and schedules nothing', () async {
    final scheduler = FakeScheduler();
    final pending = Completer<MarketResult<IntradayBar>>();
    final controller = IntradayRefreshController(
      fetch: () => pending.future,
      policy: IntradayRefreshPolicy(refreshEvery: const Duration(minutes: 1)),
      scheduler: scheduler.schedule,
    );
    final snapshots = <IntradayRefreshSnapshot>[];
    final subscription = controller.snapshots.listen(snapshots.add);
    controller.start();
    await pump();
    expect(controller.isFetching, isTrue);
    controller.stop();
    pending.complete(MarketResult(MarketState.available, value: bar()));
    await pump();
    expect(snapshots, isEmpty);
    expect(scheduler.timers, isEmpty);
    expect(controller.isActive, isFalse);
    await controller.dispose();
    await subscription.cancel();
  });

  test(
    'restart during an old in-flight request resumes after it settles',
    () async {
      final scheduler = FakeScheduler();
      final first = Completer<MarketResult<IntradayBar>>();
      var calls = 0;
      final controller = IntradayRefreshController(
        fetch: () {
          calls++;
          if (calls == 1) return first.future;
          return Future.value(
            MarketResult(MarketState.available, value: bar()),
          );
        },
        policy: IntradayRefreshPolicy(refreshEvery: const Duration(minutes: 1)),
        scheduler: scheduler.schedule,
      );
      final snapshots = <IntradayRefreshSnapshot>[];
      final subscription = controller.snapshots.listen(snapshots.add);
      controller.start();
      await pump();
      controller.stop();
      controller.start();
      expect(calls, 1);
      first.complete(MarketResult(MarketState.available, value: bar()));
      await pump();
      expect(calls, 2);
      expect(snapshots, hasLength(1));
      expect(scheduler.timers, hasLength(1));
      await controller.dispose();
      await subscription.cancel();
    },
  );

  test('refreshNow cancels waiting timer and fetches immediately', () async {
    final scheduler = FakeScheduler();
    var calls = 0;
    final controller = IntradayRefreshController(
      fetch: () async {
        calls++;
        return MarketResult(MarketState.available, value: bar());
      },
      policy: IntradayRefreshPolicy(refreshEvery: const Duration(minutes: 5)),
      scheduler: scheduler.schedule,
    );
    final subscription = controller.snapshots.listen((_) {});
    controller.start();
    await pump();
    final original = scheduler.timers.single;
    controller.refreshNow();
    await pump();
    expect(original.cancelled, isTrue);
    expect(calls, 2);
    expect(scheduler.timers.last.delay, const Duration(minutes: 5));
    await controller.dispose();
    await subscription.cancel();
    expect(() => controller.start(), throwsStateError);
  });
}
