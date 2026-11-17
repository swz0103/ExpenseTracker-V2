/// The version of the record rows this app writes; each row carries it as
/// `_v`, with `_at`, when it was written. A row without `_v` is version 1.
/// A newer version's row is refused rather than misread.
///
/// Version 2 keeps a category by its id, so renaming one writes one row;
/// version 1 kept its name everywhere. The rows of a book kept before are
/// brought up when it is opened (`giveCategoriesIds` in category_id_migration.dart).
const recordVersion = 2;

/// Brings a stored row up to [recordVersion], one version at a time; a
/// change of a record's shape adds a step here.
Map<String, Object?> upgradeRecord(
  String collection,
  Map<String, Object?> json,
) {
  final version = (json['_v'] as num?)?.toInt() ?? 1;
  if (version > recordVersion) {
    throw FormatException('A newer app wrote this $collection ($version).');
  }
  // A version 1 row reads as it is: its category is a name.
  return json;
}
