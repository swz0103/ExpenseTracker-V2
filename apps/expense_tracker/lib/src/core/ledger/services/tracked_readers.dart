import '../cache/query_cache.dart';
import '../cache/topic.dart';
import '../models/models.dart';
import '../repositories/entry_repository.dart';
import '../repositories/account_repository.dart';
import '../repositories/category_repository.dart';
import '../repositories/holding_repository.dart';
import '../repositories/market_data_repository.dart';
import '../repositories/recurring_repository.dart';

/// The readers a service is given, each telling [QueryCache] of every
/// read, so an answer the cache keeps is thrown away when what it was
/// worked out from changes, without a list of topics kept by hand.
///
/// Holdings rest on the trades and on the market data: a read of them
/// counts as a read of both.

/// A [EntryReader] that tells [QueryCache] it was read.
final class TrackedEntryReader implements EntryReader {
  TrackedEntryReader(this._inner, this._cache);

  final EntryReader _inner;
  final QueryCache _cache;

  static const _topics = {Topic.entries};

  @override
  List<Entry> get all {
    _cache.noteReads(_topics);
    return _inner.all;
  }

  @override
  int get length {
    _cache.noteReads(_topics);
    return _inner.length;
  }

  @override
  bool get isEmpty {
    _cache.noteReads(_topics);
    return _inner.isEmpty;
  }

  @override
  Entry? byId(String id) {
    _cache.noteReads(_topics);
    return _inner.byId(id);
  }

  @override
  List<Entry> inMonth(int year, int month) {
    _cache.noteReads(_topics);
    return _inner.inMonth(year, month);
  }

  @override
  List<Entry> onDay(DateTime day) {
    _cache.noteReads(_topics);
    return _inner.onDay(day);
  }

  @override
  int versionOf(String account) {
    _cache.noteReads(_topics);
    return _inner.versionOf(account);
  }

  @override
  int orderOf(String id) {
    _cache.noteReads(_topics);
    return _inner.orderOf(id);
  }

  @override
  Iterable<Entry> get byDate {
    _cache.noteReads(_topics);
    return _inner.byDate;
  }

  @override
  DateTime? get firstDate {
    _cache.noteReads(_topics);
    return _inner.firstDate;
  }

  @override
  int refundedTotal(String id) {
    _cache.noteReads(_topics);
    return _inner.refundedTotal(id);
  }

  @override
  List<Entry> refundsOf(String id) {
    _cache.noteReads(_topics);
    return _inner.refundsOf(id);
  }
}

/// A [AccountReader] that tells [QueryCache] it was read.
final class TrackedAccountReader implements AccountReader {
  TrackedAccountReader(this._inner, this._cache);

  final AccountReader _inner;
  final QueryCache _cache;

  static const _topics = {Topic.accounts};

  @override
  List<Account> get all {
    _cache.noteReads(_topics);
    return _inner.all;
  }

  @override
  List<Account> get open {
    _cache.noteReads(_topics);
    return _inner.open;
  }

  @override
  Account? byId(String id) {
    _cache.noteReads(_topics);
    return _inner.byId(id);
  }

  @override
  bool contains(String id) {
    _cache.noteReads(_topics);
    return _inner.contains(id);
  }

  @override
  Account resolve(String id) {
    _cache.noteReads(_topics);
    return _inner.resolve(id);
  }

  @override
  String get main {
    _cache.noteReads(_topics);
    return _inner.main;
  }
}

/// A [CategoryReader] that tells [QueryCache] it was read.
final class TrackedCategoryReader implements CategoryReader {
  TrackedCategoryReader(this._inner, this._cache);

  final CategoryReader _inner;
  final QueryCache _cache;

  static const _topics = {Topic.categories};

  @override
  List<Category> get all {
    _cache.noteReads(_topics);
    return _inner.all;
  }

  @override
  Category byName(String name) {
    _cache.noteReads(_topics);
    return _inner.byName(name);
  }

  @override
  List<Category> forEntries({required bool income}) {
    _cache.noteReads(_topics);
    return _inner.forEntries(income: income);
  }

  @override
  bool isNameFree(String name, {String? except}) {
    _cache.noteReads(_topics);
    return _inner.isNameFree(name, except: except);
  }
}

/// A [HoldingReader] that tells [QueryCache] it was read.
final class TrackedHoldingReader implements HoldingReader {
  TrackedHoldingReader(this._inner, this._cache);

  final HoldingReader _inner;
  final QueryCache _cache;

  static const _topics = {Topic.entries, Topic.market};

  @override
  List<Holding> get all {
    _cache.noteReads(_topics);
    return _inner.all;
  }

  @override
  Holding? byCode(String code) {
    _cache.noteReads(_topics);
    return _inner.byCode(code);
  }

  @override
  List<Holding> get every {
    _cache.noteReads(_topics);
    return _inner.every;
  }

  @override
  bool hasQuote(String code) {
    _cache.noteReads(_topics);
    return _inner.hasQuote(code);
  }

  @override
  List<Lot> lotsOf(String code) {
    _cache.noteReads(_topics);
    return _inner.lotsOf(code);
  }

  @override
  int saleCost(String code, int shares, {bool average = false}) {
    _cache.noteReads(_topics);
    return _inner.saleCost(code, shares, average: average);
  }

  @override
  int sharesOn(String code, DateTime day) {
    _cache.noteReads(_topics);
    return _inner.sharesOn(code, day);
  }

  @override
  int inTodaysShares(String code, DateTime day, int shares) {
    _cache.noteReads(_topics);
    return _inner.inTodaysShares(code, day, shares);
  }

  @override
  Holding? everByCode(String code) {
    _cache.noteReads(_topics);
    return _inner.everByCode(code);
  }

  @override
  int? saleCostWith(
    List<Entry> entries,
    String code,
    int shares, {
    bool average = false,
  }) {
    _cache.noteReads(_topics);
    return _inner.saleCostWith(entries, code, shares, average: average);
  }

  @override
  bool holdsWith(List<Entry> entries) {
    _cache.noteReads(_topics);
    return _inner.holdsWith(entries);
  }

  @override
  int get marketValue {
    _cache.noteReads(_topics);
    return _inner.marketValue;
  }

  @override
  int get costBasis {
    _cache.noteReads(_topics);
    return _inner.costBasis;
  }

  @override
  int get dayChange {
    _cache.noteReads(_topics);
    return _inner.dayChange;
  }

  @override
  int get realizedGain {
    _cache.noteReads(_topics);
    return _inner.realizedGain;
  }

  @override
  int get dividends {
    _cache.noteReads(_topics);
    return _inner.dividends;
  }
}

/// A [MarketDataReader] that tells [QueryCache] it was read.
final class TrackedMarketDataReader implements MarketDataReader {
  TrackedMarketDataReader(this._inner, this._cache);

  final MarketDataReader _inner;
  final QueryCache _cache;

  static const _topics = {Topic.market};

  @override
  DateTime? get quotedOn {
    _cache.noteReads(_topics);
    return _inner.quotedOn;
  }

  @override
  Map<String, double> get rates {
    _cache.noteReads(_topics);
    return _inner.rates;
  }

  @override
  Map<String, double> get sellRates {
    _cache.noteReads(_topics);
    return _inner.sellRates;
  }

  @override
  Map<String, double> get moves {
    _cache.noteReads(_topics);
    return _inner.moves;
  }

  @override
  Map<String, DateTime> get quoteDays {
    _cache.noteReads(_topics);
    return _inner.quoteDays;
  }

  @override
  double? rateOf(String currency) {
    _cache.noteReads(_topics);
    return _inner.rateOf(currency);
  }

  @override
  double? moveOf(String code) {
    _cache.noteReads(_topics);
    return _inner.moveOf(code);
  }

  @override
  DateTime? olderQuote(String code) {
    _cache.noteReads(_topics);
    return _inner.olderQuote(code);
  }

  @override
  int? toHome(int minor, String currency) {
    _cache.noteReads(_topics);
    return _inner.toHome(minor, currency);
  }

  @override
  int? valueAtHome(int balance, String currency) {
    _cache.noteReads(_topics);
    return _inner.valueAtHome(balance, currency);
  }

  @override
  int? convert(int amount, String from, String to) {
    _cache.noteReads(_topics);
    return _inner.convert(amount, from, to);
  }
}

/// A [RecurringReader] that tells [QueryCache] it was read.
final class TrackedRecurringReader implements RecurringReader {
  TrackedRecurringReader(this._inner, this._cache);

  final RecurringReader _inner;
  final QueryCache _cache;

  static const _topics = {Topic.recurring};

  @override
  List<Recurring> get all {
    _cache.noteReads(_topics);
    return _inner.all;
  }

  @override
  Recurring? byId(String id) {
    _cache.noteReads(_topics);
    return _inner.byId(id);
  }
}
