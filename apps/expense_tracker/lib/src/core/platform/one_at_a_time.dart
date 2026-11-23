/// Runs a piece of work never twice at once: asked for while it runs, it
/// runs once more after, not beside it, however often it was asked
/// meanwhile, so what changed in between is still taken. Used for the
/// backups kept when the app is left (ARC-05).
final class OneAtATime {
  OneAtATime(this._work);

  final Future<void> Function() _work;

  Future<void>? _running;
  var _again = false;

  /// Whether the work is running now.
  bool get running => _running != null;

  /// Runs the work, or, while it runs, asks for one more run after it.
  /// Done when the last run asked for so far is.
  Future<void> run() {
    final running = _running;
    if (running != null) {
      _again = true;
      return running;
    }
    return _running = _loop();
  }

  Future<void> _loop() async {
    try {
      do {
        _again = false;
        await _work();
      } while (_again);
    } finally {
      _running = null;
    }
  }
}
