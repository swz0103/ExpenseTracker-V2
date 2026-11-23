import 'package:flutter/widgets.dart' show AppLifecycleState;

import 'lock_gate.dart';

/// What the open ledger does as the app goes away and comes back; the
/// [AppLifecycle] calls it, in its order, and nothing else does.
abstract interface class LifecycleSession {
  /// The app really left the screen, on no trip of its own: the backups
  /// kept on leaving are taken now. Called once per leave.
  void leave();

  /// The app is in front again and the ledger stays open: what fell due
  /// meanwhile is booked, prices and versions are looked for. Called once
  /// per return, after the lock gate has decided not to lock.
  void returned();
}

/// Where the app stands between the phone's lifecycle events.
enum LifecyclePhase {
  /// On the screen.
  present,

  /// Off the screen since the first hidden or paused.
  away,

  /// Coming back (inactive) and the ledger stays open: [LifecycleSession.
  /// returned] waits for resumed.
  returning,

  /// Coming back and the gate locks: nothing of the ledger runs.
  locking,
}

/// The one owner of what happens when the app leaves the screen and
/// comes back, in an order a test states:
///
/// - **Leaving.** The first hidden or paused of a leave counts, the
///   others are the same leave: the lock gate covers the ledger first
///   ([LockGate.left]), then the session's backups run once
///   ([LifecycleSession.leave]), unless the trip is one the app sent the
///   person on itself (the camera, a file chooser, Google's sign-in:
///   [LockGate.onErrand]).
/// - **Coming back.** The first inactive or resumed after a leave asks the
///   gate whether the ledger locks ([LockGate.returned]) before anything
///   else; only when it stays open, and once the app is resumed, does the
///   session book what fell due ([LifecycleSession.returned]). A ledger
///   being closed is never written to.
/// - An inactive and resumed with no leave between (the notification
///   shade pulled down) is no leave and no return.
final class AppLifecycle {
  AppLifecycle(this._gate);

  final LockGate<Object> _gate;

  LifecycleSession? _session;

  /// Where the app stands now.
  LifecyclePhase get phase => _phase;
  var _phase = LifecyclePhase.present;

  /// The open ledger's session hears of leaving and coming back from now
  /// on; [detach] when it ends.
  void attach(LifecycleSession session) => _session = session;

  void detach(LifecycleSession session) {
    if (identical(_session, session)) _session = null;
  }

  /// The phone says the app is now in [state].
  void changed(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.hidden || AppLifecycleState.paused:
        _left();
      case AppLifecycleState.inactive:
        _back();
      case AppLifecycleState.resumed:
        _back();
        _resumed();
      case AppLifecycleState.detached:
        break;
    }
  }

  void _left() {
    if (_phase == LifecyclePhase.away) return;
    _phase = LifecyclePhase.away;
    _gate.left();
    if (!_gate.onErrand) _session?.leave();
  }

  void _back() {
    if (_phase != LifecyclePhase.away) return;
    final locks = _gate.returned();
    _phase = locks ? LifecyclePhase.locking : LifecyclePhase.returning;
  }

  void _resumed() {
    final phase = _phase;
    _phase = LifecyclePhase.present;
    if (phase != LifecyclePhase.returning || _gate.closing) return;
    _session?.returned();
  }
}
