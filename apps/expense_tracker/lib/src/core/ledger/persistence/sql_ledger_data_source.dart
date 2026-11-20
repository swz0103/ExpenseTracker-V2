// Exception to ledger words: a new book's first categories and accounts
// are written as data, and the diagnostics log is labelled in words.

import 'dart:convert';
import 'dart:isolate';

import 'package:core/app_core.dart';
import 'package:core/foundation_values.dart';
import 'package:flutter/foundation.dart' show mapEquals;
import 'package:market/market_data.dart';
import 'package:storage/storage.dart';

import 'ledger_data_source.dart';
import '../ledger.dart';
import 'category_id_migration.dart';
import 'codec/category_refs.dart';
import 'record_version.dart';
import 'codec/record_json.dart';
import '../../diagnostics/performance_monitor.dart';
import '../../diagnostics/error_log.dart';

/// The categories a new ledger starts with, with their marks and colours.
const _starters = [
  ('居家生活', 'home', 0xFF5C9A83, false),
  ('飲食日常', 'food', 0xFFD08B5B, false),
  ('交通通勤', 'travel', 0xFF5B8DB0, false),
  ('購物休閒', 'bag', 0xFF8E7CC0, false),
  ('訂閱服務', 'subscription', 0xFFC9A34A, false),
  ('其他支出', 'other', 0xFFB07A8C, false),
  ('薪資收入', 'salary', 0xFF2F7A65, true),
  (dividendCategory, 'dividend', 0xFF5A6FA8, true),
  ('其他收入', 'income', 0xFF4E8A9A, true),
];

/// How long a deleted entry is kept to be restored.
const _keptInTrash = Duration(days: 30);

/// The collection of the last closing prices and rate board, kept so holdings
/// and foreign accounts are valued offline.
const _market = 'market';

/// When each record was deleted, by `collection/id`, so a deletion can be told
/// from a record never kept (for a later sync); dropped when the id is
/// kept again.
const _gone = 'gone';

/// Forms put aside in the composer, by tab ([WriteBatch.drafts]).
const _draft = 'draft';

/// The collections whose deletions are noted in [_gone].
const _noted = {
  Collection.account,
  Collection.category,
  Collection.entry,
  Collection.budget,
  Collection.recurring,
};

List<Object?> _decodeAll(List<String> bodies) => [
  for (final body in bodies) jsonDecode(body),
];

/// [_decodeAll] on a worker isolate. Kept out of the methods of the data
/// source: a closure made beside one that uses `this` carries it along,
/// and the database cannot be sent to another isolate.
Future<List<Object?>> _decodeApartFrom(List<String> bodies) =>
    Isolate.run(() => _decodeAll(bodies));

/// Above this many rows the JSON is decoded on a worker isolate, so the
/// screen does not freeze while a large book opens.
const _decodeApart = 2000;

/// How many rows a book is read at a time when it opens.
const readPage = 5000;

/// The book kept in the encrypted ledger: each of the screens' records a
/// row of JSON, written as the [Ledger] hands over each change.
final class SqlLedgerDataSource implements LedgerDataSource {
  SqlLedgerDataSource(
    this._store, {
    this._clock = const SystemClock(),
    MarketDataGateway? market,
    this._readPage = readPage,
  }) : _gateway = market;

  final EncryptedDatabase _store;
  final Clock _clock;

  /// How many rows are read at a time when the book opens.
  final int _readPage;

  /// Where closing prices and rates come from; none in tests.
  final MarketDataGateway? _gateway;

  /// Which category each id stands for, as the records are read and kept.
  final _refs = CategoryRefs();

  /// The exchanges, for a holding's daily closes; none in tests and the
  /// preview.
  MarketDataGateway? get gateway => _gateway;

  DateTime _today() {
    final day = _clock.today();
    return DateTime.utc(day.year, day.month, day.day);
  }

  @override
  Future<Ledger> load() => PerformanceMonitor.instance.timeLoad(() async {
    try {
      return await _load();
    } on StateError catch (error) {
      throw DataSourceException(error);
    }
  });

  /// Every row, by its shelf. A page at a time, the screen drawn between
  /// pages: read at once, a book of 100,000 entries held the screen still
  /// for a third of a second on a computer, longer on a phone.
  Future<Map<String, List<StoredRow>>> _shelves() async {
    final collections = <String, List<StoredRow>>{};
    for (var after = 0; ;) {
      final page = _store.rowsAfter(after, limit: _readPage);
      for (final row in page) {
        (collections[row.shelf] ??= []).add(row);
      }
      if (page.length < _readPage) break;
      after = page.last.seq;
      await Future<void>.delayed(Duration.zero);
    }
    return collections;
  }

  Future<Ledger> _load() async {
    _start();
    giveCategoriesIds(_store);
    final collections = await _shelves();
    final records = [
      for (final collection in Collection.values)
        if (collection != Collection.receipt) ...?collections[collection.name],
    ];
    final bodies = [for (final row in records) row.body];
    final decoded = bodies.length > _decodeApart
        ? await _decodeApartFrom(bodies)
        : _decodeAll(bodies);
    final json = <StoredRow, Map<String, Object?>>{
      for (final (i, row) in records.indexed)
        row: upgradeRecord(row.shelf, decoded[i]! as Map<String, Object?>),
    };
    List<T> read<T>(
      Collection collection,
      T Function(Map<String, Object?>) from,
    ) => [
      for (final row in collections[collection.name] ?? const <StoredRow>[])
        from(json[row]!),
    ];
    // What each category id stands for first: a category's parent and every
    // other record name theirs through it.
    _refs.fill([
      for (final row
          in collections[Collection.category.name] ?? const <StoredRow>[])
        if (json[row]! case {'id': final String id, 'name': final String name})
          (id, name),
    ]);
    final categories = read(
      Collection.category,
      (j) => categoryFromJson(j, _refs),
    );
    final market = _marketFrom(collections[_market] ?? const []);
    final today = _today();
    final trash = read(Collection.trash, (j) => trashedFromJson(j, _refs));
    final from = today.subtract(_keptInTrash);
    final expired = [
      for (final t in trash)
        if (t.on.isBefore(from)) t.entry.id,
    ];
    if (expired.isNotEmpty) {
      _store.write((w) {
        for (final id in expired) {
          w
            ..drop(Collection.trash.name, id)
            ..drop(Collection.receipt.name, id);
        }
      });
    }
    return Ledger(
      today: today,
      clock: _today,
      accounts: read(Collection.account, accountFromJson),
      categories: categories,
      entries: read(Collection.entry, (j) => entryFromJson(j, _refs)),
      holdings: _holdingsOf(market),
      budgets: read(Collection.budget, (j) => budgetFromJson(j, _refs)),
      recurring: read(Collection.recurring, (j) => recurringFromJson(j, _refs)),
      rates: market.rates,
      moves: market.moves,
      quotedOn: market.quotedOn,
      quoteDays: market.days,
      trash: [
        for (final t in trash.reversed)
          if (!t.on.isBefore(from)) t,
      ],
      receipts: {
        for (final row
            in collections[Collection.receipt.name] ?? const <StoredRow>[])
          row.id: row.body,
      },
      drafts: {
        for (final row in collections[_draft] ?? const <StoredRow>[])
          row.id: row.body,
      },
      dataSource: this,
    );
  }

  /// Gives a ledger that has none its first categories, and a cash and a
  /// bank account, so the first entry can be written at once.
  void _start() {
    final noCategories = _store.rows(shelf: Collection.category.name).isEmpty;
    final noAccounts = _store.rows(shelf: Collection.account.name).isEmpty;
    if (!noCategories && !noAccounts) return;
    _write(
      WriteBatch(
        categories: [
          if (noCategories)
            for (final (name, icon, color, income) in _starters)
              Category(name, icon, color, income: income),
        ],
        accounts: [
          if (noAccounts) ...[
            Account(PublicId.generate().value, '現金', AccountKind.cash, 0),
            Account(PublicId.generate().value, '銀行帳戶', AccountKind.bank, 0),
          ],
        ],
      ),
    );
  }

  @override
  Future<void> keep(WriteBatch batch) async {
    try {
      _write(batch);
    } on Object catch (error) {
      throw DataSourceException(error);
    }
  }

  void _write(WriteBatch batch) {
    final at = _clock.now().value.millisecondsSinceEpoch;
    // A category, as the rest of the batch names it, first; and what a
    // dropped budget was kept under, before its category goes.
    for (final c in batch.categories) {
      _refs.set(c);
    }
    final budgetKeys = {
      for (final (collection, key) in batch.dropped)
        if (collection == Collection.budget) key: _refs.idOf(key) ?? key,
    };
    String text(Map<String, Object?> json) =>
        jsonEncode({...json, '_v': recordVersion, '_at': at});
    _store.write((w) {
      void keep(Collection collection, String id, Map<String, Object?> json) {
        w.put(collection.name, id, text(json));
        if (_noted.contains(collection)) {
          w.drop(_gone, '${collection.name}/$id');
        }
      }

      for (final a in batch.accounts) {
        keep(Collection.account, a.id, accountToJson(a));
      }
      for (final c in batch.categories) {
        keep(Collection.category, c.id, categoryToJson(c, _refs));
      }
      for (final e in batch.entries) {
        keep(Collection.entry, e.id, entryToJson(e, _refs));
      }
      for (final b in batch.budgets) {
        keep(
          Collection.budget,
          _refs.idOf(b.category) ?? b.category,
          budgetToJson(b, _refs),
        );
      }
      for (final r in batch.recurring) {
        keep(Collection.recurring, r.id, recurringToJson(r, _refs));
      }
      for (final t in batch.trash) {
        keep(Collection.trash, t.entry.id, trashedToJson(t, _refs));
      }
      for (final MapEntry(key: id, value: file) in batch.receipts.entries) {
        if (file == null) {
          w.drop(Collection.receipt.name, id);
        } else {
          w.put(Collection.receipt.name, id, file);
        }
      }
      for (final (collection, name) in batch.dropped) {
        final id = collection == Collection.budget ? budgetKeys[name]! : name;
        w.drop(collection.name, id);
        if (_noted.contains(collection)) {
          w.put(_gone, '${collection.name}/$id', jsonEncode({'at': at}));
        }
        if (collection == Collection.category) _refs.remove(id);
      }
      for (final MapEntry(key: tab, value: json) in batch.drafts.entries) {
        if (json == null) {
          w.drop(_draft, tab);
        } else {
          w.put(_draft, tab, json);
        }
      }
    }, counts: !batch.onlyDrafts);
  }

  /// Throws a [FormatException] for a record this app cannot read, so a
  /// backup with one is refused rather than restored.
  static void check(String collection, String id, String body) {
    if (collection == Collection.receipt.name) {
      if (!RegExp(r'^[\w.-]+$').hasMatch(body)) {
        throw const FormatException('receipt');
      }
      return;
    }
    final Map<String, Object?> json;
    try {
      json = jsonDecode(body) as Map<String, Object?>;
    } on Object {
      throw FormatException('Unreadable $collection');
    }
    if (collection == _draft) {
      final entry = json['entry'];
      if (entry is! Map<String, Object?>) throw const FormatException('draft');
      entryFromJson(upgradeRecord(collection, entry));
      return;
    }
    if (collection == _gone) {
      if (json['at'] is! num) throw const FormatException('gone');
      return;
    }
    if (collection == _market) {
      if (id != 'quotes' && id != 'rates') throw FormatException(id);
      _marketFrom([StoredRow(0, collection, id, body)]);
      return;
    }
    // Out of context, a category's id is as good as its name.
    final refs = CategoryRefs.lenient();
    final reader = switch (Collection.values.asNameMap()[collection]) {
      Collection.account => accountFromJson,
      Collection.category => (Map<String, Object?> j) => categoryFromJson(
        j,
        refs,
      ),
      Collection.entry => (Map<String, Object?> j) => entryFromJson(j, refs),
      Collection.budget => (Map<String, Object?> j) => budgetFromJson(j, refs),
      Collection.recurring => (Map<String, Object?> j) => recurringFromJson(
        j,
        refs,
      ),
      Collection.trash => (Map<String, Object?> j) => trashedFromJson(j, refs),
      _ => throw FormatException('Unknown collection $collection'),
    };
    reader(upgradeRecord(collection, json));
  }

  // Market data.

  /// The closes and board last fetched, for `HoldingCommands.setMarket`.
  ({
    List<Holding> holdings,
    Map<String, double> moves,
    Map<String, double> rates,
    DateTime? quotedOn,
    Map<String, DateTime> days,
  })
  market() {
    final kept = _marketFrom(_store.rows(shelf: _market));
    return (
      holdings: _holdingsOf(kept),
      moves: kept.moves,
      rates: kept.rates,
      quotedOn: kept.quotedOn,
      days: kept.days,
    );
  }

  /// Fetches 臺灣銀行's board: the spot buying rate of each currency, what
  /// a foreign balance is worth in NT$. Returns whether any rate changed.
  Future<bool> refreshRates() async {
    final gateway = _gateway;
    if (gateway == null) return false;
    final board = (await gateway.bankRates()).value;
    if (board == null) return false;
    final fetched = <String, double>{};
    for (final MapEntry(key: code, value: row) in board.rates.entries) {
      final rate = row.valuation;
      if (rate != null) fetched[code] = rate.numerator / rate.denominator;
    }
    final kept = _marketFrom(_store.rows(shelf: _market));
    if (fetched.isEmpty || mapEquals(fetched, kept.rates)) return false;
    // Fetched, not changed by the person: no new backup is due for it.
    _store.write(
      (w) => w.put(
        _market,
        'rates',
        jsonEncode({'asOf': '${board.asOf}', 'rates': fetched}),
      ),
      counts: false,
    );
    return true;
  }

  /// The codes the last [refreshQuotes] found no close for: not quoted
  /// by either exchange, or out of reach.
  List<String> unquoted = const [];

  /// Fetches the latest close of each of [codes], for the holdings' value;
  /// one not found on TWSE is tried on TPEx. Returns whether any price
  /// changed.
  Future<bool> refreshQuotes(Iterable<String> codes) async {
    final gateway = _gateway;
    if (gateway == null) return false;
    final kept = _marketFrom(_store.rows(shelf: _market));
    final prices = {...kept.prices};
    final moves = {...kept.moves};
    final names = {...kept.names};
    final days = {...kept.days};
    var quotedOn = kept.quotedOn;
    var changed = false;
    final missed = <String>[];
    // Every code asked at once: the exchanges' day lists are fetched once
    // and shared, and a code looked for on TPEx or in the month report
    // does not hold up the others.
    Future<StockClose?> closeOf(String code) async {
      try {
        var result = await gateway.stockClose(Listing(code));
        if (result.state == MarketState.missing) {
          result = await gateway.stockClose(Listing(code, market: 'TPEX'));
        }
        // Not traded on the day, or left out of the day's list, and no
        // close kept from before: the last close in TWSE's month report.
        if (result.value == null && !prices.containsKey(code)) {
          final fallback = await gateway.listedHistoryClose(code);
          if (fallback.value != null) result = fallback;
        }
        return result.value;
      } on Object catch (error) {
        ErrorLog.instance.record('收盤價', error);
        return null;
      }
    }

    final asked = codes.toList();
    final closes = await Future.wait([for (final code in asked) closeOf(code)]);
    for (final (i, code) in asked.indexed) {
      final close = closes[i];
      final price = close == null ? null : double.tryParse(close.decimalPrice);
      if (close == null || price == null) {
        missed.add(code);
        continue;
      }
      final day = DateTime.utc(
        close.asOf.year,
        close.asOf.month,
        close.asOf.day,
      );
      if (quotedOn == null || day.isAfter(quotedOn)) {
        quotedOn = day;
        changed = true;
      }
      if (days[code] != day) {
        days[code] = day;
        changed = true;
      }
      final move = double.tryParse(close.decimalChange ?? '');
      final name = close.name;
      if (prices[code] == price &&
          moves[code] == move &&
          (name == null || names[code] == name)) {
        continue;
      }
      prices[code] = price;
      if (move == null) {
        moves.remove(code);
      } else {
        moves[code] = move;
      }
      if (name != null) names[code] = name;
      changed = true;
    }
    unquoted = List.unmodifiable(missed);
    if (changed) {
      _store.write(
        (w) => w.put(
          _market,
          'quotes',
          jsonEncode({
            'prices': prices,
            'moves': moves,
            'names': names,
            'days': {
              for (final MapEntry(:key, :value) in days.entries)
                key: value.toIso8601String(),
            },
            'on': ?quotedOn?.toIso8601String(),
          }),
        ),
        counts: false,
      );
    }
    return changed;
  }
}

typedef _Market = ({
  Map<String, double> prices,
  Map<String, double> moves,
  Map<String, String> names,
  Map<String, DateTime> days,
  DateTime? quotedOn,
  Map<String, double> rates,
});

/// The closes and board last fetched, from the [_market] collection.
_Market _marketFrom(List<StoredRow> rows) {
  final prices = <String, double>{};
  final moves = <String, double>{};
  final names = <String, String>{};
  final days = <String, DateTime>{};
  final rates = <String, double>{};
  DateTime? quotedOn;
  Map<String, Object?> part(Map<String, Object?> json, String key) =>
      json[key] as Map<String, Object?>? ?? const {};
  for (final row in rows) {
    final json = jsonDecode(row.body) as Map<String, Object?>;
    switch (row.id) {
      case 'quotes':
        for (final MapEntry(:key, :value) in part(json, 'prices').entries) {
          prices[key] = (value! as num).toDouble();
        }
        for (final MapEntry(:key, :value) in part(json, 'moves').entries) {
          moves[key] = (value! as num).toDouble();
        }
        for (final MapEntry(:key, :value) in part(json, 'names').entries) {
          names[key] = value! as String;
        }
        for (final MapEntry(:key, :value) in part(json, 'days').entries) {
          days[key] = DateTime.parse(value! as String);
        }
        if (json['on'] case final String on) quotedOn = DateTime.parse(on);
      case 'rates':
        for (final MapEntry(:key, :value) in part(json, 'rates').entries) {
          rates[key] = (value! as num).toDouble();
        }
    }
  }
  return (
    prices: prices,
    moves: moves,
    names: names,
    days: days,
    quotedOn: quotedOn,
    rates: rates,
  );
}

/// A reference price and name for each stock with a kept close.
List<Holding> _holdingsOf(_Market market) => [
  for (final MapEntry(key: code, value: price) in market.prices.entries)
    Holding(
      code,
      market.names[code] ?? code,
      shares: 0,
      price: price,
      cost: 0,
      change: 0,
    ),
];
