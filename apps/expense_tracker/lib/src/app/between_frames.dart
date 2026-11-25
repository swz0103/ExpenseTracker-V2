import 'dart:async';

import 'package:flutter/scheduler.dart';

/// Steps of work that can wait, each run between frames: [next] completes
/// after the frame under way, if any, is drawn, at a later turn of the
/// event loop, so a frame asked for meanwhile is drawn first; true to go
/// on, false once [stop]ped (the page that started the work is gone).
/// Not an idle task of the scheduler: one waits out every animation,
/// asking again at each turn of the event loop meanwhile.
final class BetweenFrames {
  var _stopped = false;
  Timer? _turn;
  Completer<bool>? _waiting;

  Future<bool> next() async {
    if (_stopped) return false;
    final scheduler = SchedulerBinding.instance;
    // endOfFrame asks for a frame when none is coming: waited for only
    // when one is.
    if (scheduler.hasScheduledFrame ||
        scheduler.schedulerPhase != SchedulerPhase.idle) {
      await scheduler.endOfFrame;
      if (_stopped) return false;
    }
    final waiting = _waiting = Completer<bool>();
    _turn = Timer(Duration.zero, () => waiting.complete(true));
    return waiting.future;
  }

  /// No step after this one: a step waited for is told to stop.
  void stop() {
    _stopped = true;
    _turn?.cancel();
    if (_waiting case final w? when !w.isCompleted) w.complete(false);
  }
}
