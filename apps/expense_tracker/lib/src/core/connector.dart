import 'package:flutter/foundation.dart';

import 'perf.dart';

/// Something the app fetches or sends outside the phone, such as closing
/// prices or a backup on Google Drive: whether it is at work, when it last
/// worked, and why it did not. A failure is never kept quiet: it is noted
/// for 效能與診斷 and shown where the connector's data is shown.
abstract class Connector extends ChangeNotifier {
  Connector(this.label, {this.gap = Duration.zero, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  /// What it is called on screen and in the diagnostics, such as 收盤價.
  final String label;

  /// How long after a run another waits, unless asked for outright.
  final Duration gap;

  final DateTime Function() _clock;

  bool get busy => _busy;
  var _busy = false;

  /// When it last worked.
  DateTime? get lastSuccess => _lastSuccess;
  DateTime? _lastSuccess;

  /// Why the last run did not work, in words for the person; null when
  /// it did.
  String? get problem => _problem;
  String? _problem;

  DateTime? _lastTry;

  /// Fetches or sends now; without [force], only when [gap] has passed
  /// since the last try.
  Future<void> refresh({bool force = false});

  /// Runs [work] as one try. [work] returns a problem to show, or null
  /// when all went well; a thrown error is shown as [failure].
  @protected
  Future<void> attempt(
    Future<String?> Function() work, {
    required bool force,
    String failure = '沒有連上，稍後再試',
  }) async {
    final last = _lastTry;
    if (_busy || (!force && last != null && _clock().difference(last) < gap)) {
      return;
    }
    _busy = true;
    _lastTry = _clock();
    notifyListeners();
    try {
      _problem = await work();
      _lastSuccess = _clock();
    } on Object catch (error) {
      Perf.instance.problem(label, error);
      _problem = failure;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
