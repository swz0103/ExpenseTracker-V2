import 'dart:convert';
import 'dart:math' show max;

import 'package:core/foundation_values.dart' show PublicId;
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

/// Where the store keeps the book's version: how many of [bookSteps] it
/// has been through. A book kept before versions were has none: 0.
const bookVersionKey = 'book';

/// One step up: reads the rows of [store] and writes what changes through
/// [writer], inside the transaction every step of an opening shares. A
/// row that cannot be read, or that a later version wrote, is left
/// exactly as it is.
typedef BookStep = void Function(EncryptedDatabase store, RowWriter writer);

/// `bookSteps[n]` brings a book at version n to n + 1. A change across
/// the records of a book adds a step at the end; a step is never changed
/// once released, since books already through it will not run it again.
const List<BookStep> bookSteps = [_categoryIds, _namesToIds];

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
  final version = store.meta(bookVersionKey);
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
  final at = store.meta(bookVersionKey) ?? 0;
  if (at >= ladder.length) return;
  store.write((w) {
    for (final step in ladder.skip(at)) {
      step(store, w);
    }
    w.setMeta(bookVersionKey, ladder.length);
  }, counts: false);
}

/// Notes, through [writer], that the book just given its first records
/// is at this app's version.
void markCurrent(RowWriter writer) =>
    writer.setMeta(bookVersionKey, bookVersion);

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
