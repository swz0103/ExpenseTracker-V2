import 'package:kernel/kernel.dart';

import '../journal/book_mapping.dart';
import '../journal/old_shapes.dart';
import '../journal/replay.dart';
import '../models/models.dart';
import 'codec/category_refs.dart';
import 'codec/record_json.dart';
import 'codec/row_decoding.dart';
import 'ledger_data_source.dart' show Collection;
import 'record_version.dart';

/// How many records are read, posted and written at a time when the
/// whole book is posted afresh. Each part is let go once written, so
/// the worker keeps little alive: the screen's isolate shares its
/// collections of garbage (one isolate group), and what survives each is
/// what holds the screen (D51).
const journalApartChunk = 1000;

/// A record as the store keeps it (the storage package's `KeptRow`).
typedef StoredRecord = ({String shelf, String id, int seq, String body});

/// What posting the whole book afresh answers (the storage package's
/// `PostedApart`): the report, and the account tree.
typedef PostedBook = ({ReplayReport result, List<LedgerAccount> accounts});

/// Where each part posted goes, as soon as it is (written into the file
/// while the rest is still posted).
typedef AddPart = void Function(FreshPostingStore part);

/// The work of posting the whole book afresh, to run on a worker isolate
/// beside the records (`EncryptedDatabase.postApart` in the storage
/// package): it reads the accounts, categories and entries from the rows
/// as the book opens them, leaves out those set aside as it opened
/// ([aside], `shelf/id`), and posts them with [start], the stocks held
/// from the start. Entries in no stream are read, posted and written
/// [journalApartChunk] at a time; those in a stream, whose postings read
/// the ones before, after them, in book order. Made here, at the top
/// level, so the closure carries only what it is given.
Future<PostedBook> Function(List<StoredRecord>, AddPart) postingWork({
  required Set<String> aside,
  required List<Holding> start,
}) =>
    (rows, add) => _postBook(rows, add, aside, start);

/// A record's JSON as this version reads it, or null for one set aside.
/// Every record the book set aside as it opened is left out by [aside],
/// so any other is read as the book read it; one that cannot be read
/// now fails the posting, which leaves the journal as it was (its mark
/// not moved) and is kept in the diagnostics log by the keeper.
Map<String, Object?>? _readable(StoredRecord row, Set<String> aside) {
  if (aside.contains('${row.shelf}/${row.id}')) return null;
  final json = readableRecord(row.body);
  if (json == null) return null;
  final version = versionOf(json);
  if (version == null || version > recordVersion) return null;
  return upgradeRecord(row.shelf, json);
}

Future<PostedBook> _postBook(
  List<StoredRecord> rows,
  AddPart add,
  Set<String> aside,
  List<Holding> start,
) async {
  List<Map<String, Object?>> of(Collection c) => [
    for (final row in rows)
      if (row.shelf == c.name) ?_readable(row, aside),
  ];
  final categoryJson = of(Collection.category);
  final names = [
    for (final json in categoryJson)
      if (json case {'id': final String id, 'name': final String name})
        (id, name),
  ];
  final refs = CategoryRefs()..fill(names);
  final accounts = of(Collection.account).map(accountFromJson).toList();
  final categories = [for (final j in categoryJson) categoryFromJson(j, refs)];
  final entries = [
    for (final row in rows)
      if (row.shelf == Collection.entry.name) row,
  ];
  final mapping = BookMapping(
    accounts: accounts,
    categories: categories,
    start: start,
  );
  final tree = AccountTree(mapping.tree);
  final report = ReplayReport();
  // What stands alone (in no stream) is posted and written a part at a
  // time; what stands in a stream is kept, to be posted in book order
  // after.
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
    for (final row in entries.sublist(
      at,
      _min(at + journalApartChunk, entries.length),
    )) {
      final json = _readable(row, aside);
      if (json == null) continue;
      final entry = entryFromJson(json, refs);
      final mapped = mapping.map(entry, row.seq);
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
