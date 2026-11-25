import 'dart:async';

import '../../diagnostics/error_log.dart';
import '../../diagnostics/error_steps.dart';

/// Tells [tell] of damage found in the book until a telling is acted on
/// (review 18): one telling at a time, and none after one was acted on.
/// A telling not acted on (no book open just then, as while it locks)
/// leaves the next damage found to be told again, so it is not missed
/// until the next launch. A telling that throws counts as acted on, its
/// error logged: the handling already ran and showed what it could, and
/// running it again at every fault would only fail again (review 25).
final class DamageReport {
  /// Told of the damage; answers whether it was acted on.
  Future<bool> Function(Object error)? tell;

  /// Whether a telling was acted on: nothing more is told.
  bool get told => _told;
  var _told = false;

  /// A telling not answered yet: no other meanwhile.
  var _telling = false;

  /// Tells of [error], unless one was acted on or is being told.
  void call(Object error) {
    final tell = this.tell;
    if (_told || _telling || tell == null) return;
    _telling = true;
    unawaited(_tellOf(tell, error));
  }

  Future<void> _tellOf(
    Future<bool> Function(Object error) tell,
    Object error,
  ) async {
    try {
      _told = await tell(error);
    } on Object catch (failed, stack) {
      _told = true;
      ErrorLog.instance.record(ErrorSteps.bookDamaged, failed, stack);
    } finally {
      _telling = false;
    }
  }
}
