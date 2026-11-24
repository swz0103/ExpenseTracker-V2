import 'dart:convert';

import 'package:domain/investments.dart' show DoubtedFigure;
import 'package:ledger_entries/rules.dart' show namesOnLoops;
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

import 'package:core/time/utc_days.dart';

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
/// there; none drops nothing. [entryTail], the last of the entry rows
/// already decoded elsewhere ([decodeRows], on a second worker as a large
/// book opens), is taken as it is.
DecodedBook decodeBook(
  Map<String, List<StoredRow>> shelves, {
  DateTime? trashFrom,
  DateTime? today,
  DecodedRecords? entryTail,
}) {
  final aside = Quarantine();
  final json = _records(shelves, aside, entryTail);
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
/// empty when it has no rows. The last entry rows, as many as
/// [entryTail] holds, are taken from it, their rows set aside after
/// those of the entries before them, as when all are decoded here.
Map<String, List<Map<String, Object?>?>> _records(
  Map<String, List<StoredRow>> shelves,
  Quarantine aside,
  DecodedRecords? entryTail,
) {
  final records = <String, List<Map<String, Object?>?>>{};
  for (final collection in Collection.values) {
    if (collection == Collection.receipt) continue;
    final rows = shelves[collection.name] ?? const <StoredRow>[];
    if (collection == Collection.entry && entryTail != null) {
      final head = rows.length - entryTail.records.length;
      records[collection.name] = [
        ..._shelfRecords(rows.sublist(0, head), aside),
        ...entryTail.records,
      ];
      entryTail.aside.forEach(aside.adopt);
    } else {
      records[collection.name] = _shelfRecords(rows, aside);
    }
  }
  return records;
}

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

/// The closes and board last fetched, from the [marketShelf] rows.
typedef Market = ({
  Map<String, double> prices,
  Map<String, double> moves,
  Map<String, String> names,
  Map<String, DateTime> days,
  DateTime? quotedOn,
  Map<String, double> rates,
  Map<String, double> sellRates,
  Map<String, DoubtedFigure> doubtedCloses,
  Map<String, DoubtedFigure> doubtedRates,
  Map<String, DoubtedFigure> doubtedSellRates,
  DateTime? ratesOn,
});

/// The closes and board last fetched, from [rows] of [marketShelf].
Market marketFrom(List<StoredRow> rows) {
  final prices = <String, double>{};
  final moves = <String, double>{};
  final names = <String, String>{};
  final days = <String, DateTime>{};
  final rates = <String, double>{};
  final sellRates = <String, double>{};
  final doubtedCloses = <String, DoubtedFigure>{};
  final doubtedRates = <String, DoubtedFigure>{};
  final doubtedSellRates = <String, DoubtedFigure>{};
  DateTime? quotedOn;
  DateTime? ratesOn;
  Map<String, Object?> part(Map<String, Object?> json, String key) =>
      json[key] as Map<String, Object?>? ?? const {};
  // What the last fetch doubted (D101), kept beside the figures, each
  // with its day under [field]`On`; a row kept before has none. A doubt
  // kept with no day (before review 25) is read as too old to weigh.
  void doubted(
    Map<String, Object?> json,
    String field,
    Map<String, DoubtedFigure> to,
  ) {
    final days = part(json, '${field}On');
    for (final MapEntry(:key, :value) in part(json, field).entries) {
      if (value is! num) throw FormatException(field);
      if (days[key] case final String on) {
        if (DateTime.tryParse(on) case final d?) {
          to[key] = (
            figure: value.toDouble(),
            day: DateTime.utc(d.year, d.month, d.day),
          );
        }
      }
    }
  }

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
        doubted(json, 'doubted', doubtedCloses);
      case 'rates':
        for (final MapEntry(:key, :value) in part(json, 'rates').entries) {
          rates[key] = (value! as num).toDouble();
        }
        // The selling rates, kept since D59; a board kept before has none.
        for (final MapEntry(:key, :value) in part(json, 'sell').entries) {
          if (value is! num) throw const FormatException('sell');
          sellRates[key] = value.toDouble();
        }
        doubted(json, 'doubted', doubtedRates);
        doubted(json, 'doubtedSell', doubtedSellRates);
        // The board's day: what a rate doubted is weighed by (D101); a
        // day that cannot be read only leaves it unknown.
        if (json['asOf'] case final String on) {
          if (DateTime.tryParse(on) case final d?) {
            ratesOn = dayOf(d);
          }
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
    doubtedCloses: doubtedCloses,
    doubtedRates: doubtedRates,
    doubtedSellRates: doubtedSellRates,
    ratesOn: ratesOn,
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
