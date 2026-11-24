// Exception to ledger words: a new book's first categories and accounts
// are written as data, and the diagnostics log is labelled in words.
// Exception to file length: this is the one place rows are read from and
// written to the store; what it notes of them as it reads (rows set
// aside, unknown fields, records naming a category by name) is checked
// on every write, and split across files those notes would have to be
// public. The pure parts live in codec/ and book_migrations.dart.

import 'dart:convert';
import 'dart:isolate';

import 'package:core/app_core.dart';
import 'package:core/constants/retention.dart';
import 'package:core/foundation_values.dart';
import 'package:core/money/amount_parser.dart' show parseDecimal;
import 'package:flutter/foundation.dart' show mapEquals;
import 'package:market/market_data.dart';
import 'package:storage/storage.dart';

import 'book_migrations.dart';
import 'journal_keeper.dart';
import 'journal_rebuild.dart';
import 'ledger_data_source.dart';
import '../journal/replay.dart' show KeptEntry, ReplayReport;
import '../ledger.dart';
import 'codec/category_refs.dart';
import 'codec/record_fields.dart';
import 'codec/row_decoding.dart';
import 'quarantine.dart';
import 'record_version.dart';
import 'upgrade_backup.dart';
import 'codec/record_json.dart';
import 'codec/record_shape.dart';
import '../../diagnostics/performance_monitor.dart';
import '../../diagnostics/error_log.dart';
import '../../diagnostics/error_steps.dart';

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

/// The collection of the last closing prices and rate board, kept so holdings
/// and foreign accounts are valued offline.
const _market = 'market';

/// When each record was deleted, by `collection/id`, so a deletion can be
/// told from a record never kept (for a later sync); dropped when the id
/// is kept again, and once [trashRetention] has passed. Nothing reads them
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

/// [decodeBodies] on a worker isolate. Kept out of the methods of the data
/// source: a closure made beside one that uses `this` carries it along,
/// and the database cannot be sent to another isolate.
Future<DecodedRows> _decodeApartFrom(List<String> bodies) =>
    Isolate.run(() => decodeBodies(bodies));

/// Above this many rows the JSON is decoded on a worker isolate, so the
/// screen does not freeze while a large book opens.
const _decodeApart = 2000;

/// How many rows a book is read at a time when it opens.
const readPage = 5000;

/// From this many records a change is written on a worker isolate
/// ([EncryptedDatabase.writeApart]): a merchant renamed on every entry,
/// categories merged, an import. Fewer, it is written at once, as a
/// single save is (well under a frame: storage's README).
const writeApartFrom = 500;

/// The book kept in the encrypted ledger: each of the screens' records a
/// row of JSON, written as the [Ledger] hands over each change.
///
/// Opening reads row by row: a row this version cannot read is set aside
/// ([quarantined]), kept on disk as it is and never written over, and
/// the rest of the book opens. A book kept by an earlier version is first
/// brought up (book_migrations.dart), only once [beforeUpgrade] has kept a
/// copy of it ([bringUp]).
final class SqlLedgerDataSource implements LedgerDataSource {
  SqlLedgerDataSource(
    this._store, {
    this._clock = const SystemClock(),
    MarketDataGateway? market,
    this._readPage = readPage,
    this._writeApartFrom = writeApartFrom,
    this.beforeUpgrade,
    this.keepsJournal = false,
  }) : _gateway = market;

  /// Whether the journal of postings is kept beside the records and
  /// checked against them (journal_keeper.dart): as the app opens its
  /// book; tests that do not look at it leave it out.
  final bool keepsJournal;

  /// The journal kept beside the records, when [keepsJournal].
  late final journal = JournalKeeper(
    store: _store.journal,
    revision: () => _store.revision,
    entrySeqs: _entrySeqs,
    recordOf: _keptEntry,
    isOpen: () => _store.isOpen,
    busy: () => _store.busyApart,
    quiet: _quiet,
    postApart: _postJournalApart,
  );

  /// The whole journal posted afresh on a worker isolate (D51): from the
  /// records as kept, those set aside as the book opened left out, the
  /// mark of the records' revision kept last.
  Future<ReplayReport> _postJournalApart(List<Holding> start) async {
    // Asked again after each wait, so the store is taken in the same step
    // as it is found free (a backup may be waiting for the same moment).
    while (_store.busyApart) {
      await _store.idle;
    }
    return _store.postApart(
      postingWork(
        aside: {for (final r in _aside.rows) '${r.shelf}/${r.id}'},
        start: start,
      ),
      mark: (rules: journalRules, revision: _store.revision),
    );
  }

  /// Where each entry read as the book last opened stands, until the
  /// journal has taken it; then read from the store again.
  Map<String, int>? _seqsAtLoad;

  Map<String, int> _entrySeqs() {
    final kept = _seqsAtLoad;
    _seqsAtLoad = null;
    return kept ??
        {
          for (final row in _store.rows(shelf: Collection.entry.name))
            row.id: row.seq,
        };
  }

  /// The entry kept as [id] and its place; null when there is none or
  /// it cannot be read (a row set aside has no postings).
  KeptEntry? _keptEntry(String id) {
    final row = _store.row(Collection.entry.name, id);
    if (row == null || _aside.holds(row.shelf, row.id)) return null;
    final json = readableRecord(row.body);
    if (json == null) return null;
    try {
      final entry = entryFromJson(upgradeRecord(row.shelf, json), _refs);
      return (entry: entry, seq: row.seq);
    } on Object catch (error) {
      ErrorLog.instance.record(ErrorSteps.journalUpdate, error);
      return null;
    }
  }

  final EncryptedDatabase _store;

  /// The app's one clock, handed over where the app is put together.
  final Clock _clock;

  /// How many rows are read at a time when the book opens.
  final int _readPage;

  /// From how many records a change is written apart ([writeApartFrom]).
  final int _writeApartFrom;

  /// Where closing prices and rates come from; none in tests.
  final MarketDataGateway? _gateway;

  /// Keeps a copy of the book as it is, before a book kept by an earlier
  /// version is brought up; none in tests. A copy that cannot be kept
  /// keeps the book from being brought up (D19): [bringUp] says why, and
  /// [load] refuses the book until the person decides.
  final Future<UpgradeBackup> Function()? beforeUpgrade;

  /// Which category each id stands for, as the records are read and kept.
  final _refs = CategoryRefs();

  /// The rows set aside the last time the book was opened, in the order
  /// they are kept.
  List<QuarantinedRow> get quarantined => _aside.rows;
  final _aside = Quarantine();

  /// The fields this version does not know of the record kept as [id] of
  /// [collection], to be written back with it; null when none. Read from
  /// the row about to be written over, at write time rather than as the
  /// book opens: few records are written, every record is read. An
  /// entry's go with it to the trash and back, so an entry's are looked
  /// for in its trash row too, and a trash row's entry in the entry row.
  Map<String, Object?>? _unknownOf(Collection collection, String id) {
    Map<String, Object?>? kept(Collection c) =>
        switch (_store.row(c.name, id)) {
          final row? => readableRecord(row.body),
          null => null,
        };
    switch (collection) {
      case Collection.entry:
        final json =
            kept(Collection.entry) ??
            switch (kept(Collection.trash)?['entry']) {
              final Map<String, Object?> entry => entry,
              _ => null,
            };
        return json == null ? null : unknownFields(collection.name, json);
      case Collection.trash:
        final trash = kept(Collection.trash);
        final entry = switch (trash?['entry']) {
          final Map<String, Object?> entry => entry,
          _ => kept(Collection.entry),
        };
        final inner = entry == null
            ? null
            : unknownFields(Collection.entry.name, entry);
        return {
          ...?(trash == null ? null : unknownFields(collection.name, trash)),
          'entry': ?inner,
        };
      case _:
        final json = kept(collection);
        return json == null ? null : unknownFields(collection.name, json);
    }
  }

  /// The exchanges, for a holding's daily closes; none in tests and the
  /// preview.
  MarketDataGateway? get gateway => _gateway;

  DateTime _today() => _clock.today().asUtcMidnight;

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
        : decodeBodies(bodies);
    final json = <StoredRow, Map<String, Object?>>{};
    for (final (i, row) in records.indexed) {
      final record = decoded.values[i];
      if (record is! Map<String, Object?>) {
        _aside.record(
          row.shelf,
          row.id,
          QuarantineReason.unreadable,
          detail: decoded.failures.containsKey(i)
              ? 'not JSON'
              : 'not a JSON object',
        );
        continue;
      }
      switch (versionOf(record)) {
        case null:
          _aside.record(
            row.shelf,
            row.id,
            QuarantineReason.invalid,
            detail: '_v is not a number',
          );
        case final version when version > recordVersion:
          _aside.record(
            row.shelf,
            row.id,
            QuarantineReason.newer,
            version: version,
          );
        case _:
          json[row] = upgradeRecord(row.shelf, record);
      }
    }
    return json;
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
    final notes = decodeBodies([for (final row in gone) row.body]).values;
    final forgotten = [
      for (final (i, row) in gone.indexed)
        // A note that cannot be read is left as it is.
        if (notes[i] case {'at': final num at} when at < cutoff) row.id,
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

  /// Brings the book up to this version before it is read: a new one is
  /// given its first records, one kept by an earlier version goes through
  /// the steps it lacks, once [beforeUpgrade] has kept a copy of it, or
  /// without one when the person chose [withoutBackup]. A book that was
  /// opened before is never given records again, even when the person
  /// removed every account.
  ///
  /// The copy that could not be kept, the book left as it was; null once
  /// the book is at this version (or later).
  Future<UpgradeBackupFailed?> bringUp({bool withoutBackup = false}) async {
    while (_store.busyApart) {
      await _store.idle;
    }
    switch (standingOf(_store)) {
      case BookStanding.fresh:
        _start();
      case BookStanding.behind:
        if (!withoutBackup) {
          if (await beforeUpgrade?.call() case final UpgradeBackupFailed no) {
            return no;
          }
        }
        while (_store.busyApart) {
          await _store.idle;
        }
        bringUpBook(_store);
      case BookStanding.current || BookStanding.ahead:
        break;
    }
    return null;
  }

  Future<Ledger> _load() async {
    _aside.clear();
    _named.clear();
    _namesOf.clear();
    // Never read a book left behind: the copy before its upgrade was not
    // kept, and the person has not chosen to go on without it.
    if (await bringUp() case final no?) throw UpgradeHeld(no);
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
          // Not logged per row: the row is set aside and told on opening.
          _aside.record(
            row.shelf,
            row.id,
            QuarantineReason.invalid,
            error: error,
          );
          continue;
        }
        _indexNames(row.shelf, row.id, record);
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
    final from = today.subtract(trashRetention);
    while (_store.busyApart) {
      await _store.idle;
    }
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
    if (!_aside.isEmpty) {
      ErrorLog.instance.record(
        '開啟帳本',
        StateError('${_aside.rows.length} rows set aside'),
      );
    }
    if (keepsJournal) {
      _seqsAtLoad = {
        for (final row
            in collections[Collection.entry.name] ?? const <StoredRow>[])
          row.id: row.seq,
      };
      journal.open(ledger);
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
      // A category made or renamed reads the records naming it as the
      // change is written (_claimName): such a change is written at once.
      if (_sizeOf(batch) >= _writeApartFrom && _claimed(batch).isEmpty) {
        await _writeApart(batch);
      } else {
        // A backup reading the book on a worker holds the store for that
        // read (D41): the change is written once it is done, never into
        // the middle of it.
        while (_store.busyApart) {
          await _store.idle;
        }
        _write(batch);
      }
    } on Object catch (error) {
      throw DataSourceException(error);
    }
    if (keepsJournal) journal.kept(batch);
  }

  static int _sizeOf(WriteBatch batch) =>
      batch.accounts.length +
      batch.categories.length +
      batch.entries.length +
      batch.budgets.length +
      batch.recurring.length +
      batch.trash.length +
      batch.receipts.length +
      batch.dropped.length +
      batch.drafts.length;

  /// Done once no other isolate uses the store. A caller about to use it
  /// asks [EncryptedDatabase.busyApart] again in a loop instead, so the
  /// store is found free and used in one step: another waiting for the
  /// same moment may take it first.
  Future<void> _quiet() async {
    while (_store.busyApart) {
      await _store.idle;
    }
  }

  /// The categories of [batch] whose name stands for them from now on,
  /// newly made or renamed, by that name: the records kept naming it by
  /// name are to name it by id ([_claimName]).
  Map<String, String> _claimed(WriteBatch batch) => {
    for (final c in batch.categories)
      if (_refs.idOf(c.name) != c.id) c.name: c.id,
  };

  /// The records kept naming a category by name, by that name; and the
  /// names each of them names so, by `collection/key`. Few or none: a
  /// record names a category by name only while no category has it.
  final _named = <String, Set<String>>{};
  final _namesOf = <String, Set<String>>{};

  /// The names [_indexNames] finds in a record, gathered by [_collectName].
  final _collected = <String>{};
  late final _collectName = _collect;
  String? _collect(String name) {
    _collected.add(name);
    return null;
  }

  /// Notes the categories [json], the record kept as [id] of [shelf],
  /// names by name; none when it is dropped (null).
  void _noteNames(String shelf, String id, Map<String, Object?>? json) {
    final key = '$shelf/$id';
    for (final name in _namesOf.remove(key) ?? const <String>{}) {
      final keys = _named[name]!..remove(key);
      if (keys.isEmpty) _named.remove(name);
    }
    if (json != null) _indexNames(shelf, id, json);
  }

  /// Adds what [json] names by name to [_named], as the book is read.
  void _indexNames(String shelf, String id, Map<String, Object?> json) {
    // One collector for every record, not a closure made for each.
    namesToIds(shelf, json, _collectName);
    if (_collected.isEmpty) return;
    final found = {..._collected};
    _collected.clear();
    final key = '$shelf/$id';
    _namesOf[key] = found;
    for (final name in found) {
      (_named[name] ??= {}).add(key);
    }
  }

  /// Each record kept naming [name] by name names it by [id] instead, so
  /// a later rename reaches it (DAT-05); what to note once the write is
  /// kept is added to [after].
  void _claimName(
    RowWriter w,
    String name,
    String id,
    List<void Function()> after,
  ) {
    for (final key in List.of(_named[name] ?? const <String>{})) {
      final slash = key.indexOf('/');
      final shelf = key.substring(0, slash);
      final row = _store.row(shelf, key.substring(slash + 1));
      if (row == null || _aside.holds(row.shelf, row.id)) continue;
      final json = readableRecord(row.body);
      if (json == null) continue;
      final byId = namesToIds(shelf, json, (n) => n == name ? id : null);
      if (byId == null) continue;
      var kept = row.id;
      if (shelf == Collection.budget.name) {
        kept = budgetKeyAfter(_store, row, byId);
        if (kept != row.id) w.drop(shelf, row.id);
      }
      w.put(shelf, kept, jsonEncode(byId));
      after.add(() {
        _noteNames(shelf, row.id, null);
        _noteNames(shelf, kept, byId);
      });
    }
  }

  /// Writes [batch] at once, in one transaction, with what [also] adds.
  void _write(WriteBatch batch, {void Function(RowWriter writer)? also}) {
    final after = <void Function()>[];
    _store.write((w) {
      for (final _ in _fill(
        batch,
        put: w.put,
        drop: w.drop,
        after: after,
        claim: w,
      )) {}
      also?.call(w);
    }, counts: !batch.onlyDrafts);
    for (final note in after) {
      note();
    }
  }

  /// Writes [batch] on a worker isolate (DAT-03): its rows are made here a
  /// slice at a time, the screen drawn between slices ([_slice]), then
  /// kept in one transaction apart; what this notes of them follows once
  /// they are kept, a slice at a time too.
  Future<void> _writeApart(WriteBatch batch) async {
    final changes = <RowChange>[];
    final after = <void Function()>[];
    final watch = Stopwatch()..start();
    Future<void> breathe() async {
      if (watch.elapsed < _slice) return;
      await Future<void>.delayed(Duration.zero);
      watch.reset();
    }

    for (final _ in _fill(
      batch,
      put: (shelf, id, body) => changes.add(RowChange.put(shelf, id, body)),
      drop: (shelf, id) => changes.add(RowChange.drop(shelf, id)),
      after: after,
    )) {
      await breathe();
    }
    while (_store.busyApart) {
      await _store.idle;
    }
    await _store.writeApart(changes, counts: !batch.onlyDrafts);
    for (final note in after) {
      note();
      await breathe();
    }
  }

  /// The longest the screen is kept waiting while the rows of a change
  /// written apart are made: half a frame at 60 frames a second.
  // Exception to the motion scale: a share of a frame's time, not a
  // movement.
  static const _slice = Duration(milliseconds: 8);

  /// The rows [batch] puts in place and drops, handed to [put] and
  /// [drop] in the order they are written, a record at a time: it yields
  /// after each, so a caller may let the screen draw. What to note once
  /// they are kept is added to [after]. [claim] is the writer of a
  /// transaction under way, for the records that named a category by
  /// name; none when the batch claims none ([keep] writes those at once).
  Iterable<void> _fill(
    WriteBatch batch, {
    required void Function(String shelf, String id, String body) put,
    required void Function(String shelf, String id) drop,
    required List<void Function()> after,
    RowWriter? claim,
  }) sync* {
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
      final unknown = _unknownOf(collection, id);
      if (unknown?.remove('entry') case final Map<String, Object?> inner) {
        json = {
          ...json,
          'entry': {...inner, ...json['entry']! as Map<String, Object?>},
        };
      }
      return jsonEncode({...?unknown, ...json, '_v': recordVersion, '_at': at});
    }

    void mayChange(String shelf, String id) {
      if (_aside.holds(shelf, id)) {
        throw RowSetAside(shelf);
      }
    }

    // What the data source notes of the rows written, once they are kept:
    // nothing of a write that throws.
    void keep(Collection collection, String id, Map<String, Object?> json) {
      mayChange(collection.name, id);
      put(collection.name, id, text(collection, id, json));
      if (_noted.contains(collection)) {
        drop(_gone, '${collection.name}/$id');
      }
      after.add(() => _noteNames(collection.name, id, json));
    }

    for (final a in batch.accounts) {
      keep(Collection.account, a.id, accountToJson(a));
      yield null;
    }
    for (final c in batch.categories) {
      keep(Collection.category, c.id, categoryToJson(c, _refs));
      yield null;
    }
    for (final e in batch.entries) {
      keep(Collection.entry, e.id, entryToJson(e, _refs));
      yield null;
    }
    for (final b in batch.budgets) {
      keep(
        Collection.budget,
        _refs.idOf(b.category) ?? b.category,
        budgetToJson(b, _refs),
      );
      yield null;
    }
    for (final r in batch.recurring) {
      keep(Collection.recurring, r.id, recurringToJson(r, _refs));
      yield null;
    }
    for (final t in batch.trash) {
      keep(Collection.trash, t.entry.id, trashedToJson(t, _refs));
      yield null;
    }
    for (final MapEntry(key: id, value: file) in batch.receipts.entries) {
      if (file == null) {
        drop(Collection.receipt.name, id);
      } else {
        put(Collection.receipt.name, id, file);
      }
      yield null;
    }
    for (final (collection, name) in batch.dropped) {
      final id = collection == Collection.budget ? budgetKeys[name]! : name;
      mayChange(collection.name, id);
      drop(collection.name, id);
      if (_noted.contains(collection)) {
        put(_gone, '${collection.name}/$id', jsonEncode({'at': at}));
      }
      if (collection == Collection.category) _refs.remove(id);
      after.add(() => _noteNames(collection.name, id, null));
      yield null;
    }
    for (final MapEntry(key: tab, value: json) in batch.drafts.entries) {
      if (json == null) {
        drop(_draft, tab);
      } else {
        put(_draft, tab, json);
      }
      yield null;
    }
    if (claimed.isNotEmpty) {
      // Only a write at once claims: keep() sends no claiming batch apart.
      final w = claim!;
      for (final MapEntry(key: name, value: id) in claimed.entries) {
        _claimName(w, name, id, after);
      }
    }
  }

  /// Throws a [FormatException] naming the row, whatever its slip, for a
  /// record this app cannot read or no version of it would write
  /// ([shapeIssues]), so a backup with one is refused, not restored.
  static void check(String collection, String id, String body) {
    try {
      _check(collection, id, body);
    } on Object catch (slip) {
      final what = slip is FormatException ? slip.message : slip.runtimeType;
      throw FormatException('$collection $id: $what');
    }
  }

  static void _check(String collection, String id, String body) {
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
    checkRecord(collection, upgradeRecord(collection, json));
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
    while (_store.busyApart) {
      await _store.idle;
    }
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
    while (_store.busyApart) {
      await _store.idle;
    }
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
      final price = close == null ? null : parseDecimal(close.decimalPrice);
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
      final move = parseDecimal(close.decimalChange ?? '');
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
      while (_store.busyApart) {
        await _store.idle;
      }
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

/// A book kept by an earlier version was not opened: the copy kept before
/// bringing it up could not be written ([SqlLedgerDataSource.bringUp]).
final class UpgradeHeld implements Exception {
  const UpgradeHeld(this.failure);

  final UpgradeBackupFailed failure;

  @override
  String toString() => 'UpgradeHeld(${failure.problem.name})';
}
