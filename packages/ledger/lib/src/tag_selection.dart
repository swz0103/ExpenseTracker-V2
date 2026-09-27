import 'package:foundation_values/foundation_values.dart';

/// Ledger stores public metadata references; Tags owns their lifecycle.
final class TagSelection {
  TagSelection(this.id, this.expectedVersion) {
    if (expectedVersion < 1)
      throw ArgumentError.value(expectedVersion, 'expectedVersion');
  }
  final PublicId id;
  final int expectedVersion;
}

/// Canonical selection order makes retries independent of chip selection order.
List<TagSelection> canonicalTags(Iterable<TagSelection> tags) {
  final values = tags.toList()
    ..sort((a, b) => a.id.value.compareTo(b.id.value));
  if (values.length > 16 ||
      values.map((v) => v.id).toSet().length != values.length) {
    throw ArgumentError('At most 16 distinct tags are supported per posting.');
  }
  return List.unmodifiable(values);
}
