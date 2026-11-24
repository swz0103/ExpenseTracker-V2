import 'dart:convert';
import 'dart:math' show max;

import 'package:core/foundation_values.dart' show PublicId;
import 'package:ledger_entries/model.dart' show Entry, EntryMark, EntryType;
import 'package:ledger_entries/rules.dart' show refundShare;
import 'package:storage/storage.dart';

import 'codec/category_refs.dart';
import 'codec/row_decoding.dart';
import 'ledger_data_source.dart' show Collection;
import 'record_version.dart';

// The book's own version, and the steps that bring a book kept by an
// earlier version of the app up to it. The store's layout (its tables)
// has its own ladder in the storage package; a record's shape has its
// version in each row (record_version.dart). This is what lies between:
// changes across the records of a book, such as which category a record
// names and how.

/// The store keeps the book's version under
/// [EncryptedDatabase.bookVersionKey]: how many of [bookSteps] it has
/// been through. A book kept before versions were has none: 0. A backup
/// carries it, so a book restored is not brought up again.

/// One step up: reads the rows of [store] and writes what changes through
/// [writer], inside the transaction every step of an opening shares. A
/// row that cannot be read, or that a later version wrote, is left
/// exactly as it is.
typedef BookStep = void Function(EncryptedDatabase store, RowWriter writer);

/// `bookSteps[n]` brings a book at version n to n + 1. A change across
/// the records of a book adds a step at the end; a step is never changed
/// once released, since books already through it will not run it again.
const List<BookStep> bookSteps = [
  _categoryIds,
  _namesToIds,
  _refundsMirrorPurchases,
  _marksFromTags,
];

/// The version this app brings every book it opens up to.
final bookVersion = bookSteps.length;

/// Where a book opened stands against this app's [bookVersion].
enum BookStanding {
  /// Nothing kept yet: a ledger just made, to be given its first records.
  fresh,

  /// Kept at an earlier version: the steps it lacks are due.
  behind,

  /// At this version.
  current,

  /// Brought up by a later version of the app. It opens as it is: each
  /// row a later version wrote is set aside, the rest read.
  ahead,
}

BookStanding standingOf(EncryptedDatabase store) {
  final version = store.meta(EncryptedDatabase.bookVersionKey);
  if (version == null && store.count == 0) return BookStanding.fresh;
  final at = version ?? 0;
  if (at < bookVersion) return BookStanding.behind;
  return at == bookVersion ? BookStanding.current : BookStanding.ahead;
}

/// Runs the steps of [steps] the book in [store] has not been through,
/// then notes its version, all in one transaction: a step that throws
/// leaves the book as it was. Not a change of the book: no backup is due
/// for it. Nothing is done for a book at or past the version of [steps].
void bringUpBook(EncryptedDatabase store, {List<BookStep>? steps}) {
  final ladder = steps ?? bookSteps;
  final at = store.meta(EncryptedDatabase.bookVersionKey) ?? 0;
  if (at >= ladder.length) return;
  store.write((w) {
    for (final step in ladder.skip(at)) {
      step(store, w);
    }
    w.setMeta(EncryptedDatabase.bookVersionKey, ladder.length);
  }, counts: false);
}

/// Notes, through [writer], that the book just given its first records
/// is at this app's version.
void markCurrent(RowWriter writer) =>
    writer.setMeta(EncryptedDatabase.bookVersionKey, bookVersion);

/// Version 0 to 1: each category kept by its name, as books were before
/// categories had ids, is given an id and kept under it. Two kept under
/// the same name become one, the later kept.
void _categoryIds(EncryptedDatabase store, RowWriter w) {
  final named = <String, String>{};
  final shelf = Collection.category.name;
  final rows = store.rows(shelf: shelf);
  for (final row in rows) {
    final json = readableRecord(row.body);
    if (json case {'id': final String id, 'name': final String name}) {
      named[name] = id;
    }
  }
  for (final row in rows) {
    final json = readableRecord(row.body);
    if (json == null || json['id'] != null) continue;
    final name = json['name'];
    if (name is! String) continue;
    final id = named[name] ??= PublicId.generate().value;
    w
      ..drop(shelf, row.id)
      ..put(shelf, id, jsonEncode({...json, 'id': id}));
  }
}

/// Version 1 to 2: each record that names a category by name, where a
/// category of that name is kept, names it by its id. A name no category
/// has stays a name. A budget is kept under what it covers, so one of a
/// category moves under its id. A record of version 1 is of version 2
/// once through this step (record_version.dart).
void _namesToIds(EncryptedDatabase store, RowWriter w) {
  final ids = <String, String>{};
  for (final row in store.rows(shelf: Collection.category.name)) {
    if (readableRecord(row.body) case {
      'id': final String id,
      'name': final String name,
    }) {
      ids[name] = id;
    }
  }
  for (final shelf in namingCollections) {
    for (final row in store.rows(shelf: shelf)) {
      final json = readableRecord(row.body);
      if (json == null) continue;
      final version = rowVersion(json);
      final byId = namesToIds(shelf, json, (name) => ids[name]);
      if (byId == null && version >= 2) continue;
      final next = {...byId ?? json, '_v': max(version, 2)};
      var key = row.id;
      if (shelf == Collection.budget.name) {
        final moved = budgetKeyAfter(store, row, next);
        if (moved != row.id) {
          w.drop(shelf, row.id);
          key = moved;
        }
      }
      w.put(shelf, key, jsonEncode(next));
    }
  }
}

/// Version 2 to 3: a refund of a split purchase kept without a split is
/// given its share of each part, and a refund kept without tags the
/// purchase's tags, as every refund is written since D65 (the ledger's
/// one rule, `refundShare`): a purchase refunded in full then leaves no
/// category and no tag total behind. The refunds of a purchase are
/// shared in the order the book keeps them; a tag the refund was given
/// itself is left as it is. A refund whose purchase is not kept, or
/// cannot be read, stays as it was.
void _refundsMirrorPurchases(EncryptedDatabase store, RowWriter w) {
  final shelf = Collection.entry.name;
  final rows = store.rows(shelf: shelf);
  final byId = <String, Map<String, Object?>>{};
  for (final row in rows) {
    final json = readableRecord(row.body);
    if (json case {'id': final String id}) byId[id] = json;
  }
  // What each purchase's refunds gave back so far, as the rule reads them.
  final earlier = <String, List<Entry>>{};
  for (final row in rows) {
    final json = readableRecord(row.body);
    if (json == null || json['type'] != EntryType.income.name) continue;
    final of = json['refundOf'];
    if (of is! String) continue;
    final original = byId[of];
    final amount = json['amount'];
    if (original == null || amount is! int) continue;
    if (original['type'] != EntryType.expense.name) continue;
    final purchase = _keyed(original);
    if (purchase == null) continue;
    final kept = earlier.putIfAbsent(of, () => []);
    final share = refundShare(purchase, amount, earlier: kept);
    final ownParts = json['parts'];
    final ownTags = json['tags'];
    final next = {...json};
    var changed = false;
    if ((ownParts is! List || ownParts.isEmpty) && share.parts.isNotEmpty) {
      for (final key in _categoryKeys) {
        next.remove(key);
      }
      next.addAll(_unkey(share.category, entry: true));
      next['parts'] = [
        for (final (key, value) in share.parts)
          {..._unkey(key, entry: false), 'amount': value},
      ];
      changed = true;
    }
    if ((ownTags is! List || ownTags.isEmpty) && share.tags.isNotEmpty) {
      next['tags'] = share.tags;
      changed = true;
    }
    // The refund as it now stands, for the next refund of the purchase.
    if (_keyed(next) case final mine?) kept.add(mine);
    if (changed) w.put(shelf, row.id, jsonEncode(next));
  }
}

/// Version 3 to 4: an entry the app identified by a tag's words is given
/// its mark (D52), so a tag renamed changes no figure: cashback (income
/// tagged 回饋), an annual fee (spending tagged 年費), an e-invoice
/// (spending tagged 發票); in the trash too. The tags stay as they are.
void _marksFromTags(EncryptedDatabase store, RowWriter w) {
  Map<String, Object?>? marked(Map<String, Object?> json) {
    if (json['mark'] != null) return null;
    final tags = json['tags'];
    if (tags is! List) return null;
    final mark = switch (json['type']) {
      'income' when tags.contains(_rewardTag) => EntryMark.reward,
      'expense' when tags.contains(_annualFeeTag) => EntryMark.annualFee,
      'expense' when tags.contains(_invoiceTag) => EntryMark.invoice,
      _ => null,
    };
    return mark == null ? null : {...json, 'mark': mark.name};
  }

  final entries = Collection.entry.name;
  for (final row in store.rows(shelf: entries)) {
    final json = readableRecord(row.body);
    if (json == null) continue;
    if (marked(json) case final next?) {
      w.put(entries, row.id, jsonEncode(next));
    }
  }
  final trash = Collection.trash.name;
  for (final row in store.rows(shelf: trash)) {
    final json = readableRecord(row.body);
    final entry = json?['entry'];
    if (json == null || entry is! Map<String, Object?>) continue;
    if (marked(entry) case final next?) {
      w.put(trash, row.id, jsonEncode({...json, 'entry': next}));
    }
  }
}

// Exception to shared words: the tags earlier versions identified these
// entries by, read once to give them their mark.
const _rewardTag = '回饋';
const _annualFeeTag = '年費';
const _invoiceTag = '發票';

/// The keys an entry names its category under: by id, or by name.
const _categoryKeys = ['categoryId', 'category'];

/// [json], an entry row, as an [Entry] of its amount, split and tags
/// whose categories are opaque keys (`id:` and an id, `name:` and a
/// name), for [refundShare]. Null when not readable.
Entry? _keyed(Map<String, Object?> json) {
  final amount = json['amount'];
  if (amount is! int) return null;
  String? key(Map<String, Object?> m, String nameKey) => switch (m) {
    {'categoryId': final String id} => 'id:$id',
    _ when m[nameKey] is String => 'name:${m[nameKey]}',
    _ => null,
  };
  final parts = <(String, int)>[];
  final kept = json['parts'];
  for (final p in kept is List ? kept : const []) {
    if (p is! Map<String, Object?>) return null;
    final k = key(p, 'name');
    final value = p['amount'];
    if (k == null || value is! int) return null;
    parts.add((k, value));
  }
  final home = json['home'];
  return Entry(
    id: switch (json['id']) {
      final String id => id,
      _ => '',
    },
    date: DateTime.utc(2000),
    type: json['type'] == EntryType.expense.name
        ? EntryType.expense
        : EntryType.income,
    amount: amount,
    account: '',
    category: key(json, 'category') ?? '',
    parts: parts,
    tags: [
      for (final t in switch (json['tags']) {
        final List<Object?> tags => tags,
        _ => const <Object?>[],
      })
        if (t is String) t,
    ],
    home: home is int ? home : null,
  );
}

/// The JSON naming the category of an opaque [key] of [_keyed]: an
/// entry's (`category`) or a part's (`name`), by id or by name.
Map<String, Object?> _unkey(String key, {required bool entry}) =>
    key.startsWith('id:')
    ? {'categoryId': key.substring(3)}
    : {(entry ? 'category' : 'name'): key.substring(5)};

/// The key the budget [row] is kept under once it holds [json]: its
/// category's id when it names one by id and no other budget is kept
/// under that id; else where it is.
String budgetKeyAfter(
  EncryptedDatabase store,
  StoredRow row,
  Map<String, Object?> json,
) {
  final id = json['categoryId'];
  if (id is! String || id == row.id) return row.id;
  return store.row(row.shelf, id) == null ? id : row.id;
}
