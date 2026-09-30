import 'dart:async';

import 'intraday.dart';
import 'market_data.dart';
import 'routing.dart';

final class IntradayRefreshPolicy {
  IntradayRefreshPolicy({
    required this.refreshEvery,
    this.maximumBackoff = const Duration(minutes: 15),
  }) {
    if (refreshEvery < const Duration(minutes: 1) ||
        refreshEvery > const Duration(minutes: 5)) {
      throw ArgumentError.value(
        refreshEvery,
        'refreshEvery',
        'Must be between one and five minutes',
      );
    }
    if (maximumBackoff < refreshEvery ||
        maximumBackoff > const Duration(hours: 1)) {
      throw ArgumentError.value(maximumBackoff, 'maximumBackoff');
    }
  }

  final Duration refreshEvery;
  final Duration maximumBackoff;

  Duration delayAfter(MarketState state, int consecutiveFailures) {
    if (state != MarketState.failed && state != MarketState.throttled) {
      return refreshEvery;
    }
    var delay = refreshEvery;
    for (var i = 0; i < consecutiveFailures && delay < maximumBackoff; i++) {
      delay *= 2;
    }
    return delay > maximumBackoff ? maximumBackoff : delay;
  }
}

final class IntradayRefreshSnapshot {
  const IntradayRefreshSnapshot({
    required this.sequence,
    required this.routed,
    required this.nextAttemptAt,
    required this.consecutiveFailures,
  });

  final int sequence;
  final RoutedMarketResult<IntradayBar> routed;
  MarketResult<IntradayBar> get result => routed.result;
  final DateTime nextAttemptAt;
  final int consecutiveFailures;
}

abstract interface class IntradayRefreshTimer {
  void cancel();
}

typedef IntradayRefreshScheduler = IntradayRefreshTimer Function(
  Duration delay,
  void Function() callback,
);

typedef IntradayBarFetch = Future<RoutedMarketResult<IntradayBar>> Function();

final class IntradayRefreshController {
  IntradayRefreshController({
    required IntradayBarFetch fetch,
    required IntradayRefreshPolicy policy,
    DateTime Function()? clock,
    IntradayRefreshScheduler? scheduler,
  }) : _fetch = fetch,
       _policy = policy,
       _clock = clock ?? DateTime.now,
       _scheduler = scheduler ?? _scheduleTimer;

  final IntradayBarFetch _fetch;
  final IntradayRefreshPolicy _policy;
  final DateTime Function() _clock;
  final IntradayRefreshScheduler _scheduler;
  final StreamController<IntradayRefreshSnapshot> _snapshots =
      StreamController.broadcast(sync: true);

  IntradayRefreshTimer? _timer;
  var _active = false;
  var _fetching = false;
  var _disposed = false;
  var _generation = 0;
  var _sequence = 0;
  var _consecutiveFailures = 0;

  Stream<IntradayRefreshSnapshot> get snapshots => _snapshots.stream;
  bool get isActive => _active;
  bool get isFetching => _fetching;

  void start() {
    _ensureUsable();
    if (_active) return;
    _active = true;
    _generation++;
    unawaited(_run(_generation));
  }

  void refreshNow() {
    _ensureUsable();
    if (!_active || _fetching) return;
    _timer?.cancel();
    _timer = null;
    _generation++;
    unawaited(_run(_generation));
  }

  void stop() {
    if (!_active) return;
    _active = false;
    _generation++;
    _timer?.cancel();
    _timer = null;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    stop();
    _disposed = true;
    await _snapshots.close();
  }

  Future<void> _run(int generation) async {
    if (!_active || _fetching || generation != _generation) return;
    _fetching = true;
    late final RoutedMarketResult<IntradayBar> routed;
    try {
      routed = await _fetch();
    } catch (_) {
      routed = const RoutedMarketResult(
        result: MarketResult(
          MarketState.failed,
          reason: 'Intraday refresh failed',
        ),
        selectedProvider: null,
        attempts: [],
      );
    } finally {
      _fetching = false;
    }
    if (_active && !_disposed && generation != _generation) {
      unawaited(_run(_generation));
      return;
    }
    if (!_active || _disposed || generation != _generation) return;
    if (routed.result.state == MarketState.failed ||
        routed.result.state == MarketState.throttled) {
      _consecutiveFailures++;
    } else {
      _consecutiveFailures = 0;
    }
    final delay = _policy.delayAfter(routed.result.state, _consecutiveFailures);
    final next = _clock().toUtc().add(delay);
    _snapshots.add(
      IntradayRefreshSnapshot(
        sequence: ++_sequence,
        routed: routed,
        nextAttemptAt: next,
        consecutiveFailures: _consecutiveFailures,
      ),
    );
    _timer = _scheduler(delay, () {
      if (!_active || _disposed || generation != _generation) return;
      _timer = null;
      unawaited(_run(generation));
    });
  }

  void _ensureUsable() {
    if (_disposed) throw StateError('Intraday refresh controller is disposed');
  }
}

final class _TimerAdapter implements IntradayRefreshTimer {
  _TimerAdapter(this.timer);
  final Timer timer;

  @override
  void cancel() => timer.cancel();
}

IntradayRefreshTimer _scheduleTimer(Duration delay, void Function() callback) =>
    _TimerAdapter(Timer(delay, callback));
