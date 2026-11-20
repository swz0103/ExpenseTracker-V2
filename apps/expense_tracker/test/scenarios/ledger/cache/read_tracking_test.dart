import 'package:expense_tracker/src/core/ledger/cache/query_cache.dart';
import 'package:expense_tracker/src/core/ledger/cache/topic.dart';
import 'package:expense_tracker/src/core/ledger/models/models.dart';
import 'package:expense_tracker/src/core/ledger/repositories/entry_repository.dart';
import 'package:expense_tracker/src/core/ledger/repositories/holding_repository.dart';
import 'package:expense_tracker/src/core/ledger/services/tracked_readers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('an answer rests on the topics its readers told of', () {
    final cache = QueryCache();
    cache.remember('k', () {
      cache.noteReads({Topic.entries});
      cache.noteReads({Topic.accounts});
      return 1;
    });
    expect(cache.readsOf('k'), {Topic.entries, Topic.accounts});
  });

  test('a topic named adds to those read', () {
    final cache = QueryCache();
    cache.remember('k', () {
      cache.noteReads({Topic.entries});
      return 1;
    }, reads: {Topic.recurring});
    expect(cache.readsOf('k'), {Topic.entries, Topic.recurring});
  });

  test('an answer asked for inside another passes on what it read', () {
    final cache = QueryCache();
    int inner() => cache.remember('inner', () {
      cache.noteReads({Topic.market});
      return 1;
    });
    cache.remember('outer', () {
      cache.noteReads({Topic.entries});
      return inner() + 1;
    });
    expect(cache.readsOf('outer'), {Topic.entries, Topic.market});
    // Asked again, the inner answer is kept, and still passes it on.
    cache.remember('outer2', () => inner());
    expect(cache.readsOf('outer2'), {Topic.market});
    // A change to what only the inner read throws both away.
    cache.forget({Topic.market});
    expect(cache.length, 0);
  });

  test('a read outside any answer is noted nowhere', () {
    final cache = QueryCache();
    cache.noteReads({Topic.entries});
    expect(cache.length, 0);
  });

  test('an answer that threw is not kept, and its reads end with it', () {
    final cache = QueryCache();
    expect(
      () => cache.remember<int>('k', () {
        cache.noteReads({Topic.entries});
        throw StateError('no');
      }),
      throwsStateError,
    );
    expect(cache.readsOf('k'), isNull);
    cache.remember('after', () {
      cache.noteReads({Topic.budgets});
      return 1;
    });
    expect(cache.readsOf('after'), {Topic.budgets});
  });

  test('a tracked reader tells of its topic on every read', () {
    final cache = QueryCache();
    final entries = TrackedEntryReader(
      EntryRepository([
        Entry(
          id: 'a',
          date: DateTime.utc(2026, 10, 1),
          type: EntryType.expense,
          amount: 1,
          account: 'bank',
          category: '飲食',
        ),
      ]),
      cache,
    );
    cache.remember('month', () => entries.inMonth(2026, 10));
    cache.remember('one', () => entries.byId('a'));
    expect(cache.readsOf('month'), {Topic.entries});
    expect(cache.readsOf('one'), {Topic.entries});
  });

  test('the holdings rest on the trades and the market data', () {
    final cache = QueryCache();
    final holdings = TrackedHoldingReader(
      HoldingRepository(const [], moveOf: (_) => null)..replay(const []),
      cache,
    );
    cache.remember('value', () => holdings.marketValue);
    expect(cache.readsOf('value'), {Topic.entries, Topic.market});
  });
}
