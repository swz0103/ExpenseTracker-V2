import 'dart:convert';

import 'package:core/foundation_values.dart' show PublicId;
import 'package:storage/storage.dart';

import 'codec/category_refs.dart';
import 'codec/record_json.dart';
import 'ledger_data_source.dart';
import 'record_version.dart';

/// A book kept before categories had ids has each category under its name
/// in every record that names one. Gives each category an id and keeps
/// every such record under it, all in one write: whole, or not at all.
/// A book already so kept is left as it is.
void giveCategoriesIds(EncryptedDatabase store) {
  final rows = store.rows(shelf: Collection.category.name);
  final named = <String, String>{};
  var legacy = false;
  for (final row in rows) {
    final json = jsonDecode(row.body) as Map<String, Object?>;
    final name = json['name']! as String;
    final id = json['id'] as String?;
    if (id == null) legacy = true;
    named[name] = id ?? PublicId.generate().value;
  }
  if (!legacy) return;
  final refs = CategoryRefs()
    ..fill([for (final e in named.entries) (e.value, e.key)]);
  String text(Map<String, Object?> json, Object? at) =>
      jsonEncode({...json, '_v': recordVersion, '_at': at});
  Map<String, Object?> parse(StoredRow row) =>
      jsonDecode(row.body) as Map<String, Object?>;

  store.write((w) {
    // Each category under its id, in the order they were first kept.
    for (final row in rows) {
      final json = parse(row);
      final id = named[json['name']! as String]!;
      final category = categoryFromJson({...json, 'id': id});
      w.drop(Collection.category.name, row.id);
      w.put(
        Collection.category.name,
        id,
        text(categoryToJson(category, refs), json['_at']),
      );
    }
    for (final row in store.rows(shelf: Collection.entry.name)) {
      final json = parse(row);
      w.put(
        row.shelf,
        row.id,
        text(entryToJson(entryFromJson(json), refs), json['_at']),
      );
    }
    for (final row in store.rows(shelf: Collection.trash.name)) {
      final json = parse(row);
      w.put(
        row.shelf,
        row.id,
        text(trashedToJson(trashedFromJson(json), refs), json['_at']),
      );
    }
    for (final row in store.rows(shelf: Collection.recurring.name)) {
      final json = parse(row);
      w.put(
        row.shelf,
        row.id,
        text(recurringToJson(recurringFromJson(json), refs), json['_at']),
      );
    }
    // A budget is kept under what it covers: now its category's id.
    for (final row in store.rows(shelf: Collection.budget.name)) {
      final json = parse(row);
      final budget = budgetFromJson(json);
      w.drop(row.shelf, row.id);
      w.put(
        row.shelf,
        named[budget.category] ?? budget.category,
        text(budgetToJson(budget, refs), json['_at']),
      );
    }
  }, counts: false);
}
