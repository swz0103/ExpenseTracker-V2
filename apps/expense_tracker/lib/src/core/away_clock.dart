/// How long the app was away, for locking the ledger again: by the
/// phone's clock and by a clock that only runs forward, so setting the
/// phone's time back does not keep the ledger open. A clock that went
/// backwards counts as away long enough.
final class AwayClock {
  AwayClock({DateTime Function()? now, Duration Function()? running})
    : _now = now ?? DateTime.now,
      _running = running;

  final DateTime Function() _now;

  /// Time that only runs forward; a stopwatch unless given, for tests.
  final Duration Function()? _running;
  final _watch = Stopwatch();
  DateTime? _leftAt;
  Duration _startedAt = Duration.zero;

  Duration get _elapsed => _running?.call() ?? _watch.elapsed;

  /// The app left the screen; the first of several counts.
  void leave() {
    if (_leftAt != null) return;
    _leftAt = _now();
    _watch
      ..reset()
      ..start();
    _startedAt = _elapsed;
  }

  /// The app is back: whether it was away [limit] or more. False when it
  /// never left.
  bool back(Duration limit) {
    final left = _leftAt;
    _leftAt = null;
    _watch.stop();
    if (left == null) return false;
    final wall = _now().difference(left);
    final running = _elapsed - _startedAt;
    return wall.isNegative || wall >= limit || running >= limit;
  }
}
