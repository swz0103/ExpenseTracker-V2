// Exception to ledger words: a new book's first categories and accounts
// are written as data, and the diagnostics log is labelled in words.
// Exception to file length: this is the one place rows are read from and
// written to the store; what it notes of them as it reads (rows set
// aside, unknown fields, records naming a category by name) is checked
// on every write, and split across files those notes would have to be
// public. The pure parts live in codec/ and book_migrations.dart.

import 'dart:async' show FutureOr;
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:isolate';

import 'package:core/app_core.dart';
import 'package:core/constants/retention.dart';
import 'package:core/foundation_values.dart';
import 'package:core/money/amount_parser.dart' show parseDecimal;
import 'package:flutter/foundation.dart' show mapEquals;
import 'package:domain/investments.dart'
    show DoubtedFigure, doubtsStanding, takesFetched;
import 'package:market/market_data.dart';
import 'package:storage/storage.dart';

import 'book_migrations.dart';
import 'book_opening.dart';
import 'damage_report.dart';
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

/// The collection of the last closing prices and rate board, kept so holdings
/// and foreign accounts are valued offline.
const _market = marketShelf;

/// When each record was deleted, by `collection/id`, so a deletion can be
/// told from a record never kept (for a later sync); dropped when the id
/// is kept again, and once [trashRetention] has passed. Nothing reads them
/// but a backup's check.
const _gone = goneShelf;

/// Forms put aside in the composer, by tab ([WriteBatch.drafts]).
const _draft = draftShelf;

/// The collections whose deletions are noted in [_gone].
const _noted = {
  Collection.account,
  Collection.category,
  Collection.entry,
  Collection.budget,
  Collection.recurring,
};

/// Up to this many rows a book is read and decoded here, on the screen's
/// isolate, as a small book takes less than a frame; above it, or when
/// the journal is kept, on a worker ([EncryptedDatabase.workApart]).
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
    fault: _journalFault,
  );

  /// Told when a page of the journal's tables is found damaged (D102):
  /// the connection is of no more use, and the database is to be made
  /// again from its records. Answers whether the report was acted on;
  /// once it was, it is not told again this session ([DamageReport]).
  Future<bool> Function(Object error)? get onJournalDamaged =>
      _journalDamage.tell;
  set onJournalDamaged(Future<bool> Function(Object error)? tell) =>
      _journalDamage.tell = tell;

  final _journalDamage = DamageReport();

  void _journalFault(Object error) {
    if (EncryptedDatabase.damageIn(error)) _journalDamage(error);
  }

  /// The whole journal posted afresh on a worker isolate (D51): from the
  /// records as kept, those set aside as the book opened left out, the
  /// mark of the records' revision kept last.
  Future<ReplayReport> _postJournalApart(List<Holding> start) async {
    return _whenQuiet(
      () => _store.postApart(
        postingWork(
          aside: {for (final r in _aside.rows) '${r.shelf}/${r.id}'},
          start: start,
        ),
        mark: (rules: journalRules, revision: _store.revision),
      ),
    );
  }

  /// Where each entry kept stands, by id, read from the store: only
  /// when the journal is posted afresh on this isolate (no worker).
  Map<String, int> _entrySeqs() => {
    for (final row in _store.rows(shelf: Collection.entry.name))
      row.id: row.seq,
  };

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
    switch (await _whenQuiet(() => standingOf(_store))) {
      case BookStanding.fresh:
        await _whenQuiet(_start);
      case BookStanding.behind:
        if (!withoutBackup) {
          if (await beforeUpgrade?.call() case final UpgradeBackupFailed no) {
            return no;
          }
        }
        await _whenQuiet(() => bringUpBook(_store));
      case BookStanding.current || BookStanding.ahead:
        break;
    }
    return null;
  }

  Future<Ledger> _load() async {
    final watch = Stopwatch()..start();
    _aside.clear();
    _named.clear();
    _namesOf.clear();
    // Never read a book left behind: the copy before its upgrade was not
    // kept, and the person has not chosen to go on without it.
    if (await bringUp() case final no?) throw UpgradeHeld(no);
    final today = _today();
    final trashFrom = today.subtract(trashRetention);
    final Future<ReplayReport?>? posting;
    final DecodedBook book;
    OpeningWorked? worked;
    if (keepsJournal || _store.count > _decodeApart) {
      (:book, :worked, posting: posting) = await _openApart(today, trashFrom);
      if (worked.helperFault case final fault?) {
        // The book opened all the same, only later: its second worker's
        // half was decoded on the first.
        ErrorLog.instance.record(ErrorSteps.openingHelper, StateError(fault));
      }
    } else {
      posting = null;
      book = decodeBook(await _shelves(), trashFrom: trashFrom, today: today);
      if (book.expired.isNotEmpty) {
        await _whenQuiet(
          () => _store.write(
            (w) => _apply(w, book.expired),
            counts: book.expiredCounts,
          ),
        );
      }
    }
    for (final row in book.aside) {
      _aside.adopt(row);
    }
    book.namesOf.forEach(_indexFound);
    _refs.fill(book.categoryNames);
    final market = marketFrom(_readableMarket(book.market));
    final ledger = Ledger(
      today: today,
      clock: _today,
      accounts: book.accounts,
      categories: book.categories,
      entries: book.entries,
      entryPlaces: book.entryPlaces,
      holdings: holdingsOf(market),
      budgets: book.budgets,
      recurring: book.recurring,
      rates: market.rates,
      sellRates: market.sellRates,
      moves: market.moves,
      quotedOn: market.quotedOn,
      quoteDays: market.days,
      trash: book.trash,
      receipts: book.receipts,
      drafts: book.drafts,
      readHoldings: book.holdings,
      dataSource: this,
    );
    if (!_aside.isEmpty) {
      ErrorLog.instance.record(
        ErrorSteps.bookOpen,
        StateError('${_aside.rows.length} rows set aside'),
      );
    }
    if (keepsJournal) journal.open(ledger, posted: posting);
    lastOpening = (
      us: watch.elapsedMicroseconds,
      workerUs: worked?.us,
      split: worked?.split ?? false,
    );
    return ledger;
  }

  /// How long the last [load] took, and how much of it the book's worker
  /// spent reading it (null when it was read here, a small book), in
  /// microseconds: what is left is starting the worker, handing the book
  /// back and making the ledger of it, the part the screen's isolate
  /// waits on or does (open_gate_test.dart); and whether the worker had
  /// half of the entries decoded on a second one (`openingWork`). Null
  /// before a load.
  ({int us, int? workerUs, bool split})? lastOpening;

  /// Reads and decodes the book on a worker isolate, which drops what has
  /// expired ([DecodedBook.expired]) and hands the book here as soon as it
  /// is read; when the journal is kept, it then posts the whole book
  /// afresh there unless the journal is the records' own (decision D51:
  /// the book decoded once, for the screens and the journal). The book,
  /// how long the worker took to read it, and what posting it found (null
  /// when nothing was posted).
  Future<
    ({DecodedBook book, OpeningWorked worked, Future<ReplayReport?>? posting})
  >
  _openApart(DateTime today, DateTime trashFrom) async {
    final books = ReceivePort();
    try {
      // Taken in the turn the store is found free; the work itself runs on.
      late final Future<OpenedBook> work;
      await _whenQuiet(() {
        work = _store.workApart(
          openingWork(
            books: books.sendPort,
            today: today,
            trashFrom: trashFrom,
            rules: keepsJournal ? journalRules : null,
            // A second worker only where there is a core beside the
            // worker's: the screen's isolate only waits for the book
            // meanwhile.
            split: Platform.numberOfProcessors > 1,
          ),
        );
      });
      // The book comes back whole when nothing is posted; else it is sent
      // as soon as it is read, and posted on. A fault before either is the
      // opening's.
      final first = await Future.any<Object?>([books.first, work]);
      return switch (first) {
        (book: final DecodedBook book, :final OpeningWorked worked) => (
          book: book,
          worked: worked,
          posting: work.then((opened) => opened.posted),
        ),
        (
          book: final DecodedBook book,
          posted: _,
          :final OpeningWorked worked,
        ) =>
          (
            book: book,
            worked: worked,
            posting: keepsJournal ? Future<ReplayReport?>.value() : null,
          ),
        _ => throw StateError('the book was not read'),
      };
    } finally {
      books.close();
    }
  }

  /// Applies [changes] through [w].
  static void _apply(RowWriter w, List<RowChange> changes) =>
      changes.forEach(w.apply);

  /// Gives a ledger just made its first categories, and a cash and a bank
  /// account, so the first entry can be written at once; and notes that
  /// it is at this version, in the same write.
  void _start() {
    _write(
      WriteBatch(
        categories: starterCategories(),
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
        // the middle of it, and before another can start.
        await _whenQuiet(() => _write(batch));
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

  /// Done once no other isolate uses the store (a write apart, a
  /// backup's read, a posting afresh). The journal's keeper waits with it
  /// and asks [EncryptedDatabase.busyApart] again in the same turn as it
  /// works; every write here goes through [_whenQuiet].
  Future<void> _quiet() async {
    while (_store.busyApart) {
      await _store.idle;
    }
  }

  /// Runs [then] once no other isolate uses the store (a write apart, or
  /// a backup's read), in the same turn as the last look at it: nothing,
  /// a backup starting included, comes between the look and [then] (D41).
  /// The one way a change of the open book reaches the store.
  Future<T> _whenQuiet<T>(FutureOr<T> Function() then) async {
    while (_store.busyApart) {
      await _store.idle;
    }
    // [then] starts here, in this turn; a write apart is awaited whole.
    return await then();
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
    _indexFound('$shelf/$id', found);
  }

  /// Notes that the record [key] (`shelf/id`) names [names] by name.
  void _indexFound(String key, Set<String> names) {
    _namesOf[key] = names;
    for (final name in names) {
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
        move: w.move,
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
      move: (from, shelf, id, body) =>
          changes.add(RowChange.move(from, shelf, id, body)),
      drop: (shelf, id) => changes.add(RowChange.drop(shelf, id)),
      after: after,
    )) {
      await breathe();
    }
    await _whenQuiet(
      () => _store.writeApart(changes, counts: !batch.onlyDrafts),
    );
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

  /// The rows [batch] puts in place, moves and drops, handed to [put],
  /// [move] and [drop] in the order they are written, a record at a time:
  /// an entry going to the trash, or coming back from it, is moved, so it
  /// keeps its place among the entries (D75). It yields
  /// after each, so a caller may let the screen draw. What to note once
  /// they are kept is added to [after]. [claim] is the writer of a
  /// transaction under way, for the records that named a category by
  /// name; none when the batch claims none ([keep] writes those at once).
  Iterable<void> _fill(
    WriteBatch batch, {
    required void Function(String shelf, String id, String body) put,
    required void Function(String from, String shelf, String id, String body)
    move,
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

    // An entry dropped and kept in the trash in the same change goes
    // there, and one kept again and dropped from the trash comes back.
    final droppedFrom = <Collection, Set<String>>{};
    for (final (collection, key) in batch.dropped) {
      (droppedFrom[collection] ??= {}).add(key);
    }
    final toTrash = {
      for (final t in batch.trash)
        if (droppedFrom[Collection.entry]?.contains(t.entry.id) ?? false)
          t.entry.id,
    };
    final fromTrash = {
      for (final e in batch.entries)
        if (droppedFrom[Collection.trash]?.contains(e.id) ?? false) e.id,
    };

    // What the data source notes of the rows written, once they are kept:
    // nothing of a write that throws.
    void keep(Collection collection, String id, Map<String, Object?> json) {
      mayChange(collection.name, id);
      final from = switch (collection) {
        Collection.trash when toTrash.contains(id) => Collection.entry,
        Collection.entry when fromTrash.contains(id) => Collection.trash,
        _ => null,
      };
      if (from == null) {
        put(collection.name, id, text(collection, id, json));
      } else {
        mayChange(from.name, id);
        move(from.name, collection.name, id, text(collection, id, json));
      }
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
      final moved = switch (collection) {
        Collection.entry => toTrash.contains(id),
        Collection.trash => fromTrash.contains(id),
        _ => false,
      };
      if (!moved) drop(collection.name, id);
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

  /// Throws a [FormatException] for a book restored into [staging] whose
  /// categories are on a loop of parents (D103): records that each read
  /// alone ([check]) but no book could be made of.
  static void checkRestored(EncryptedDatabase staging) {
    final rows = staging.rows(shelf: Collection.category.name);
    final json = decodeBodies([for (final r in rows) r.body]).values;
    final refs = CategoryRefs()
      ..fill([
        for (final j in json)
          if (j case {'id': final String id, 'name': final String name})
            (id, name),
      ]);
    final categories = <Category>[];
    for (final j in json) {
      if (j is! Map<String, Object?>) continue;
      categories.add(
        categoryFromJson(upgradeRecord(Collection.category.name, j), refs),
      );
    }
    if (categoriesOnLoops(categories).isNotEmpty) {
      throw const FormatException(parentLoopProblem);
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
      marketFrom([StoredRow(0, collection, id, body)]);
      return;
    }
    checkRecord(collection, upgradeRecord(collection, json));
  }

  /// The rows of [rows] of the [_market] collection that can be read: a
  /// close or rate kept that cannot is fetched again, and noted.
  static List<StoredRow> _readableMarket(List<StoredRow>? rows) =>
      readableMarket(
        rows,
        report: (error) => ErrorLog.instance.record('讀取行情', error),
      );

  // Market data.

  /// The closes and board last fetched, for `HoldingCommands.setMarket`.
  ({
    List<Holding> holdings,
    Map<String, double> moves,
    Map<String, double> rates,
    Map<String, double> sellRates,
    DateTime? quotedOn,
    Map<String, DateTime> days,
  })
  market() {
    final kept = marketFrom(_readableMarket(_store.rows(shelf: _market)));
    return (
      holdings: holdingsOf(kept),
      moves: kept.moves,
      rates: kept.rates,
      sellRates: kept.sellRates,
      quotedOn: kept.quotedOn,
      days: kept.days,
    );
  }

  /// Fetches 臺灣銀行's board: the spot buying and selling rate of each
  /// currency, what a foreign balance held and owed is worth in NT$
  /// (D59). Returns whether any rate changed.
  Future<bool> refreshRates() async {
    final gateway = _gateway;
    if (gateway == null) return false;
    final board = (await gateway.bankRates()).value;
    if (board == null) return false;
    final quoted = <String, double>{};
    final quotedSelling = <String, double>{};
    for (final MapEntry(key: code, value: row) in board.rates.entries) {
      if (row.rateFor(BoardSide.buying) case final rate?) {
        quoted[code] = rate.numerator / rate.denominator;
      }
      if (row.rateFor(BoardSide.selling) case final rate?) {
        quotedSelling[code] = rate.numerator / rate.denominator;
      }
    }
    final boardDay = board.asOf.asUtcMidnight;
    return _whenQuiet(() {
      final kept = marketFrom(_readableMarket(_store.rows(shelf: _market)));
      // A rate too far from the one kept is doubted (D95) unless there is
      // reason to take it (D101: found again, or the one kept old): the
      // one kept stays, the doubted one is kept to weigh the next fetch
      // by, and the doubt is noted; buying and selling alike (D59).
      final doubted = <String>{};
      final keptDays = switch (kept.ratesOn) {
        final on? => boardDay.difference(on).inDays,
        null => null,
      };
      (Map<String, double>, Map<String, DoubtedFigure>) sane(
        Map<String, double> quotes,
        Map<String, double> before,
        Map<String, DoubtedFigure> doubtedBefore,
      ) {
        final taken = <String, double>{};
        // As for closes: a doubt of a code not on this board is kept to
        // weigh its next fetch by (review 18), until it is too old to
        // (review 25).
        final held = doubtsStanding(doubtedBefore, boardDay);
        for (final MapEntry(key: code, value: rate) in quotes.entries) {
          final was = before[code];
          if (takesFetched(
            kept: was,
            fetched: rate,
            keptDaysAgo: keptDays,
            doubtedBefore: held[code]?.figure,
          )) {
            taken[code] = rate;
            held.remove(code);
          } else {
            doubted.add(code);
            if (rate.isFinite && rate > 0) {
              held[code] = (figure: rate, day: boardDay);
            }
            if (was != null) taken[code] = was;
          }
        }
        return (taken, held);
      }

      final (fetched, heldBuying) = sane(quoted, kept.rates, kept.doubtedRates);
      final (selling, heldSelling) = sane(
        quotedSelling,
        kept.sellRates,
        kept.doubtedSellRates,
      );
      doubtfulRates = List.unmodifiable(doubted);
      if (doubted.isNotEmpty) {
        ErrorLog.instance.record(
          ErrorSteps.doubtfulQuote,
          StateError('rates of ${doubted.join(', ')} set aside'),
        );
      }
      final ratesMoved =
          !mapEquals(fetched, kept.rates) ||
          !mapEquals(selling, kept.sellRates);
      if (fetched.isEmpty ||
          (!ratesMoved &&
              mapEquals(heldBuying, kept.doubtedRates) &&
              mapEquals(heldSelling, kept.doubtedSellRates))) {
        return false;
      }
      // Fetched, not changed by the person: no new backup is due for it.
      // The board's day moves only with a rate taken: the day the rates
      // kept are of.
      _store.write(
        (w) => w.put(
          _market,
          'rates',
          jsonEncode({
            'asOf': ratesMoved || kept.ratesOn == null
                ? '${board.asOf}'
                : '${BusinessDate.of(kept.ratesOn!)}',
            'rates': fetched,
            'sell': selling,
            ..._doubtsJson('doubted', heldBuying),
            ..._doubtsJson('doubtedSell', heldSelling),
          }),
        ),
        counts: false,
      );
      return ratesMoved;
    });
  }

  /// The codes the last [refreshQuotes] found no close for: not quoted
  /// by either exchange, or out of reach.
  List<String> unquoted = const [];

  static double? _neverReshaped(String code, DateTime? day) => null;

  /// [doubts] as kept in a market row: the figures under [field], their
  /// days under [field]`On` (marketFrom); nothing when there are none.
  static Map<String, Object> _doubtsJson(
    String field,
    Map<String, DoubtedFigure> doubts,
  ) => {
    if (doubts.isNotEmpty) ...{
      field: {
        for (final MapEntry(:key, :value) in doubts.entries) key: value.figure,
      },
      '${field}On': {
        for (final MapEntry(:key, :value) in doubts.entries)
          key: value.day.toIso8601String(),
      },
    },
  };

  /// The codes whose close the last [refreshQuotes] doubted (D95): more
  /// than `doubtfulMoveFactor` times away from the one kept. The one kept
  /// stays, with its day, so the holding shows its older close.
  List<String> doubtfulCloses = const [];

  /// The currencies whose rate the last [refreshRates] doubted (D95); the
  /// rate kept stays.
  List<String> doubtfulRates = const [];

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
  /// changed. [reshapedBy] tells how many times the splits, stock
  /// dividends and reductions the book holds of a stock after a day
  /// multiplied its shares, null for none (D101).
  Future<bool> refreshQuotes(
    Iterable<String> codes, {
    double? Function(String code, DateTime? day) reshapedBy = _neverReshaped,
  }) async {
    final gateway = _gateway;
    if (gateway == null) return false;
    final kept = await _whenQuiet(
      () => marketFrom(_readableMarket(_store.rows(shelf: _market))),
    );
    final prices = {...kept.prices};
    final moves = {...kept.moves};
    final names = {...kept.names};
    final days = {...kept.days};
    final today = _today();
    // A doubt too old to weigh a fetch by is let go of (review 25).
    final doubtedBefore = doubtsStanding(kept.doubtedCloses, today);
    var quotedOn = kept.quotedOn;
    var changed = doubtedBefore.length != kept.doubtedCloses.length;
    final missed = <String>[];
    final doubted = <String>[];
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
      final day = close.asOf.asUtcMidnight;
      // A close dated after today is no close; one too far from the one
      // kept is doubted (D95). Either way the one kept stays, with its
      // day, and the day the holdings are quoted on does not move for it.
      if (day.isAfter(today)) {
        missed.add(code);
        continue;
      }
      final keptOn = days[code];
      if (!takesFetched(
        kept: prices[code],
        fetched: price,
        keptDaysAgo: keptOn == null ? null : day.difference(keptOn).inDays,
        doubtedBefore: doubtedBefore[code]?.figure,
        reshapedBy: reshapedBy(code, keptOn),
      )) {
        doubted.add(code);
        // Kept to weigh the next fetch by (D101), with its day.
        final doubt = (figure: price, day: day);
        if (doubtedBefore[code] != doubt && price.isFinite && price > 0) {
          doubtedBefore[code] = doubt;
          changed = true;
        }
        continue;
      }
      if (doubtedBefore.remove(code) != null) changed = true;
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
    doubtfulCloses = List.unmodifiable(doubted);
    if (doubted.isNotEmpty) {
      ErrorLog.instance.record(
        ErrorSteps.doubtfulQuote,
        StateError('closes of ${doubted.join(', ')} set aside'),
      );
    }
    // A day kept from before that is after today (written by an earlier
    // version) is let go of: the holdings are quoted on no day ahead.
    if (quotedOn != null && quotedOn.isAfter(today)) {
      quotedOn = null;
      for (final day in days.values) {
        if (!day.isAfter(today) &&
            (quotedOn == null || day.isAfter(quotedOn))) {
          quotedOn = day;
        }
      }
      changed = true;
    }
    if (changed) {
      await _whenQuiet(
        () => _store.write(
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
              ..._doubtsJson('doubted', doubtedBefore),
            }),
          ),
          counts: false,
        ),
      );
    }
    return changed;
  }
}

/// A book kept by an earlier version was not opened: the copy kept before
/// bringing it up could not be written ([SqlLedgerDataSource.bringUp]).
final class UpgradeHeld implements Exception {
  const UpgradeHeld(this.failure);

  final UpgradeBackupFailed failure;

  @override
  String toString() => 'UpgradeHeld(${failure.problem.name})';
}
