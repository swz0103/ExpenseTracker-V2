/// Checks that every read through a tracked reader answers as the reader
/// it wraps does and tells the cache which part of the ledger it read, so
/// an answer worked out from it is thrown away when, and only when, that
/// part changes.
library;

import 'package:expense_tracker/src/core/ledger/cache/query_cache.dart';
import 'package:expense_tracker/src/core/ledger/cache/topic.dart';
import 'package:expense_tracker/src/core/ledger/models/models.dart';
import 'package:expense_tracker/src/core/ledger/repositories/account_repository.dart';
import 'package:expense_tracker/src/core/ledger/repositories/category_repository.dart';
import 'package:expense_tracker/src/core/ledger/repositories/entry_repository.dart';
import 'package:expense_tracker/src/core/ledger/repositories/holding_repository.dart';
import 'package:expense_tracker/src/core/ledger/repositories/market_data_repository.dart';
import 'package:expense_tracker/src/core/ledger/repositories/recurring_repository.dart';
import 'package:expense_tracker/src/core/ledger/services/tracked_readers.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/book.dart';

void main() {
  /// The topics [read] rests on, as the cache keeps them, and its answer.
  (Set<Topic>?, Object?) traced(Object? Function(QueryCache) read) {
    final cache = QueryCache();
    final answer = cache.remember('k', () => read(cache));
    return (cache.readsOf('k'), answer);
  }

  final buy = Entry(
    id: 'buy',
    date: day,
    type: EntryType.buy,
    amount: 9000,
    account: 'bank',
    holding: '2330',
    shares: 10,
  );
  final lunch = entry('lunch', amount: 120);
  final entries = EntryRepository([buy, lunch]);
  final accounts = AccountRepository(const [
    Account('bank', '銀行', AccountKind.bank, 1000),
  ]);
  final categories = CategoryRepository();
  final market = MarketDataRepository(
    rates: const {'USD': 32.0},
    moves: const {'2330': 2.0},
    quotedOn: day,
    quoteDays: {'2330': day},
  );
  final holdings = HoldingRepository(const [
    Holding('2330', '台積電', shares: 0, price: 1000, cost: 0, change: 0),
  ], moveOf: market.moveOf)..replay(entries.all, today: day);
  final recurring = RecurringRepository(const [
    Recurring(
      id: 'r',
      name: 'Netflix',
      amount: 390,
      day: 5,
      account: 'bank',
      category: '娛樂',
    ),
  ]);

  test('reading entries rests on the entries alone, with the same answers', () {
    final reads = <String, Object? Function(EntryReader)>{
      'all': (r) => r.all,
      'length': (r) => r.length,
      'isEmpty': (r) => r.isEmpty,
      'byId': (r) => r.byId('lunch'),
      'inMonth': (r) => r.inMonth(day.year, day.month),
      'onDay': (r) => r.onDay(day),
      'byDate': (r) => r.byDate.toList(),
      'firstDate': (r) => r.firstDate,
      'refundedTotal': (r) => r.refundedTotal('lunch'),
    };
    for (final MapEntry(:key, value: read) in reads.entries) {
      final (topics, answer) = traced(
        (cache) => read(TrackedEntryReader(entries, cache)),
      );
      expect(topics, {Topic.entries}, reason: key);
      expect(answer, read(entries), reason: key);
    }
  });

  test('reading accounts rests on the accounts alone', () {
    final reads = <String, Object? Function(AccountReader)>{
      'all': (r) => r.all,
      'open': (r) => r.open,
      'byId': (r) => r.byId('bank'),
      'contains': (r) => r.contains('bank'),
      'resolve': (r) => r.resolve('bank').name,
      'main': (r) => r.main,
    };
    for (final MapEntry(:key, value: read) in reads.entries) {
      final (topics, answer) = traced(
        (cache) => read(TrackedAccountReader(accounts, cache)),
      );
      expect(topics, {Topic.accounts}, reason: key);
      expect(answer, read(accounts), reason: key);
    }
  });

  test('reading categories rests on the categories alone', () {
    final reads = <String, Object? Function(CategoryReader)>{
      'all': (r) => r.all.length,
      'byName': (r) => r.byName('飲食').name,
      'forEntries': (r) => r.forEntries(income: false).length,
      'isNameFree': (r) => r.isNameFree('新的'),
    };
    for (final MapEntry(:key, value: read) in reads.entries) {
      final (topics, answer) = traced(
        (cache) => read(TrackedCategoryReader(categories, cache)),
      );
      expect(topics, {Topic.categories}, reason: key);
      expect(answer, read(categories), reason: key);
    }
  });

  test('reading holdings rests on both the trades and the market', () {
    final reads = <String, Object? Function(HoldingReader)>{
      'all': (r) => r.all.map((h) => h.shares).toList(),
      'byCode': (r) => r.byCode('2330')?.shares,
      'hasQuote': (r) => r.hasQuote('2330'),
      'lotsOf': (r) => r.lotsOf('2330').length,
      'saleCost': (r) => r.saleCost('2330', 4),
      'sharesOn': (r) => r.sharesOn('2330', day),
      'inTodaysShares': (r) => r.inTodaysShares('2330', day, 10),
      'everByCode': (r) => r.everByCode('2330')?.shares,
      'reshapedAfter': (r) => r.reshapedAfter('2330', day),
      'holdsWith': (r) => r.holdsWith([buy]),
      'marketValue': (r) => r.marketValue,
      'costBasis': (r) => r.costBasis,
      'dayChange': (r) => r.dayChange,
      'realizedGain': (r) => r.realizedGain,
      'dividends': (r) => r.dividends,
    };
    for (final MapEntry(:key, value: read) in reads.entries) {
      final (topics, answer) = traced(
        (cache) => read(TrackedHoldingReader(holdings, cache)),
      );
      expect(topics, {Topic.entries, Topic.market}, reason: key);
      expect(answer, read(holdings), reason: key);
    }
    expect(holdings.byCode('2330')?.shares, 10);
  });

  test('reading the market rests on the market alone', () {
    final reads = <String, Object? Function(MarketDataReader)>{
      'quotedOn': (r) => r.quotedOn,
      'rates': (r) => r.rates,
      'moves': (r) => r.moves,
      'quoteDays': (r) => r.quoteDays,
      'rateOf': (r) => r.rateOf('USD'),
      'moveOf': (r) => r.moveOf('2330'),
      'olderQuote': (r) => r.olderQuote('2330'),
      'toHome': (r) => r.toHome(100, 'USD'),
      'convert': (r) => r.convert(100, 'USD', 'TWD'),
    };
    for (final MapEntry(:key, value: read) in reads.entries) {
      final (topics, answer) = traced(
        (cache) => read(TrackedMarketDataReader(market, cache)),
      );
      expect(topics, {Topic.market}, reason: key);
      expect(answer, read(market), reason: key);
    }
  });

  test('reading recurring items rests on them alone', () {
    final reads = <String, Object? Function(RecurringReader)>{
      'all': (r) => r.all.map((x) => x.name).toList(),
      'byId': (r) => r.byId('r')?.name,
    };
    for (final MapEntry(:key, value: read) in reads.entries) {
      final (topics, answer) = traced(
        (cache) => read(TrackedRecurringReader(recurring, cache)),
      );
      expect(topics, {Topic.recurring}, reason: key);
      expect(answer, read(recurring), reason: key);
    }
  });

  test('an answer read through a tracked reader is worked out again only '
      'when what it read changes', () {
    final cache = QueryCache();
    final reader = TrackedEntryReader(entries, cache);
    var made = 0;
    int count() {
      made++;
      return reader.length;
    }

    expect(cache.remember('n', count), 2);
    cache.forget({Topic.budgets, Topic.accounts});
    cache.remember('n', count);
    expect(made, 1);
    cache.forget({Topic.entries});
    cache.remember('n', count);
    expect(made, 2);
  });

  test('a read made outside any answer is not kept anywhere', () {
    final cache = QueryCache();
    expect(TrackedAccountReader(accounts, cache).main, 'bank');
    expect(cache.length, 0);
  });
}
