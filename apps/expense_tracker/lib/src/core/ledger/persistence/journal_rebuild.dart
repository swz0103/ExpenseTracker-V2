import 'dart:isolate';

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

/// How many isolates read and post the entries that stand alone (in no
/// stream) when the whole book is posted afresh, while the isolate that
/// owns the file writes each slice as it comes: one core each on a
/// four-core phone, the screen's own isolate never one of them.
const journalSlices = 3;

/// How many intents in a stream (trades, instalments) are posted at a
/// time, one after the other, when the whole book is posted afresh.
const journalStreamChunk = 1000;

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
/// from the start. Entries in no stream are read and posted in
/// [journalSlices] isolates at once; those in a stream, whose postings
/// read the ones before, after them, in book order. Made here, at the top
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
  final size = (entries.length / journalSlices).ceil();
  final slices = await Future.wait([
    for (var k = 0; k * size < entries.length; k++)
      _runSlice(
        entries.sublist(k * size, _min((k + 1) * size, entries.length)),
        aside,
        names,
        accounts,
        categories,
        start,
      ).then((slice) {
        // Written while the other slices are still being posted.
        add(slice.fresh);
        return slice;
      }),
  ]);

  // What stands in a stream, from every slice, posted here in book order.
  final mapping = BookMapping(
    accounts: accounts,
    categories: categories,
    start: start,
  );
  final tree = AccountTree(mapping.tree);
  final report = ReplayReport();
  final streamed = <(LedgerIntent, Entry, Set<OldShape>)>[];
  for (final slice in slices) {
    slice.accounts.forEach(tree.put);
    report.add(slice.report);
    streamed.addAll(slice.streamed);
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
  for (var at = 0; at < streamed.length; at += journalStreamChunk) {
    final chunk = streamed.sublist(
      at,
      _min(at + journalStreamChunk, streamed.length),
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

/// [_postSlice] on an isolate of its own. At the top level, so the
/// closure sent carries these values alone.
Future<_Slice> _runSlice(
  List<StoredRecord> rows,
  Set<String> aside,
  List<(String, String)> names,
  List<Account> accounts,
  List<Category> categories,
  List<Holding> start,
) => Isolate.run(
  () => _postSlice(rows, aside, names, accounts, categories, start),
);

/// One slice of the entries read, mapped, and those in no stream posted:
/// what it posted, the accounts its records named that the tree lacked,
/// and the intents in a stream, left to be posted in book order.
typedef _Slice = ({
  FreshPostingStore fresh,
  ReplayReport report,
  List<LedgerAccount> accounts,
  List<(LedgerIntent, Entry, Set<OldShape>)> streamed,
});

_Slice _postSlice(
  List<StoredRecord> rows,
  Set<String> aside,
  List<(String, String)> names,
  List<Account> accounts,
  List<Category> categories,
  List<Holding> start,
) {
  final refs = CategoryRefs()..fill(names);
  final mapping = BookMapping(
    accounts: accounts,
    categories: categories,
    start: start,
  );
  final tree = AccountTree(mapping.tree);
  final fresh = FreshPostingStore();
  final journal = Journal(
    registry: registryFor(() => mapping),
    accounts: tree,
    store: fresh,
    source: (_) => null,
  );
  final added = <LedgerAccount>[];
  final alone = <LedgerIntent>[];
  final records = <IntentId, (Entry, Set<OldShape>)>{};
  final streamed = <(LedgerIntent, Entry, Set<OldShape>)>[];
  for (final row in rows) {
    final json = _readable(row, aside);
    if (json == null) continue;
    final entry = entryFromJson(json, refs);
    final mapped = mapping.map(entry, row.seq);
    for (final account in mapped.accounts) {
      tree.put(account);
      added.add(account);
    }
    if (journal.streamsOf(mapped.intent).isEmpty) {
      alone.add(mapped.intent);
      records[mapped.intent.id] = (entry, mapped.shapes);
    } else {
      streamed.add((mapped.intent, entry, mapped.shapes));
    }
  }
  final report = ReplayReport();
  postIntents(journal, alone, report, records, mapping: mapping);
  return (fresh: fresh, report: report, accounts: added, streamed: streamed);
}
