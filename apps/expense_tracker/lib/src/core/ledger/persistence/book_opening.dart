import 'dart:convert';

import 'package:storage/storage.dart';

import '../models/models.dart';
import 'codec/category_refs.dart';
import 'codec/record_json.dart';
import 'codec/record_shape.dart';
import 'codec/row_decoding.dart';
import 'codec/same_values.dart';
import 'quarantine.dart';
import 'record_version.dart';
import '../repositories/holding_repository.dart'
    show ReadHoldings, readHoldings;
import 'write_batch.dart' show Collection;

/// The shelf of the closes and board last fetched.
const marketShelf = 'market';

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
  });

  final List<Account> accounts;
  final List<Category> categories;
  final List<Entry> entries;
  final List<Budget> budgets;
  final List<Recurring> recurring;

  /// The entries in the trash still kept, the latest put there first.
  final List<Trashed> trash;

  /// The rows of [marketShelf], as kept.
  final List<StoredRow> market;

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
/// there; none drops nothing.
DecodedBook decodeBook(
  Map<String, List<StoredRow>> shelves, {
  DateTime? trashFrom,
  DateTime? today,
}) {
  final aside = Quarantine();
  final json = _records(shelves, aside);
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
    final rows = shelves[collection.name] ?? const <StoredRow>[];
    final records = json[collection.name]!;
    for (final (i, row) in rows.indexed) {
      final record = records[i];
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
    for (final record in json[Collection.category.name]!)
      if (record case {'id': final String id, 'name': final String name})
        (id, name),
  ];
  final refs = CategoryRefs()..fill(categoryNames);
  final categories = read(
    Collection.category,
    (j) => categoryFromJson(j, refs),
  );
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
      Trashed(t.entry, t.on, order: trashPlaces[t.entry.id]),
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
  final market = shelves[marketShelf] ?? const <StoredRow>[];
  final holdings = today == null
      ? null
      : readHoldings(
          holdingsOf(marketFrom(readableMarket(market))),
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
    aside: aside.rows,
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
  );
}

/// The record of each row of [shelves] but the receipts, by shelf, in
/// the order of its rows, decoded and brought up to the current version;
/// null for a row that is not a JSON object, or that a later version
/// wrote, which is set [aside] instead. Every collection has its list,
/// empty when it has no rows.
Map<String, List<Map<String, Object?>?>> _records(
  Map<String, List<StoredRow>> shelves,
  Quarantine aside,
) => {
  for (final collection in Collection.values)
    if (collection != Collection.receipt)
      collection.name: _shelfRecords(
        shelves[collection.name] ?? const <StoredRow>[],
        aside,
      ),
};

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

/// The closes and board last fetched, from the [marketShelf] rows.
typedef Market = ({
  Map<String, double> prices,
  Map<String, double> moves,
  Map<String, String> names,
  Map<String, DateTime> days,
  DateTime? quotedOn,
  Map<String, double> rates,
  Map<String, double> sellRates,
});

/// The closes and board last fetched, from [rows] of [marketShelf].
Market marketFrom(List<StoredRow> rows) {
  final prices = <String, double>{};
  final moves = <String, double>{};
  final names = <String, String>{};
  final days = <String, DateTime>{};
  final rates = <String, double>{};
  final sellRates = <String, double>{};
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
        // The selling rates, kept since D59; a board kept before has none.
        for (final MapEntry(:key, :value) in part(json, 'sell').entries) {
          if (value is! num) throw const FormatException('sell');
          sellRates[key] = value.toDouble();
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
    sellRates: sellRates,
  );
}

/// The rows of [rows] of [marketShelf] that can be read; [report] is
/// told what reading each other threw (a close or rate kept that cannot
/// be read is fetched again).
List<StoredRow> readableMarket(
  List<StoredRow>? rows, {
  void Function(Object error) report = _unreported,
}) => [
  for (final row in rows ?? const <StoredRow>[])
    if (_marketReadable(row, report)) row,
];

void _unreported(Object error) {}

bool _marketReadable(StoredRow row, void Function(Object error) report) {
  try {
    marketFrom([row]);
    return true;
  } on Object catch (error) {
    // Told to [report]: a close or rate that cannot be read is fetched
    // again.
    report(error);
    return false;
  }
}

/// A reference price and name for each stock with a kept close: the
/// holdings a book starts from.
List<Holding> holdingsOf(Market market) => [
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
