import 'package:ledger_entries/model.dart' show EntryType, keptCategory;

/// The version of the record rows this app writes; each row carries it as
/// `_v`, with `_at`, when it was written. A row without `_v` is version 1.
/// A newer version's row is refused rather than misread: opening the book
/// sets it aside (quarantine.dart), and a backup holding one is not
/// restored.
///
/// Version 2 keeps a category by its id, so renaming one writes one row;
/// version 1 kept its name everywhere. The rows of a book kept before are
/// brought up when it is opened (book_migrations.dart).
///
/// Raised only when an earlier version would misread a row of the new
/// shape: a field renamed, or one whose meaning changed. A field added
/// that an earlier version can pass over does not raise it: an earlier
/// version keeps such a field as it is when it writes the record again
/// (record_fields.dart), so nothing is lost either way.
const recordVersion = 2;

/// A row written by a later version of the app than this one.
final class NewerRecord extends FormatException {
  const NewerRecord(String collection, this.version)
    : super('A newer app wrote this $collection ($version).');

  /// The record version it was written at.
  final int version;
}

/// The record version [json] was written at: its `_v`, or 1 when it has
/// none. Throws a [FormatException] when `_v` is not a version.
int rowVersion(Map<String, Object?> json) =>
    versionOf(json) ?? (throw const FormatException('_v: expected a version'));

/// The record version [json] was written at, as [rowVersion], or null
/// when its `_v` is not a version: a whole number of at least 1. A `_v`
/// that is not a number, not finite (`1e999` reads as infinity), not
/// whole (2.9) or below 1 (0, -5) is no version any app wrote, and the
/// row cannot be read; never thrown, so the book still opens without it.
int? versionOf(Map<String, Object?> json) => switch (json['_v']) {
  null => 1,
  final int v when v >= 1 => v,
  // A whole double too large for an int is clamped by toInt(): far
  // beyond any version, which is all that matters of it.
  final double v when v.isFinite && v == v.truncateToDouble() && v >= 1 =>
    v.toInt(),
  _ => null,
};

/// Brings a stored row up to [recordVersion], one version at a time; a
/// change of a record's shape adds a step here. Throws [NewerRecord] for
/// a row of a later version.
Map<String, Object?> upgradeRecord(
  String collection,
  Map<String, Object?> json,
) {
  final version = rowVersion(json);
  if (version > recordVersion) throw NewerRecord(collection, version);
  // A version 1 row reads as it is: its category is a name.
  return switch (collection) {
    'entry' => _withKeptCategory(json),
    'trash' => switch (json['entry']) {
      final Map<String, Object?> entry
          when !identical(_withKeptCategory(entry), entry) =>
        {...json, 'entry': _withKeptCategory(entry)},
      _ => json,
    },
    _ => json,
  };
}

/// [entry], an entry's row, under the category the book keeps it under
/// ([keptCategory], D80): a transfer kept with none reads under 轉帳, at
/// any version, as a form saving it would write it. [entry] itself when
/// it already is.
Map<String, Object?> _withKeptCategory(Map<String, Object?> entry) {
  if (entry['category'] != null || entry['categoryId'] != null) return entry;
  final type = EntryType.values.asNameMap()[entry['type']];
  if (type == null) return entry;
  final kept = keptCategory(type, '');
  return kept.isEmpty ? entry : {...entry, 'category': kept};
}
