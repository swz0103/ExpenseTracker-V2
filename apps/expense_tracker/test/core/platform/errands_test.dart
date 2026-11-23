import 'dart:async';

import 'package:expense_tracker/src/core/platform/errands.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a trip is under way from its start until the person is back', () async {
    expect(Errands.any, isFalse);
    final back = Completer<String>();
    final trip = Errands.run(() => back.future);
    expect(Errands.any, isTrue);
    back.complete('photo.jpg');
    expect(await trip, 'photo.jpg');
    expect(Errands.any, isFalse);
  });

  test('a trip that fails is over too', () async {
    await expectLater(
      Errands.run<void>(() async => throw StateError('no camera')),
      throwsStateError,
    );
    expect(Errands.any, isFalse);
  });

  test('two trips at once are over when both are', () async {
    final first = Completer<void>();
    final second = Completer<void>();
    final a = Errands.run(() => first.future);
    final b = Errands.run(() => second.future);
    first.complete();
    await a;
    expect(Errands.any, isTrue);
    second.complete();
    await b;
    expect(Errands.any, isFalse);
  });
}
