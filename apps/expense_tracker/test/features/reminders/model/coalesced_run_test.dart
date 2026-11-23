import 'dart:async';

import 'package:expense_tracker/src/features/reminders/model/coalesced_run.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('asks in one turn run it once', () async {
    var runs = 0;
    final run = CoalescedRun(() async => runs++);
    run
      ..ask()
      ..ask()
      ..ask();
    await run.idle;
    expect(runs, 1);
  });

  test(
    'asked while running, it runs once more after, never two at once',
    () async {
      var runs = 0;
      var running = 0;
      var most = 0;
      final gate = Completer<void>();
      final run = CoalescedRun(() async {
        runs++;
        running++;
        most = running > most ? running : most;
        if (runs == 1) await gate.future;
        running--;
      });
      run.ask();
      await Future<void>.delayed(Duration.zero);
      run
        ..ask()
        ..ask();
      gate.complete();
      await run.idle;
      expect(runs, 2);
      expect(most, 1);
    },
  );

  test('stopped, it runs no more', () async {
    var runs = 0;
    final run = CoalescedRun(() async => runs++)..ask();
    run.stop();
    run.ask();
    await run.idle;
    expect(runs, 0);
  });
}
