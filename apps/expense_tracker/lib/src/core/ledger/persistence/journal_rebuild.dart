import 'dart:isolate';

import 'package:kernel/kernel.dart';
import 'package:storage/storage.dart';

import '../journal/book_mapping.dart';
import '../journal/old_shapes.dart';
import '../journal/replay.dart';
import '../models/models.dart';
import 'book_opening.dart';

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
/// ([DecodedBook.expired], [trashFrom]); the book sent to [books] for the
/// screens; then, when the journal is kept by [rules] and is not the
/// records' own, the whole book posted afresh from the same entries
/// ([postBook]), the mark of the records' revision kept last. What
/// posting found; null when nothing was posted. Made here, at the top
/// level, so the closure carries only what it is given.
Future<ReplayReport?> Function(ApartStore) openingWork({
  required SendPort books,
  required DateTime trashFrom,
  required int? rules,
}) => (store) async {
  final book = decodeBook(shelvesOf(store.read().rows), trashFrom: trashFrom);
  if (book.expired.isNotEmpty) {
    store.write(book.expired, counts: book.expiredCounts);
  }
  books.send(book);
  if (rules == null) return null;
  final mark = (rules: rules, revision: store.revision);
  if (store.journal.mark == mark) return null;
  final start = holdingsOf(marketFrom(readableMarket(book.market)));
  return store.post((add) async => postBook(book, add, start), mark: mark);
};

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
  final mapping = BookMapping(
    accounts: book.accounts,
    categories: book.categories,
    start: start,
  );
  final tree = AccountTree(mapping.tree);
  final report = ReplayReport();
  final entries = book.entries;
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
    for (final entry in entries.sublist(
      at,
      _min(at + journalApartChunk, entries.length),
    )) {
      final mapped = mapping.map(entry, book.entrySeqs[entry.id]!);
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
