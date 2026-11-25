import 'dart:async';

import 'package:expense_tracker/src/core/ledger/persistence/damage_report.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a report not acted on is told again at the next damage; once one '
      'is, no more (review 18)', () async {
    final answers = <Completer<bool>>[];
    final report = DamageReport()
      ..tell = (_) {
        final answer = Completer<bool>();
        answers.add(answer);
        return answer.future;
      };
    report('first');
    // Being told: no other meanwhile.
    report('meanwhile');
    expect(answers, hasLength(1));
    // No book open just then: not acted on.
    answers.single.complete(false);
    await pumpEventQueue();
    expect(report.told, isFalse);
    report('second');
    expect(answers, hasLength(2));
    answers.last.complete(true);
    await pumpEventQueue();
    expect(report.told, isTrue);
    report('third');
    expect(answers, hasLength(2));
  });

  test('a telling that fails is logged and not told again: no handling '
      'at every fault (review 25)', () async {
    var tries = 0;
    final report = DamageReport()
      ..tell = (_) async {
        tries++;
        throw StateError('read-only disk');
      };
    report('first');
    await pumpEventQueue();
    expect(report.told, isTrue);
    report('second');
    await pumpEventQueue();
    expect(tries, 1);
  });

  test('nobody to tell: nothing is told, and it is told once someone is', () {
    final report = DamageReport()..call('unheard');
    expect(report.told, isFalse);
    var told = 0;
    report
      ..tell = ((_) async {
        told++;
        return true;
      })
      ..call('heard');
    expect(told, 1);
  });
}
