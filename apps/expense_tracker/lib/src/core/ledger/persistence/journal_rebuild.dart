import 'dart:isolate';

import 'package:kernel/kernel.dart';
import 'package:storage/storage.dart';

import '../journal/book_mapping.dart';
import '../journal/old_shapes.dart';
import '../journal/replay.dart';
import '../models/models.dart';
import '../../diagnostics/error_log.dart';
import 'book_opening.dart';
import 'write_batch.dart' show Collection;

/// How many records are posted and written at a time when the whole book
/// is posted afresh. Each part is let go once written, so the worker
/// keeps little alive: the screen's isolate shares its collections of
/// garbage (one isolate group), and what survives each is what holds the
/// screen (D51).
const journalApartChunk = 1000;

/// What posting the whole book afresh answers (the storage package's
/// `PostedApart`): the report, and the account tree.
typedef PostedBook = ({ReplayReport result, List<LedgerAccount> accounts});

/// Where each part posted goes, as soon as it is (written into the file
/// while the rest is still posted).
typedef AddPart = void Function(FreshPostingStore part);

/// The work of opening the book on a worker isolate beside the records
/// (`EncryptedDatabase.workApart`), decision D51: every row read in one
/// read and decoded once ([decodeBook]); what has expired dropped
/// ([DecodedBook.expired], [trashFrom]); the holdings replayed as of
/// [today]. When the journal is kept by [rules] and is not the records'
/// own, the book is sent to [books] for the screens and posted afresh
/// from the same entries ([postBook]), the mark of the records' revision
/// kept last; otherwise it is answered.
///
/// With [split], when the phone has a core beside this worker's, a book
/// of [splitFrom] entries or more has the last half of its entries
/// decoded by [decodeApart] (on a second worker) while this one decodes
/// the first. That second worker only saves time: one that cannot be
/// started, or fails, has its half decoded here after all, and a real
/// fault in those rows then throws here as it would have. Made here, at
/// the top level, so the closure carries only what it is given;
/// [decodeApart] is a top-level function for the same reason.
Future<OpenedBook> Function(ApartStore) openingWork({
  required SendPort books,
  required DateTime today,
  required DateTime trashFrom,
  required int? rules,
  bool split = false,
  int splitFrom = splitOpeningFrom,
  DecodeApart decodeApart = decodedApart,
}) => (store) async {
  final watch = Stopwatch()..start();
  final shelves = shelvesOf(store.read().rows);
  final entries = shelves[Collection.entry.name] ?? const <StoredRow>[];
  final halves = split && entries.length >= splitFrom
      ? await _decodedInHalves(entries, decodeApart)
      : null;
  final book = decodeBook(
    shelves,
    trashFrom: trashFrom,
    today: today,
    entryTail: halves?.records,
  );
  if (book.expired.isNotEmpty) {
    store.write(book.expired, counts: book.expiredCounts);
  }
  final worked = (
    us: watch.elapsedMicroseconds,
    split: halves?.apart ?? false,
    helperFault: halves?.fault,
  );
  final mark = rules == null ? null : (rules: rules, revision: store.revision);
  if (mark == null || store.journal.mark == mark) {
    // Nothing to post: the book goes back whole as the worker ends,
    // handed over, never copied (a copy left for the screen's isolate to
    // collect held it at the next large change).
    return (book: book, posted: null, worked: worked);
  }
  // Sent now, a copy, so the screens open while the book is posted.
  books.send((book: book, worked: worked));
  final start = holdingsOf(marketFrom(readableMarket(book.market)));
  final posted = await store.post(
    (add) async => postBook(book, add, start),
    mark: mark,
  );
  return (book: null, posted: posted, worked: worked);
};

/// How many entries a book has from which [openingWork] decodes half of
/// them on a second worker: below it, starting one costs about what it
/// saves.
const splitOpeningFrom = 20000;

/// Decodes the rows of one shelf elsewhere, as [decodeRows] does: what
/// [openingWork] hands the last half of a large book's entries to.
typedef DecodeApart = Future<DecodedRecords> Function(List<StoredRow> rows);

/// [rows] decoded on a worker of their own ([decodeRows]), handed back
/// whole. At the top level, so the closure carries [rows] alone.
Future<DecodedRecords> decodedApart(List<StoredRow> rows) =>
    Isolate.run(() => decodeRows(rows));

/// [entries] decoded in two halves at once: the first here, the last by
/// [decodeApart]. Should that one not start, or fail, its half is
/// decoded here after the first, and what it threw is told with the book
/// (`helperFault`); one still running when the first half throws is let
/// go of, its outcome never left unhandled. The records of both, in row
/// order, whether the last half was decoded apart, and what it threw.
Future<({DecodedRecords records, bool apart, String? fault})> _decodedInHalves(
  List<StoredRow> entries,
  DecodeApart decodeApart,
) async {
  final half = entries.length ~/ 2;
  final tailRows = entries.sublist(half);
  // Started first, so both halves are decoded at once; a start that
  // throws at once is a failure like any other.
  final tail = Future.sync(() => decodeApart(tailRows))..ignore();
  final head = decodeRows(entries.sublist(0, half));
  String? fault;
  // Told as text: what was thrown need not be sendable to the screen's
  // isolate, which records it (`SqlLedgerDataSource`).
  // Exception to error words: recorded in the ErrorLog, never shown.
  void report(Object error) => fault = ErrorLog.describe(error);
  DecodedRecords rest;
  try {
    rest = await tail;
  } on Object catch (error) {
    // Only the time saved is lost: told with the book and recorded on
    // the screen's isolate, the half decoded here; a fault in its rows
    // themselves throws now as it would have.
    report(error);
    rest = decodeRows(tailRows);
  }
  return (
    records: (
      records: [...head.records, ...rest.records],
      aside: [...head.aside, ...rest.aside],
    ),
    apart: fault == null,
    fault: fault,
  );
}

/// How reading the book on its worker went: how long it took, in
/// microseconds, from the first row read until it was ready to hand
/// over; whether the last half of its entries was decoded on a second
/// worker meanwhile ([openingWork]); and what that worker threw when it
/// could not be started or failed, its half then decoded on this one.
typedef OpeningWorked = ({int us, bool split, String? helperFault});

/// What opening the book on its worker answers: the book itself when
/// nothing was posted (else it was sent as soon as it was read, as a
/// [ReadBook]), what posting afresh found, and how reading the book went
/// there.
typedef OpenedBook = ({
  DecodedBook? book,
  ReplayReport? posted,
  OpeningWorked worked,
});

/// The book read on its worker, and how reading it went there.
typedef ReadBook = ({DecodedBook book, OpeningWorked worked});

/// The work of posting the whole book afresh, to run on a worker isolate
/// beside the records (`EncryptedDatabase.postApart`): it reads the
/// accounts, categories and entries from the rows as the book opens them
/// ([decodeBook]), leaves out those set aside as it opened ([aside],
/// `shelf/id`), and posts them with [start], the stocks held from the
/// start ([postBook]). Made here, at the top level, so the closure
/// carries only what it is given.
Future<PostedBook> Function(List<KeptRow>, AddPart) postingWork({
  required Set<String> aside,
  required List<Holding> start,
}) =>
    (rows, add) async => postBook(
      decodeBook(
        shelvesOf([
          for (final r in rows)
            if (!aside.contains('${r.shelf}/${r.id}'))
              StoredRow(r.seq, r.shelf, r.id, r.body),
        ]),
      ),
      add,
      start,
    );

/// Posts the entries of [book] with [start], the stocks held from the
/// start, into parts handed to [add] as each is done: those in no stream
/// [journalApartChunk] at a time, as they come; those in a stream, whose
/// postings read the ones before, after them, in book order. The report
/// and the account tree.
PostedBook postBook(DecodedBook book, AddPart add, List<Holding> start) {
  final byId = {for (final e in book.entries) e.id: e};
  final refunds = <String, List<Entry>>{};
  for (final e in book.entries) {
    if (e.refundOf case final of?) (refunds[of] ??= []).add(e);
  }
  final mapping = BookMapping(
    accounts: book.accounts,
    categories: book.categories,
    start: start,
    entryById: (id) => byId[id],
    refundsOf: (id) => refunds[id] ?? const [],
  );
  final tree = AccountTree(mapping.tree);
  final report = ReplayReport();
  final entries = book.entries;
  final places = book.entryPlaces;
  final streamed = <(LedgerIntent, Entry, Set<OldShape>)>[];
  for (var at = 0; at < entries.length; at += journalApartChunk) {
    final part = FreshPostingStore();
    final journal = Journal(
      registry: registryFor(() => mapping),
      accounts: tree,
      store: part,
      source: (_) => null,
    );
    final alone = <LedgerIntent>[];
    final records = <IntentId, (Entry, Set<OldShape>)>{};
    for (var i = at; i < _min(at + journalApartChunk, entries.length); i++) {
      final entry = entries[i];
      final mapped = mapping.map(entry, places[i]);
      mapped.accounts.forEach(tree.put);
      if (journal.streamsOf(mapped.intent).isEmpty) {
        alone.add(mapped.intent);
        records[mapped.intent.id] = (entry, mapped.shapes);
      } else {
        streamed.add((mapped.intent, entry, mapped.shapes));
      }
    }
    postIntents(journal, alone, report, records, mapping: mapping);
    add(part);
  }
  streamed.sort((a, b) {
    final byPlace = comparePositions(a.$1.position, b.$1.position);
    return byPlace != 0 ? byPlace : a.$1.id.value.compareTo(b.$1.id.value);
  });
  final main = FreshPostingStore();
  final journal = Journal(
    registry: registryFor(() => mapping),
    accounts: tree,
    store: main,
    source: (_) => null,
  );
  postIntents(journal, mapping.openings, report, const {});
  for (var at = 0; at < streamed.length; at += journalApartChunk) {
    final chunk = streamed.sublist(
      at,
      _min(at + journalApartChunk, streamed.length),
    );
    postIntents(
      journal,
      [for (final (intent, _, _) in chunk) intent],
      report,
      {for (final (intent, entry, shapes) in chunk) intent.id: (entry, shapes)},
      mapping: mapping,
    );
  }
  add(main);
  return (result: report, accounts: tree.all.toList());
}

int _min(int a, int b) => a < b ? a : b;
