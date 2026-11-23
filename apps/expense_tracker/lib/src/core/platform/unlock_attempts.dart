import 'dart:convert';
import 'dart:io';

import 'package:vault/backup_security.dart';

import '../diagnostics/error_log.dart';
import '../formatting/json_fields.dart';
import '../time/app_clock.dart';

/// Time since the phone started, which no setting can move: `boot` names
/// this start of the phone, `up` is how long it has run, sleep included.
typedef Uptime = ({String boot, Duration up});

/// Reads the phone's [Uptime]; null where there is no such clock.
typedef UptimeSource = Future<Uptime?> Function();

/// The wrong passwords and recovery codes typed in a row on the lock
/// screen, kept in a file beside the keyring (not in the encrypted book,
/// which is shut while they are typed), so closing the app does not start
/// the count again. How long each further one makes the next wait is the
/// vault's [AttemptPolicy]; this counts, keeps and reads the clocks.
///
/// The wait is measured so that changing the phone's clock never shortens
/// it:
///
/// - while the phone has not been restarted, by its [Uptime] alone, which
///   runs on whatever the clock is set to;
/// - after a restart of the phone (or where there is no such clock), by
///   the wall clock against the kept "not before" time. A clock set back
///   would make that longer than the policy's wait: the whole wait then
///   starts again from now. In real time that is the later of the kept
///   "not before" and now plus what was left, so setting the clock back
///   and forth gains nothing, and a clock corrected by a day does not
///   lock the person out for a day.
///
/// What is left open: setting the clock forward and restarting the phone
/// ends a wait early. That needs the phone itself unlocked and restarted
/// for each few tries.
final class UnlockAttempts {
  UnlockAttempts(
    this._file, {
    this.policy = AttemptPolicy.standard,
    DateTime Function()? now,
    this._uptime,
  }) : _now = now ?? AppClock.now {
    _load();
  }

  final File _file;

  /// How long each count of wrong tries waits.
  final AttemptPolicy policy;
  final DateTime Function() _now;
  final UptimeSource? _uptime;

  /// The wrong tries in a row since the ledger last opened.
  int get failures => _failures;
  var _failures = 0;

  /// The wall-clock time the next try may be made at.
  DateTime? _notBefore;

  /// The phone's start the wait was measured in, and its uptime the next
  /// try may be made at.
  String? _boot;
  Duration? _readyUp;

  void _load() {
    if (!_file.existsSync()) return;
    try {
      final json = JsonFields.decode(_file.readAsStringSync());
      _failures = json.whole('failures') ?? 0;
      _notBefore = DateTime.tryParse(json.text('notBefore') ?? '');
      _boot = json.text('boot');
      final ready = json.whole('readyUpMs');
      _readyUp = ready == null ? null : Duration(milliseconds: ready);
    } on Object catch (error) {
      ErrorLog.instance.record('解鎖次數', error);
    }
  }

  void _save() {
    try {
      _file.parent.createSync(recursive: true);
      // Written beside, then renamed over: never half a count.
      final next = File('${_file.path}.new');
      next.writeAsStringSync(
        jsonEncode({
          'failures': _failures,
          'notBefore': _notBefore?.toUtc().toIso8601String(),
          'boot': _boot,
          'readyUpMs': _readyUp?.inMilliseconds,
        }),
        flush: true,
      );
      next.renameSync(_file.path);
    } on Object catch (error) {
      // Kept in memory for this run.
      ErrorLog.instance.record('解鎖次數', error);
    }
  }

  /// The uptime could not be read once: noted once, and the wall clock
  /// is used for the rest of this run.
  var _noUptime = false;

  Future<Uptime?> _readUptime() async {
    if (_noUptime) return null;
    try {
      return await _uptime?.call();
    } on Object catch (error) {
      _noUptime = true;
      ErrorLog.instance.record('解鎖次數', error);
      return null;
    }
  }

  /// How long until the next try may be made; zero when it may be now.
  Future<Duration> wait() async {
    final whole = policy.waitAfter(_failures);
    if (whole == Duration.zero) return Duration.zero;
    final uptime = await _readUptime();
    final ready = _readyUp;
    if (uptime != null && uptime.boot == _boot && ready != null) {
      // The phone has run on since the wrong try: its uptime says how
      // long, whatever its clock was set to meanwhile.
      final left = ready - uptime.up;
      if (left <= whole) return left.isNegative ? Duration.zero : left;
    }
    final now = _now();
    final kept = _notBefore;
    var left = kept?.difference(now) ?? whole;
    // A clock set back (or a time that cannot be read): the whole wait
    // again from now, which is never sooner than the wait that was left.
    if (left > whole) left = whole;
    if (left.isNegative) left = Duration.zero;
    final notBefore = now.add(left);
    final readyUp = uptime == null ? null : uptime.up + left;
    final moved = kept == null || !notBefore.isAtSameMomentAs(kept);
    if (moved || uptime?.boot != _boot) {
      // From here on measured in this start of the phone.
      _notBefore = notBefore;
      _boot = uptime?.boot;
      _readyUp = readyUp;
      _save();
    }
    return left;
  }

  /// Counts one more wrong try, and returns how long the next one waits.
  Future<Duration> failed() async {
    _failures++;
    final whole = policy.waitAfter(_failures);
    final uptime = await _readUptime();
    _notBefore = _now().add(whole);
    _boot = uptime?.boot;
    _readyUp = uptime == null ? null : uptime.up + whole;
    _save();
    return whole;
  }

  /// The ledger opened: the count starts again.
  void clear() {
    _failures = 0;
    _notBefore = null;
    _boot = null;
    _readyUp = null;
    try {
      if (_file.existsSync()) _file.deleteSync();
    } on FileSystemException catch (error) {
      ErrorLog.instance.record('解鎖次數', error);
    }
  }
}
