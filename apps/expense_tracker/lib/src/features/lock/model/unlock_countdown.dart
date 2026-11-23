import 'dart:async';

import '../../../core/diagnostics/error_log.dart';
import '../../../core/messages/lock_messages.dart';

/// The wait after too many wrong passwords or recovery codes, as the lock
/// screen counts it down: it asks how long the wait still is, and keeps
/// asking each second while it lasts, so the screen opens up by itself.
/// How long is the keeper's (`UnlockAttempts`); this only follows it.
final class UnlockCountdown {
  UnlockCountdown({
    required this._ask,
    required this._limited,
    required this._changed,
  });

  /// How long the wait still is, as its keeper says.
  final Future<Duration> Function() _ask;

  /// Whether what is asked for now is slowed down at all (a backup's
  /// secret is not); nothing is asked while it is not.
  final bool Function() _limited;

  /// Told each time [wait] changes.
  final void Function(Duration wait) _changed;

  /// How long until a secret may be tried again; zero when one may be
  /// now.
  Duration get wait => _wait;
  var _wait = Duration.zero;

  Timer? _ticker;
  var _closed = false;

  /// Asks how long the wait still is; while there is one, asks again each
  /// second.
  Future<void> refresh() async {
    if (_closed || !_limited()) return;
    final Duration asked;
    try {
      asked = await _ask();
    } on Object catch (error) {
      ErrorLog.instance.record(LockWords.lockHeading, error);
      return;
    }
    if (_closed) return;
    final waiting = asked > Duration.zero && _limited();
    if (waiting) {
      _ticker ??= Timer.periodic(
        const Duration(seconds: 1),
        (_) => unawaited(refresh()),
      );
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
    final next = waiting ? asked : Duration.zero;
    if (next == _wait) return;
    _wait = next;
    _changed(next);
  }

  /// Stops counting: the screen has gone.
  void close() {
    _closed = true;
    _ticker?.cancel();
    _ticker = null;
  }
}
