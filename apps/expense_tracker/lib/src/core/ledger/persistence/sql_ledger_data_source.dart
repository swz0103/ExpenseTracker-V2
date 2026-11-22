// Exception to ledger words: a new book's first categories and accounts
// are written as data, and the diagnostics log is labelled in words.

import 'dart:convert';
import 'dart:isolate';

import 'package:core/app_core.dart';
import 'package:core/foundation_values.dart';
import 'package:flutter/foundation.dart' show mapEquals;
import 'package:market/market_data.dart';
import 'package:storage/storage.dart';

import 'book_migrations.dart';
import 'ledger_data_source.dart';
import '../ledger.dart';
import 'codec/category_refs.dart';
import 'codec/record_fields.dart';
import 'quarantine.dart';
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

/// How long a deleted entry is kept to be restored, and how long the note
/// of a deletion is kept in [_gone]. (The trash page says the same number
/// of days with its own constant, `_keptDays` in trash_section.dart.)
const keptInTrash = Duration(days: 30);

/// The collection of the last closing prices and rate board, kept so holdings
/// and foreign accounts are valued offline.
const _market = 'market';

/// When each record was deleted, by `collection/id`, so a deletion can be
/// told from a record never kept (for a later sync); dropped when the id
/// is kept again, and once [keptInTrash] has passed. Nothing reads them
/// but a backup's check.
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

/// A row whose body is not JSON, as [_decodeAll] gives it.
final class _NotJson {
  const _NotJson();
}

List<Object?> _decodeAll(List<String> bodies) => [
  for (final body in bodies) _decode(body),
];

Object? _decode(String body) {
  try {
    return jsonDecode(body);
  } on FormatException {
    return const _NotJson();
  }
}

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
///
/// Opening reads row by row: a row this version cannot read is set aside
/// ([quarantined]), kept on disk as it is and never written over, and
/// the rest of the book opens. A book kept by an earlier version is first
/// brought up (book_migrations.dart), after [beforeUpgrade] has kept a
/// copy of it.
final class SqlLedgerDataSource implements LedgerDataSource {
  SqlLedgerDataSource(
    this._store, {
    this._clock = const SystemClock(),
    MarketDataGateway? market,
    this._readPage = readPage,
    this.beforeUpgrade,
  }) : _gateway = market;

  final EncryptedDatabase _store;
  final Clock _clock;

  /// How many rows are read at a time when the book opens.
  final int _readPage;

  /// Where closing prices and rates come from; none in tests.
  final MarketDataGateway? _gateway;

  /// Keeps a copy of the book as it is, before a book kept by an earlier
  /// version is brought up; none in tests. A copy that cannot be kept is
  /// noted in the diagnostics log and the book is brought up all the same:
  /// the steps run in one transaction, so a failing one changes nothing.
  final Future<void> Function()? beforeUpgrade;

  /// Which category each id stands for, as the records are read and kept.
  final _refs = CategoryRefs();

  /// The rows set aside the last time the book was opened, in the order
  /// they are kept.
  List<QuarantinedRow> get quarantined => List.unmodifiable(_aside.values);
  final _aside = <String, QuarantinedRow>{};

  /// The fields a record was read with that this version does not know,
  /// by `collection/key`, to be written back with it. An entry's are kept
  /// under `entry/id` in the trash too, so they go with it there and back.
  final _unknown = <String, Map<String, Object?>>{};

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

  /// Sets [row] aside for [reason].
  void _setAside(
    StoredRow row,
    QuarantineReason reason, {
    String detail = '',
    int? version,
  }) {
    final aside = QuarantinedRow(
      row.shelf,
      row.id,
      reason,
      detail: detail,
      version: version,
    );
    _aside[aside.key] = aside;
  }

  /// The record of each row of [collections] but the receipts, decoded
  /// and brought up to the current version; a row that is not a JSON
  /// object, or that a later version wrote, is set aside instead.
  Future<Map<StoredRow, Map<String, Object?>>> _records(
    Map<String, List<StoredRow>> collections,
  ) async {
    final records = [
      for (final collection in Collection.values)
        if (collection != Collection.receipt) ...?collections[collection.name],
    ];
    final bodies = [for (final row in records) row.body];
    final decoded = bodies.length > _decodeApart
        ? await _decodeApartFrom(bodies)
        : _decodeAll(bodies);
    final json = <StoredRow, Map<String, Object?>>{};
    for (final (i, row) in records.indexed) {
      final record = decoded[i];
      if (record is! Map<String, Object?>) {
        _setAside(
          row,
          QuarantineReason.unreadable,
          detail: record is _NotJson ? 'not JSON' : 'not a JSON object',
        );
        continue;
      }
      try {
        json[row] = upgradeRecord(row.shelf, record);
      } on NewerRecord catch (newer) {
        _setAside(row, QuarantineReason.newer, version: newer.version);
      } on FormatException catch (error) {
        _setAside(
          row,
          QuarantineReason.invalid,
          detail: quarantineDetail(error),
        );
      }
    }
    return json;
  }

  /// Notes the fields of [json], the record of [row], that this version
  /// does not read, to keep them when it is written again.
  void _keepUnknown(StoredRow row, Map<String, Object?> json) {
    final unknown = unknownFields(row.shelf, json);
    if (unknown != null) _unknown['${row.shelf}/${row.id}'] = unknown;
    if (row.shelf != Collection.trash.name) return;
    if (json['entry'] case final Map<String, Object?> entry) {
      final inner = unknownFields(Collection.entry.name, entry);
      if (inner != null) _unknown['${Collection.entry.name}/${row.id}'] = inner;
    }
  }

  /// Drops the entries of [trash] put there before [from], and their
  /// receipts, and the notes in [_gone] of deletions made before [from].
  /// A row set aside is never dropped.
  void _dropExpired(List<Trashed> trash, List<StoredRow> gone, DateTime from) {
    final expired = [
      for (final t in trash)
        if (t.on.isBefore(from)) t.entry.id,
    ];
    final cutoff = from.millisecondsSinceEpoch;
    final forgotten = [
      for (final row in gone)
        if (_noteTime(row) case final at? when at < cutoff) row.id,
    ];
    if (expired.isEmpty && forgotten.isEmpty) return;
    _store.write((w) {
      for (final id in expired) {
        w
          ..drop(Collection.trash.name, id)
          ..drop(Collection.receipt.name, id);
      }
      for (final id in forgotten) {
        w.drop(_gone, id);
      }
      // Only an entry gone for good is a change of the book.
    }, counts: expired.isNotEmpty);
  }

  /// When the deletion noted in [row] was made, in milliseconds; null
  /// when the note cannot be read.
  static int? _noteTime(StoredRow row) {
    try {
      return switch (jsonDecode(row.body)) {
        {'at': final num at} => at.toInt(),
        _ => null,
      };
    } on FormatException {
      return null;
    }
  }

  /// Brings the book up to this version before it is read: a new one is
  /// given its first records, one kept by an earlier version goes through
  /// the steps it lacks. A book that was opened before is never given
  /// records again, even when the person removed every account.
  Future<void> _bringUp() async {
    switch (standingOf(_store)) {
      case BookStanding.fresh:
        _start();
      case BookStanding.behind:
        try {
          await beforeUpgrade?.call();
        } on Object catch (error) {
          ErrorLog.instance.record('升級前備份', error);
        }
        bringUpBook(_store);
      case BookStanding.current || BookStanding.ahead:
        break;
    }
  }

  Future<Ledger> _load() async {
    _aside.clear();
    _unknown.clear();
    await _bringUp();
    final collections = await _shelves();
    final json = await _records(collections);
    List<T> read<T>(
      Collection collection,
      T Function(Map<String, Object?>) from,
    ) {
      final read = <T>[];
      for (final row in collections[collection.name] ?? const <StoredRow>[]) {
        final record = json[row];
        if (record == null) continue;
        try {
          read.add(from(record));
        } on Object catch (error) {
          _setAside(
            row,
            QuarantineReason.invalid,
            detail: quarantineDetail(error),
          );
          continue;
        }
        _keepUnknown(row, record);
      }
      return read;
    }

    // What each category id stands for first: a category's parent and every
    // other record name theirs through it.
    _refs.fill([
      for (final row
          in collections[Collection.category.name] ?? const <StoredRow>[])
        if (json[row] case {'id': final String id, 'name': final String name})
          (id, name),
    ]);
    final categories = read(
      Collection.category,
      (j) => categoryFromJson(j, _refs),
    );
    final market = _marketFrom(_readableMarket(collections[_market]));
    final today = _today();
    final trash = read(Collection.trash, (j) => trashedFromJson(j, _refs));
    final from = today.subtract(keptInTrash);
    _dropExpired(trash, collections[_gone] ?? const [], from);
    final ledger = Ledger(
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
    if (_aside.isNotEmpty) {
      ErrorLog.instance.record(
        '開啟帳本',
        StateError('${_aside.length} rows set aside'),
      );
    }
    return ledger;
  }

  /// Gives a ledger just made its first categories, and a cash and a bank
  /// account, so the first entry can be written at once; and notes that
  /// it is at this version, in the same write.
  void _start() {
    _write(
      WriteBatch(
        categories: [
          for (final (name, icon, color, income) in _starters)
            Category(name, icon, color, income: income),
        ],
        accounts: [
          Account(PublicId.generate().value, '現金', AccountKind.cash, 0),
          Account(PublicId.generate().value, '銀行帳戶', AccountKind.bank, 0),
        ],
      ),
      also: markCurrent,
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

  /// The categories of [batch] whose name stands for them from now on,
  /// newly made or renamed, by that name: the records kept naming it by
  /// name are to name it by id ([_claimName]).
  Map<String, String> _claimed(WriteBatch batch) => {
    for (final c in batch.categories)
      if (_refs.idOf(c.name) != c.id) c.name: c.id,
  };

  /// Each record kept naming [name] by name names it by [id] instead, so
  /// a later rename reaches it (DAT-05). Found by the name as the JSON
  /// writes it, without reading the whole book.
  void _claimName(RowWriter w, String name, String id) {
    for (final row in _store.rowsHolding(
      jsonEncode(name),
      shelves: namingCollections,
    )) {
      if (_aside.containsKey('${row.shelf}/${row.id}')) continue;
      final json = readableRecord(row);
      if (json == null) continue;
      final byId = namesToIds(row.shelf, json, (n) => n == name ? id : null);
      if (byId == null) continue;
      var key = row.id;
      if (row.shelf == Collection.budget.name) {
        key = budgetKeyAfter(_store, row, byId);
        if (key != row.id) {
          w.drop(row.shelf, row.id);
          final unknown = _unknown.remove('${row.shelf}/${row.id}');
          if (unknown != null) _unknown['${row.shelf}/$key'] = unknown;
        }
      }
      w.put(row.shelf, key, jsonEncode(byId));
    }
  }

  void _write(WriteBatch batch, {void Function(RowWriter writer)? also}) {
    final at = _clock.now().value.millisecondsSinceEpoch;
    final claimed = _claimed(batch);
    // A category, as the rest of the batch names it, first; and what a
    // dropped budget was kept under, before its category goes.
    for (final c in batch.categories) {
      _refs.set(c);
    }
    final budgetKeys = {
      for (final (collection, key) in batch.dropped)
        if (collection == Collection.budget) key: _refs.idOf(key) ?? key,
    };
    String text(Collection collection, String id, Map<String, Object?> json) {
      final unknown = _unknown['${collection.name}/$id'];
      if (collection == Collection.trash) {
        final inner = _unknown['${Collection.entry.name}/$id'];
        if (inner != null) {
          json = {
            ...json,
            'entry': {...inner, ...json['entry']! as Map<String, Object?>},
          };
        }
      }
      return jsonEncode({...?unknown, ...json, '_v': recordVersion, '_at': at});
    }

    void mayChange(String shelf, String id) {
      if (_aside.containsKey('$shelf/$id')) {
        throw StateError('A row set aside is not written over ($shelf).');
      }
    }

    _store.write((w) {
      void keep(Collection collection, String id, Map<String, Object?> json) {
        mayChange(collection.name, id);
        w.put(collection.name, id, text(collection, id, json));
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
        mayChange(collection.name, id);
        w.drop(collection.name, id);
        if (_noted.contains(collection)) {
          w.put(_gone, '${collection.name}/$id', jsonEncode({'at': at}));
        }
        if (collection == Collection.category) _refs.remove(id);
        // An entry's unknown fields go with it to the trash and back.
        if (collection != Collection.entry && collection != Collection.trash) {
          _unknown.remove('${collection.name}/$id');
        }
      }
      for (final MapEntry(key: tab, value: json) in batch.drafts.entries) {
        if (json == null) {
          w.drop(_draft, tab);
        } else {
          w.put(_draft, tab, json);
        }
      }
      for (final MapEntry(key: name, value: id) in claimed.entries) {
        _claimName(w, name, id);
      }
      also?.call(w);
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

  /// The rows of [rows] of the [_market] collection that can be read: a
  /// close or rate kept that cannot is fetched again, and noted.
  static List<StoredRow> _readableMarket(List<StoredRow>? rows) => [
    for (final row in rows ?? const <StoredRow>[])
      if (_marketReadable(row)) row,
  ];

  static bool _marketReadable(StoredRow row) {
    try {
      _marketFrom([row]);
      return true;
    } on Object catch (error) {
      ErrorLog.instance.record('讀取行情', error);
      return false;
    }
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
    final kept = _marketFrom(_readableMarket(_store.rows(shelf: _market)));
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
    final kept = _marketFrom(_readableMarket(_store.rows(shelf: _market)));
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

  /// The latest close of [code] from [gateway], TWSE first, or null when
  /// none is found; [prices] are the closes kept from before.
  Future<StockClose?> _closeOf(
    MarketDataGateway gateway,
    String code,
    Map<String, double> prices,
  ) async {
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

  /// Fetches the latest close of each of [codes], for the holdings' value;
  /// one not found on TWSE is tried on TPEx. Returns whether any price
  /// changed.
  Future<bool> refreshQuotes(Iterable<String> codes) async {
    final gateway = _gateway;
    if (gateway == null) return false;
    final kept = _marketFrom(_readableMarket(_store.rows(shelf: _market)));
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
    final asked = codes.toList();
    final closes = await Future.wait([
      for (final code in asked) _closeOf(gateway, code, prices),
    ]);
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
