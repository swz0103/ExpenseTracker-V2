import 'package:flutter/foundation.dart';

import '../diagnostics/error_log.dart';
import '../time/app_clock.dart';

/// Something the app fetches or sends outside the phone, such as closing
/// prices or a backup on Google Drive: whether it is at work, when it last
/// worked, and why it did not. A failure is never kept quiet: it is noted
/// for 效能與診斷 and shown where the connector's data is shown.
abstract class SyncJob extends ChangeNotifier {
  SyncJob(this.label, {this.gap = Duration.zero, DateTime Function()? clock})
    : _clock = clock ?? AppClock.now;

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
      ErrorLog.instance.record(label, error);
      _problem = failure;
    } finally {
      _busy = false;
      // Let go while at work (the ledger locked): no one is told.
      if (!_gone) notifyListeners();
    }
  }

  /// Let go: a try under way ends without telling anyone.
  var _gone = false;

  @override
  void dispose() {
    _gone = true;
    super.dispose();
  }
}

/// A holding's daily closes, for its chart: what the exchanges answered,
/// kept on the phone once read. The preview has none.
abstract interface class PriceHistory {
  Future<List<(DateTime, double)>> history(String code, DateTime from);
}
