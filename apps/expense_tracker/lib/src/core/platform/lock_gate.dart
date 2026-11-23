import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:vault/ledger_vault.dart' show OpenVault;

import '../diagnostics/error_log.dart';
import 'away_clock.dart';
import 'errands.dart';
import 'preferences.dart';
import 'quick_action.dart';
import 'startup.dart';

/// The one gate above every screen: it decides whether the ledger may be
/// seen, and everything that would show it goes through here.
///
/// - **What is on screen.** Each opening of a ledger is a [session]; when
///   it ends (the ledger locks, or opens afresh on new keys) [generation]
///   moves on and the app replaces every route, sheet and dialog with it,
///   so nothing of a closed ledger stays in the widget tree. While the
///   app is off the screen and may have to lock, and while it is locking,
///   [covered] is true and the app draws nothing of the ledger.
/// - **Auto-lock.** [left] starts the clock when the app leaves the
///   screen; [returned] decides, before a frame of the ledger is drawn,
///   whether the person's [AutoLock] choice has run out, and locks.
/// - **Ways in.** A home-screen shortcut, the widget and a notification
///   hand their [QuickAction] to [ask]; it reaches the screens ([quick])
///   only once a ledger is open and in front, so while locked the person
///   unlocks first and then lands on the form asked for.
///
/// It listens to [startup], so a lock from anywhere (settings, a restore,
/// new keys) is followed the same way.
///
/// [Place] is what names a page of the app (the app's routes); the gate
/// only keeps one and hands it back, so it need not know what pages are.
final class LockGate<Place extends Object> extends ChangeNotifier {
  LockGate(
    this.startup, {
    required this._autoLock,
    AwayClock? clock,
    bool Function()? onErrand,
  }) : _clock = clock ?? AwayClock(),
       _onErrand = onErrand ?? (() => Errands.any) {
    _session = _sessionOf(startup.state);
    startup.addListener(_follow);
  }

  final Startup startup;

  /// The person's choice of how long away locks the ledger, read each
  /// time the app comes back.
  final AutoLock Function() _autoLock;

  /// How long the app was away, by a clock that cannot be set back.
  final AwayClock _clock;

  /// Whether the app itself sent the person away (see [Errands]).
  final bool Function() _onErrand;

  /// What is open: the open vault itself, or the kind of closed state.
  /// Routes belong to one and go with it.
  Object get session => _session;
  late Object _session;

  /// Counts the sessions; the app keys its navigator by it.
  int get generation => _generation;
  var _generation = 0;

  static Object _sessionOf(StartupState state) => switch (state) {
    Ready(:final vault) => vault,
    _ => state.runtimeType,
  };

  bool get _open => _session is OpenVault;

  /// The app is off the screen since [left].
  var _away = false;

  /// Whether that trip away was one the app started.
  var _errand = false;

  /// Whether the app is away on a trip it started itself (see [Errands]),
  /// as told at [left].
  bool get onErrand => _away && _errand;

  /// The ledger is being closed: pending changes are kept first.
  var _closing = false;

  /// Whether leaving the screen may end in a lock: a ledger with a
  /// password is open and the choice is not "never", or keys are held for
  /// a restore.
  bool get _mayLock =>
      startup.canResume ||
      (_open && !startup.passwordless && _autoLock().after != null);

  /// Whether the app must draw nothing of the ledger now: it is being
  /// closed, or it is off the screen and may have to lock when back.
  bool get covered => _closing || (_away && _mayLock);

  /// Whether the ledger is being closed, so nothing new should start on
  /// it.
  bool get closing => _closing;

  /// What the screens act on: set only while a ledger is open and in
  /// front, and set back to null by the screen that acts on it.
  final quick = ValueNotifier<QuickAction?>(null);

  /// An action waiting for the ledger to be open and in front.
  QuickAction? _pending;

  /// A shortcut, the widget or a notification asked for [action]. It is
  /// kept until a ledger is open and in front; the newest one wins.
  void ask(QuickAction action) {
    _pending = action;
    _deliver();
  }

  void _deliver() {
    final pending = _pending;
    if (pending == null || !_open || _away || _closing) return;
    _pending = null;
    quick.value = pending;
  }

  /// How the open session closes itself, keeping pending changes first;
  /// set by the session while it lasts.
  Future<void> Function()? _lock;

  /// The open session's own way to lock (it settles what is being written
  /// first); [detach] when it ends.
  void attach(Future<void> Function() lock) => _lock = lock;

  void detach(Future<void> Function() lock) {
    if (_lock == lock) _lock = null;
  }

  /// The page the open ledger shows over its tabs, told by the app frame.
  Place? place;

  /// Where to go back to once the ledger reopens after a restore was
  /// given up.
  Place? _returnTo;

  /// The page the person was on when they left for a restore they then
  /// gave up, once; null otherwise.
  Place? takeReturn() {
    final to = _returnTo;
    _returnTo = null;
    return to;
  }

  void _follow() {
    final session = _sessionOf(startup.state);
    if (identical(session, _session)) return;
    _session = session;
    _generation++;
    _closing = false;
    if (_open) {
      // Only a ledger reopened as it was goes back to where it was left.
      if (!startup.takeResumed()) _returnTo = null;
    } else {
      // An action not acted on yet waits for the next opening.
      _pending ??= quick.value;
      quick.value = null;
      _returnTo = startup.canResume ? place : null;
    }
    place = null;
    _deliver();
    notifyListeners();
  }

  /// The app left the screen (hidden or paused); the first call counts.
  void left() {
    if (_away) return;
    _away = true;
    _errand = _onErrand();
    _clock.leave();
    if (_mayLock) notifyListeners();
  }

  /// The app is coming back to the screen: decides at once whether the
  /// ledger locks, before anything of it is drawn. True when it locks.
  bool returned() {
    if (!_away) return false;
    _away = false;
    final limit = _autoLock().limit(onErrand: _errand);
    // Asked even for "never", so the clock starts afresh next time.
    final longEnough = _clock.back(limit ?? Duration.zero) && limit != null;
    if (longEnough && _mayLock) {
      unawaited(lock());
      notifyListeners();
      return true;
    }
    _deliver();
    notifyListeners();
    return false;
  }

  /// Locks now: the ledger is covered at once, its pending changes are
  /// kept, then it closes. Keys held for a restore are let go.
  Future<void> lock() async {
    if (!_open) {
      if (startup.canResume) startup.lock();
      return;
    }
    if (_closing) return;
    _closing = true;
    notifyListeners();
    final session = _session;
    try {
      await _lock?.call();
    } on Object catch (error) {
      ErrorLog.instance.record('上鎖', error);
    }
    // Closed whatever happened to the changes: never left open.
    if (identical(_session, session)) startup.lock();
  }

  @override
  void dispose() {
    startup.removeListener(_follow);
    quick.dispose();
    super.dispose();
  }
}
