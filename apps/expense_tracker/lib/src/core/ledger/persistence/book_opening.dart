import 'dart:convert';

import 'package:storage/storage.dart';

import '../models/models.dart';
import 'codec/category_refs.dart';
import 'codec/record_json.dart';
import 'codec/row_decoding.dart';
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
    required this.entrySeqs,
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

  /// Where each entry kept stands, by id.
  final Map<String, int> entrySeqs;

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
  final namesOf = <String, Set<String>>{};
  final collected = <String>{};
  String? collect(String name) {
    collected.add(name);
    return null;
  }

  List<T> read<T>(
    Collection collection,
    T Function(Map<String, Object?>) from,
  ) {
    final read = <T>[];
    for (final row in shelves[collection.name] ?? const <StoredRow>[]) {
      final record = json[row];
      if (record == null) continue;
      try {
        read.add(from(record));
      } on Object catch (error) {
        // Not logged per row: the row is set aside and told on opening.
        aside.record(row.shelf, row.id, QuarantineReason.invalid, error: error);
        continue;
      }
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
    for (final row in shelves[Collection.category.name] ?? const <StoredRow>[])
      if (json[row] case {'id': final String id, 'name': final String name})
        (id, name),
  ];
  final refs = CategoryRefs()..fill(categoryNames);
  final categories = read(
    Collection.category,
    (j) => categoryFromJson(j, refs),
  );
  final trash = read(Collection.trash, (j) => trashedFromJson(j, refs));
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
  final entries = read(Collection.entry, (j) => entryFromJson(j, refs));
  final market = shelves[marketShelf] ?? const <StoredRow>[];
  return DecodedBook._(
    accounts: read(Collection.account, accountFromJson),
    categories: categories,
    entries: entries,
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
    entrySeqs: {
      for (final row in shelves[Collection.entry.name] ?? const <StoredRow>[])
        row.id: row.seq,
    },
    expired: [
      for (final id in expiredIds) ...[
        RowChange.drop(Collection.trash.name, id),
        RowChange.drop(Collection.receipt.name, id),
      ],
      for (final id in forgotten) RowChange.drop(goneShelf, id),
    ],
    // Only an entry gone for good is a change of the book.
    expiredCounts: expiredIds.isNotEmpty,
    holdings: today == null
        ? null
        : readHoldings(
            holdingsOf(marketFrom(readableMarket(market))),
            entries,
            today,
          ),
  );
}

/// The record of each row of [shelves] but the receipts, decoded and
/// brought up to the current version; a row that is not a JSON object, or
/// that a later version wrote, is set [aside] instead.
Map<StoredRow, Map<String, Object?>> _records(
  Map<String, List<StoredRow>> shelves,
  Quarantine aside,
) {
  final records = [
    for (final collection in Collection.values)
      if (collection != Collection.receipt) ...?shelves[collection.name],
  ];
  final decoded = decodeBodies([for (final row in records) row.body]);
  final json = <StoredRow, Map<String, Object?>>{};
  for (final (i, row) in records.indexed) {
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
      continue;
    }
    switch (versionOf(record)) {
      case null:
        aside.record(
          row.shelf,
          row.id,
          QuarantineReason.invalid,
          detail: '_v is not a number',
        );
      case final version when version > recordVersion:
        aside.record(
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

/// The closes and board last fetched, from the [marketShelf] rows.
typedef Market = ({
  Map<String, double> prices,
  Map<String, double> moves,
  Map<String, String> names,
  Map<String, DateTime> days,
  DateTime? quotedOn,
  Map<String, double> rates,
});

/// The closes and board last fetched, from [rows] of [marketShelf].
Market marketFrom(List<StoredRow> rows) {
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
