import 'package:app_core/app_core.dart';
import 'package:app_core/testing.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:test/test.dart';

final class _Append implements Command<int> {
  _Append(this.operation, this.text);

  @override
  final OperationKey operation;
  final String text;

  @override
  String get input => 'append-v1:$text';

  @override
  String encodeResult(int result) => '$result';

  @override
  int decodeResult(String encoded) => int.parse(encoded);
}

void main() {
  final workspace = WorkspaceId(PublicId.generate());
  OperationKey key() =>
      OperationKey(workspace, OperationId(PublicId.generate()));
  late MemoryStore store;
  late CommandRunner<MemoryTransaction> runner;
  var handled = 0;

  Future<int> append(MemoryTransaction transaction, String text) async {
    handled++;
    transaction.append(text);
    return transaction.events.length;
  }

  Future<CommandOutcome<int>> run(_Append command) =>
      runner.run(command, (transaction) => append(transaction, command.text));

  setUp(() {
    store = MemoryStore();
    runner = CommandRunner(store);
    handled = 0;
  });

  test('a retry returns the recorded result without running again', () async {
    final command = _Append(key(), 'a');
    final first = await run(command);
    final retry = await run(command);
    expect(first.value, 1);
    expect(first.replayed, isFalse);
    expect(retry.value, 1);
    expect(retry.replayed, isTrue);
    expect(handled, 1);
    expect(store.events, ['a']);
  });

  test('reusing a key with different input is a conflict', () async {
    final operation = key();
    await run(_Append(operation, 'a'));
    await expectLater(
      run(_Append(operation, 'b')),
      throwsA(const AppFailure.operationConflict()),
    );
    expect(store.events, ['a']);
    expect(handled, 1);
  });

  test('a failing handler commits nothing and can be retried', () async {
    final command = _Append(key(), 'a');
    await expectLater(
      runner.run(command, (transaction) async {
        transaction.append('partial');
        await transaction.enqueue(
          OutboxMessage(id: PublicId.generate(), topic: 't', payload: 'p'),
        );
        throw const AppFailure(FailureKind.rejected, 'test.refused');
      }),
      throwsA(const AppFailure(FailureKind.rejected, 'test.refused')),
    );
    expect(store.events, isEmpty);
    expect(store.outbox, isEmpty);
    final retry = await run(command);
    expect(retry.replayed, isFalse);
    expect(store.events, ['a']);
  });

  test('concurrent commands queue instead of overlapping or failing', () async {
    final outcomes = await Future.wait([
      for (var i = 0; i < 20; i++) run(_Append(key(), '$i')),
    ]);
    expect(outcomes.map((o) => o.value), [for (var i = 1; i <= 20; i++) i]);
    expect(store.events, [for (var i = 0; i < 20; i++) '$i']);
    expect(store.commits, 20);
  });

  test('a failure does not block the commands queued behind it', () async {
    final failing = runner.run(
      _Append(key(), 'x'),
      (_) async => throw const AppFailure(FailureKind.notFound, 'test.none'),
    );
    final next = run(_Append(key(), 'b'));
    await expectLater(failing, throwsA(isA<AppFailure>()));
    expect((await next).value, 1);
  });

  test('outbox messages appear only when their transaction commits', () async {
    final message = OutboxMessage(
      id: PublicId.generate(),
      topic: 'backup.requested',
      payload: '{}',
    );
    await runner.run(_Append(key(), 'a'), (transaction) async {
      await transaction.enqueue(message);
      expect(store.outbox, isEmpty);
      return 0;
    });
    expect(store.outbox.single.id, message.id);
  });

  test('fixed clock moves only when advanced', () {
    final clock = FixedClock(UtcInstant(DateTime.utc(2026, 10, 3, 8)));
    expect(clock.now(), UtcInstant(DateTime.utc(2026, 10, 3, 8)));
    clock.advance(const Duration(minutes: 5));
    expect(clock.now(), UtcInstant(DateTime.utc(2026, 10, 3, 8, 5)));
  });
}
