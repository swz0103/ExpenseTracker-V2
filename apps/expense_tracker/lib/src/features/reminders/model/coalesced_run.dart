import 'dart:async';

/// Runs a task soon after it is asked for, once for every burst of asks,
/// and never twice at once: asked again while it runs, it runs once more
/// when done. What it works from is read when it runs, so the last ask
/// is always seen.
final class CoalescedRun {
  CoalescedRun(this._task);

  final Future<void> Function() _task;

  var _asked = false;
  var _running = false;
  var _stopped = false;
  Timer? _timer;

  /// Asks for a run: after the changes made in this turn of the event
  /// loop, so a save that changes several things runs it once.
  void ask() {
    if (_stopped) return;
    _asked = true;
    if (_running || _timer != null) return;
    _timer = Timer(Duration.zero, _drain);
  }

  /// Done once the runs asked for so far are done.
  Future<void> get idle async {
    while (_running || _timer != null) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> _drain() async {
    _timer = null;
    _running = true;
    try {
      while (_asked && !_stopped) {
        _asked = false;
        await _task();
      }
    } finally {
      _running = false;
    }
  }

  /// No more runs; one under way finishes.
  void stop() {
    _stopped = true;
    _timer?.cancel();
    _timer = null;
  }
}
