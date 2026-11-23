import 'dart:async';

import 'package:expense_tracker/src/core/platform/one_at_a_time.dart';
import 'package:flutter_test/flutter_test.dart';

/// The backups kept on leaving never run twice at once (ARC-05), and a
/// leave while they run is not lost.
void main() {
  test('asked for while it runs: never beside it, once more after it, '
      'however often it was asked', () async {
    var started = 0;
    var running = 0;
    var most = 0;
    final gates = <Completer<void>>[];
    final work = OneAtATime(() async {
      started++;
      running++;
      most = running > most ? running : most;
      final gate = Completer<void>();
      gates.add(gate);
      await gate.future;
      running--;
    });
    final first = work.run();
    final second = work.run();
    final third = work.run();
    expect(work.running, isTrue);
    expect(started, 1);
    gates[0].complete();
    await pumpEventQueue();
    // Two asked for meanwhile: one more run, not two.
    expect(started, 2);
    gates[1].complete();
    await Future.wait([first, second, third]);
    expect(started, 2);
    expect(most, 1);
    expect(work.running, isFalse);
  });

  test('asked for again once done, it runs again', () async {
    var started = 0;
    final work = OneAtATime(() async => started++);
    await work.run();
    await work.run();
    expect(started, 2);
  });

  test('a run that fails ends the turn; the next one asked for runs', () async {
    var started = 0;
    final work = OneAtATime(() async {
      started++;
      if (started == 1) throw StateError('disk full');
    });
    await expectLater(work.run(), throwsStateError);
    expect(work.running, isFalse);
    await work.run();
    expect(started, 2);
  });
}
