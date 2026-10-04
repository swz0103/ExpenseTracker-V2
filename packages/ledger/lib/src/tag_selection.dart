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
