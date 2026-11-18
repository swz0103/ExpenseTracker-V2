import 'dart:async';

import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/ledger/persistence/ledger_data_source.dart';
import 'package:expense_tracker/src/core/ledger/persistence/write_queue.dart';
import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter_test/flutter_test.dart';

/// A data source that records what it is given and can be made to refuse.
final class _Source implements LedgerDataSource {
  _Source(this.fresh);

  final Ledger fresh;
  final kept = <String>[];
  var loads = 0;
  var failNext = 0;
  var failLoad = false;

  /// Held by a test to make [keep] take time.
  Completer<void>? hold;

  @override
  Future<void> keep(WriteBatch batch) async {
    await hold?.future;
    if (failNext > 0) {
      failNext--;
      throw const DataSourceException('closed');
    }
    kept.add([for (final e in batch.entries) e.id].join(','));
  }

  @override
  Future<Ledger> load() async {
    loads++;
    if (failLoad) throw const DataSourceException('unreadable');
    return fresh;
  }
}

void main() {
  late Ledger fresh;
  late _Source source;
  late ValueNotifier<LedgerProblem?> problem;
  late List<Ledger> reloaded;
  late WriteQueue queue;

  WriteBatch one(String id) => WriteBatch(
    entries: [
      Entry(
        id: id,
        date: DateTime.utc(2026, 10, 4),
        type: EntryType.expense,
        amount: 10,
        account: 'a',
      ),
    ],
  );

  setUp(() {
    fresh = Ledger(
      today: DateTime.utc(2026, 10, 4),
      accounts: const [Account('a', 'A', AccountKind.bank, 0)],
      categories: [],
      entries: const [],
      holdings: const [],
      budgets: const [],
      recurring: const [],
    );
    source = _Source(fresh);
    problem = ValueNotifier<LedgerProblem?>(null);
    reloaded = [];
    queue = WriteQueue(source, problem: problem, onReloaded: reloaded.add);
  });

  test('changes reach the data source in the order they were made', () async {
    queue.enqueue(one('1'));
    queue.enqueue(one('2'));
    queue.enqueue(one('3'));
    await queue.settled;
    expect(source.kept, ['1', '2', '3']);
    expect(problem.value, isNull);
    expect(source.loads, 0);
    expect(reloaded, isEmpty);
  });

  test('a change with nothing in it is not sent', () async {
    queue.enqueue(WriteBatch());
    await queue.settled;
    expect(source.kept, isEmpty);
  });

  test('a refused change is reported, then the book is read back', () async {
    source.failNext = 1;
    queue.enqueue(one('1'));
    await queue.settled;
    expect(
      problem.value,
      isA<KeepFailed>().having(
        (p) => p.cause,
        'cause',
        isA<DataSourceException>(),
      ),
    );
    expect(source.loads, 1);
    expect(reloaded, [fresh]);
  });

  test('the book is read back once nothing else is waiting', () async {
    source.failNext = 1;
    source.hold = Completer<void>();
    queue.enqueue(one('1')); // refused
    queue.enqueue(one('2'));
    queue.enqueue(one('3'));
    source.hold!.complete();
    await queue.settled;
    expect(source.kept, ['2', '3']);
    // One read after the last, not one for the refusal in the middle.
    expect(source.loads, 1);
    expect(reloaded, hasLength(1));
  });

  test('a change made while the book is read is not lost', () async {
    source.failNext = 1;
    queue.enqueue(one('1'));
    // Enqueued before the first has finished: its own turn comes first,
    // so the read-back waits until it has been kept as well.
    queue.enqueue(one('2'));
    await queue.settled;
    expect(source.kept, ['2']);
    expect(source.loads, 1);
  });

  test('a book that cannot be read back is reported and tried again', () async {
    source.failNext = 1;
    source.failLoad = true;
    queue.enqueue(one('1'));
    await queue.settled;
    expect(
      problem.value,
      isA<ReloadFailed>().having(
        (p) => p.cause,
        'cause',
        isA<DataSourceException>(),
      ),
    );
    expect(reloaded, isEmpty);

    // The next change finds the screens still ahead, and reads again.
    source.failLoad = false;
    queue.enqueue(one('2'));
    await queue.settled;
    expect(source.kept, ['2']);
    expect(reloaded, [fresh]);
  });

  test('settled completes once every change has been kept', () async {
    source.hold = Completer<void>();
    queue.enqueue(one('1'));
    var done = false;
    unawaited(queue.settled.then((_) => done = true));
    await Future<void>.delayed(Duration.zero);
    expect(done, isFalse);
    source.hold!.complete();
    await queue.settled;
    expect(done, isTrue);
  });

  test('a good change after a refused one is still kept', () async {
    source.failNext = 1;
    queue.enqueue(one('1'));
    await queue.settled;
    queue.enqueue(one('2'));
    await queue.settled;
    expect(source.kept, ['2']);
  });
}
