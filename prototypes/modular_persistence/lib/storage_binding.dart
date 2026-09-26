import 'package:foundation_values/foundation_values.dart';

/// Local-only identity. Never copied from a portable backup to its new target.
final class StorageBinding {
  StorageBinding(this.generation, this.slot, this.operation, this.fingerprint) {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(fingerprint)) {
      throw const FormatException('Invalid installation fingerprint');
    }
  }
  final PublicId generation;
  final PublicId slot;
  final OperationId operation;
  final String fingerprint;
  List<String> get values => [
    generation.value,
    slot.value,
    operation.toString(),
    fingerprint,
  ];
}
