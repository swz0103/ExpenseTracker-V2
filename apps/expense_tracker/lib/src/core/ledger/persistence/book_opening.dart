import 'package:ledger_entries/rules.dart' show namesOnLoops;
import 'package:core/time/calendar_day.dart' show BusinessDate;
import 'package:storage/storage.dart';

import '../models/models.dart';
import 'codec/category_refs.dart';
import 'market_rows.dart';
import 'codec/record_json.dart';
import 'codec/record_shape.dart';
import 'codec/row_decoding.dart';
import 'codec/same_values.dart';
import 'quarantine.dart';
import 'record_version.dart';
import '../repositories/holding_repository.dart'
    show ReadHoldings, readHoldings;
import 'write_batch.dart' show Collection;

/// The shelf noting when each record was deleted, by `collection/id`.
const goneShelf = 'gone';

/// The shelf of the forms put aside in the composer, by tab.
const draftShelf = 'draft';

/// The book's records as this version reads them, from the rows as kept
/// ([decodeBook]): what the ledger is made of, what was set aside and
/// why, and what opening it drops from the file.
///
/// Plain values only, so it is made on a worker isolate and sent to the
/// screen's (decision D51: the book is decoded once, there, for the
/// screens and the journal both).
final class DecodedBook {
  DecodedBook._({
    required this.accounts,
    required this.categories,
    required this.entries,
    required this.budgets,
    required this.recurring,
    required this.trash,
    required this.market,
    required this.receipts,
    required this.drafts,
    required this.aside,
    required this.namesOf,
    required this.categoryNames,
    required this.entryPlaces,
    required this.expired,
    required this.expiredCounts,
    required this.holdings,
    required this.marketFolds,
  });

  final List<Account> accounts;
  final List<Category> categories;
  final List<Entry> entries;
  final List<Budget> budgets;
  final List<Recurring> recurring;

  /// The entries in the trash still kept, the latest put there first.
  final List<Trashed> trash;

  /// The rows of [marketShelf], as kept, with the months long gone
  /// folded into a row each ([marketFolds]).
  final List<StoredRow> market;

  /// What folds the months long gone of the market into a row each
  /// (`foldedMarket`, review 39), worked out with the book on its worker
  /// as it opens (PERF-4): the changes to write, and the day rows they
  /// were worked out from, to check against the rows kept when they are
  /// written (`foldStillApplies`). None without a day, or with nothing
  /// to fold.
  final ({List<RowChange> changes, Map<String, String> from}) marketFolds;

  /// Each receipt's and draft's body, by id.
  final Map<String, String> receipts;
  final Map<String, String> drafts;

  /// The rows set aside, each with why.
  final List<QuarantinedRow> aside;

  /// What each record (`shelf/id`) names by name ([namesToIds]).
  final Map<String, Set<String>> namesOf;

  /// Each category's id and name, as kept: what they stand for first.
  final List<(String, String)> categoryNames;

  /// Where each of [entries] stands in the order written, beside it (its
  /// row's place): for the screens' book, which takes the entries in that
  /// order without a lookup by id, and for the journal, which posts each
  /// entry at its place (`postBook`). Never a map by id: one was built
  /// on every opening, sent to the screen's isolate and kept there, for
  /// a posting that reads the places from the rows anyway.
  final List<int> entryPlaces;

  /// What opening drops from the file: the entries in the trash longer
  /// than it keeps them, their receipts, and the notes of deletions as
  /// old; one write, a change of the book ([expiredCounts]) only when an
  /// entry goes for good.
  final List<RowChange> expired;
  final bool expiredCounts;

  /// The holdings replayed as of the day it was read for, worked out
  /// with the book (on its worker as it opens, D51): what the ledger
  /// adopts in place of replaying them itself. None without a day.
  final ReadHoldings? holdings;
}

/// [rows] by shelf, in the order given.
Map<String, List<StoredRow>> shelvesOf(Iterable<StoredRow> rows) {
  final shelves = <String, List<StoredRow>>{};
  for (final row in rows) {
    (shelves[row.shelf] ??= []).add(row);
  }
  return shelves;
}

/// Reads the book from its rows by shelf, as this version reads it: each
/// record decoded, brought up to this version and read; a row that is not
/// a JSON object, that a later version wrote, or that cannot be read is
/// set aside instead ([DecodedBook.aside]), and the rest of the book
/// opens. [trashFrom] is the oldest day the trash keeps an entry put
/// there; none drops nothing. [entryTail], the last of the entry rows
/// already decoded elsewhere ([decodeRows], on a second worker as a large
/// book opens), is taken as it is.
DecodedBook decodeBook(
  Map<String, List<StoredRow>> shelves, {
  DateTime? trashFrom,
  DateTime? today,
  DecodedRecords? entryTail,
  Iterable<StoredRow>? entryRows,
}) {
  assert(entryTail == null || entryRows == null, 'one or the other');
  final aside = Quarantine();
  final unreadable = {for (final c in Collection.values) c: Quarantine()};
  final json = _records(shelves, unreadable, entryTail);
  // One copy of what entries repeat, for the whole book.
  final same = SameValues();
  final namesOf = <String, Set<String>>{};
  final collected = <String>{};
  String? collect(String name) {
    collected.add(name);
    return null;
  }

  List<T> read<T>(
    Collection collection,
    T Function(Map<String, Object?>) from, {
    List<int>? seqs,
  }) {
    final read = <T>[];
    final rows = collection == Collection.entry && entryRows != null
        ? entryRows
        : shelves[collection.name] ?? const <StoredRow>[];
    final recordAt = json[collection]!;
    for (final (i, row) in rows.indexed) {
      final record = recordAt(i, row);
      if (record == null) continue;
      final T value;
      try {
        value = from(record);
      } on Object catch (error) {
        // Not logged per row: the row is set aside and told on opening.
        aside.record(row.shelf, row.id, QuarantineReason.invalid, error: error);
        continue;
      }
      // The shape rules a backup is restored by ([checkRecord]): a record
      // no version of the app would write is set aside, never worked with.
      if (shapeProblem(shapeIssues(value!)) case final problem?) {
        aside.record(
          row.shelf,
          row.id,
          QuarantineReason.invalid,
          detail: problem,
        );
        continue;
      }
      read.add(value);
      seqs?.add(row.seq);
      namesToIds(row.shelf, record, collect);
      if (collected.isNotEmpty) {
        namesOf['${row.shelf}/${row.id}'] = {...collected};
        collected.clear();
      }
    }
    return read;
  }

  // What each category id stands for first: a category's parent and every
  // other record name theirs through it.
  final categoryNames = [
    for (final (i, row)
        in (shelves[Collection.category.name] ?? const []).indexed)
      if (json[Collection.category]!(i, row) case {
        'id': final String id,
        'name': final String name,
      })
        (id, name),
  ];
  final refs = CategoryRefs()..fill(categoryNames);
  var categories = read(Collection.category, (j) => categoryFromJson(j, refs));
  // Categories each other's parents (D103): no form writes them, and no
  // total could say what they sit under; set aside like any record of a
  // shape the app never writes.
  final looped = categoriesOnLoops(categories);
  if (looped.isNotEmpty) {
    for (final c in looped) {
      aside.record(
        Collection.category.name,
        c.id,
        QuarantineReason.invalid,
        detail: parentLoopProblem,
      );
      namesOf.remove('${Collection.category.name}/${c.id}');
    }
    categories = [
      for (final c in categories)
        if (!looped.contains(c)) c,
    ];
  }
  // Each with its row's place: an entry moved to the trash keeps it (D75).
  final trashPlaces = {
    for (final row in shelves[Collection.trash.name] ?? const <StoredRow>[])
      row.id: row.seq,
  };
  final trash = [
    for (final t in read(
      Collection.trash,
      (j) => trashedFromJson(j, refs, same),
    ))
      Trashed(t.entry, t.on, order: trashPlaces[t.entry.id], letGo: t.letGo),
  ];
  final expiredIds = [
    if (trashFrom != null)
      for (final t in trash)
        if (t.on.isBefore(trashFrom)) t.entry.id,
  ];
  final gone = shelves[goneShelf] ?? const <StoredRow>[];
  final cutoff = trashFrom?.millisecondsSinceEpoch;
  final notes = cutoff == null
      ? const <Object?>[]
      : decodeBodies([for (final row in gone) row.body]).values;
  final forgotten = [
    if (cutoff != null)
      for (final (i, row) in gone.indexed)
        // A note that cannot be read is left as it is.
        if (notes[i] case {'at': final num at} when at < cutoff) row.id,
  ];
  // Each entry's place in the order written, beside it: its row's.
  var entryPlaces = <int>[];
  var entries = read(
    Collection.entry,
    (j) => entryFromJson(j, refs, same),
    seqs: entryPlaces,
  );
  final kept = shelves[marketShelf] ?? const <StoredRow>[];
  // A row that cannot be read is told when the market is read
  // (`readMarket`), on the screen's isolate.
  final folded = today == null
      ? (
          rows: kept,
          changes: const <RowChange>[],
          from: const <String, String>{},
        )
      : foldedMarket(kept, BusinessDate.of(today));
  final market = folded.rows;
  final holdings = today == null
      ? null
      : readHoldings(
          holdingsOf(readMarket(market, history: false)),
          entries,
          today,
        );
  if (holdings != null && holdings.faulty.isNotEmpty) {
    // A trade the holdings could not work in, whatever it threw, is set
    // aside like any record that cannot be read; the holdings already
    // leave it out.
    holdings.faulty.forEach((id, error) {
      aside.record(
        Collection.entry.name,
        id,
        QuarantineReason.invalid,
        error: error,
      );
      namesOf.remove('${Collection.entry.name}/$id');
    });
    final kept = [
      for (final (i, e) in entries.indexed)
        if (!holdings.faulty.containsKey(e.id)) i,
    ];
    entries = [for (final i in kept) entries[i]];
    entryPlaces = [for (final i in kept) entryPlaces[i]];
  }
  return DecodedBook._(
    accounts: read(Collection.account, accountFromJson),
    categories: categories,
    entries: entries,
    entryPlaces: entryPlaces,
    budgets: read(Collection.budget, (j) => budgetFromJson(j, refs)),
    recurring: read(Collection.recurring, (j) => recurringFromJson(j, refs)),
    trash: [
      for (final t in trash.reversed)
        if (trashFrom == null || !t.on.isBefore(trashFrom)) t,
    ],
    market: market,
    receipts: {
      for (final row in shelves[Collection.receipt.name] ?? const <StoredRow>[])
        row.id: row.body,
    },
    drafts: {
      for (final row in shelves[draftShelf] ?? const <StoredRow>[])
        row.id: row.body,
    },
    // Those that cannot be read at all first, shelf by shelf, then those
    // read but refused, in the order they were met.
    aside: [
      for (final c in Collection.values) ...[
        ...unreadable[c]!.rows,
        // The tail's after the head's, as when all are decoded here.
        if (c == Collection.entry) ...?entryTail?.aside,
      ],
      ...aside.rows,
    ],
    namesOf: namesOf,
    categoryNames: categoryNames,
    expired: [
      for (final id in expiredIds) ...[
        RowChange.drop(Collection.trash.name, id),
        RowChange.drop(Collection.receipt.name, id),
      ],
      for (final id in forgotten) RowChange.drop(goneShelf, id),
    ],
    // Only an entry gone for good is a change of the book.
    expiredCounts: expiredIds.isNotEmpty,
    holdings: holdings,
    marketFolds: (changes: folded.changes, from: folded.from),
  );
}

/// The record of each row of [shelves] but the receipts, by shelf, by
/// the place of its row: decoded and brought up to the current version;
/// null for a row that is not a JSON object, or that a later version
/// wrote, which is set aside instead, in [unreadable] under its shelf.
/// Every collection has its reader, of no rows when it has none. The last
/// entry rows, as many as [entryTail] holds, are taken from it (their
/// rows set aside are [entryTail]'s own, told after the others').
///
/// The entries' records are decoded one at a time, as each is asked
/// for, and are let go once read (PERF-3): decoded all at once, the
/// JSON of 100,000 entries stayed alive until the last was read, and the
/// worker's collections copying it (one isolate group) held the screen.
/// Each entry row is to be asked for once, in order.
Map<Collection, _RecordAt> _records(
  Map<String, List<StoredRow>> shelves,
  Map<Collection, Quarantine> unreadable,
  DecodedRecords? entryTail,
) {
  final records = <Collection, _RecordAt>{};
  for (final collection in Collection.values) {
    if (collection == Collection.receipt) continue;
    final rows = shelves[collection.name] ?? const <StoredRow>[];
    final aside = unreadable[collection]!;
    if (collection == Collection.entry) {
      final tail = entryTail?.records;
      final head = rows.length - (tail?.length ?? 0);
      records[collection] = (i, row) =>
          tail == null || i < head ? _recordOf(row, aside) : tail[i - head];
    } else {
      final decoded = _shelfRecords(rows, aside);
      records[collection] = (i, _) => decoded[i];
    }
  }
  return records;
}

/// The record of the row at a place of one shelf ([_records]).
typedef _RecordAt = Map<String, Object?>? Function(int i, StoredRow row);

/// The record of [row] alone, as [_shelfRecords] decodes each.
Map<String, Object?>? _recordOf(StoredRow row, Quarantine aside) =>
    _record(row, decodeBodies([row.body]), 0, aside);

/// [rows], all of one shelf, decoded and brought up to this version as
/// the book opens them ([decodeBook]), with the rows set aside: done on a
/// worker of its own for the last half of a large book's entries.
DecodedRecords decodeRows(List<StoredRow> rows) {
  final aside = Quarantine();
  return (records: _shelfRecords(rows, aside), aside: aside.rows);
}

/// What [decodeRows] made: each row's record, null for one set aside,
/// and those set aside, in order.
typedef DecodedRecords = ({
  List<Map<String, Object?>?> records,
  List<QuarantinedRow> aside,
});

List<Map<String, Object?>?> _shelfRecords(
  List<StoredRow> rows,
  Quarantine aside,
) {
  final decoded = decodeBodies([for (final row in rows) row.body]);
  return [for (final (i, row) in rows.indexed) _record(row, decoded, i, aside)];
}

Map<String, Object?>? _record(
  StoredRow row,
  DecodedRows decoded,
  int i,
  Quarantine aside,
) {
  final record = decoded.values[i];
  if (record is! Map<String, Object?>) {
    aside.record(
      row.shelf,
      row.id,
      QuarantineReason.unreadable,
      detail: decoded.failures.containsKey(i)
          ? 'not JSON'
          : 'not a JSON object',
    );
    return null;
  }
  switch (versionOf(record)) {
    case null:
      aside.record(
        row.shelf,
        row.id,
        QuarantineReason.invalid,
        detail: '_v is not a version',
      );
      return null;
    case final version when version > recordVersion:
      aside.record(row.shelf, row.id, QuarantineReason.newer, version: version);
      return null;
    case _:
      return upgradeRecord(row.shelf, record);
  }
}

/// How a category on a loop of parents is told, set aside as the book
/// opens and refused in a backup (D103).
const parentLoopProblem = 'parent loop';

/// The categories of [categories] on a loop of parents (`namesOnLoops`).
List<Category> categoriesOnLoops(List<Category> categories) {
  final looped = namesOnLoops({for (final c in categories) c.name: c.parent});
  return [
    for (final c in categories)
      if (looped.contains(c.name)) c,
  ];
}
