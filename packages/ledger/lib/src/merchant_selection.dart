import 'package:foundation_values/foundation_values.dart';

/// Ledger stores public metadata references; Merchants owns their lifecycle.
final class MerchantSelection {
  MerchantSelection(this.id, this.expectedVersion) {
    if (expectedVersion < 1)
      throw ArgumentError.value(expectedVersion, 'expectedVersion');
  }
  final PublicId id;
  final int expectedVersion;
}
