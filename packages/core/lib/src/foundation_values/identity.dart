import 'package:uuid/uuid.dart';

/// Canonical RFC 9562 version 7 public ID. Not a database row ID or a secret.
final class PublicId {
  PublicId.parse(String input) : value = input.toLowerCase() {
    if (!RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    ).hasMatch(value)) {
      throw const FormatException('Expected a UUID v7 public ID.');
    }
  }
  factory PublicId.generate() => PublicId.parse(const Uuid().v7());
  final String value;
  @override
  bool operator ==(Object other) => other is PublicId && value == other.value;
  @override
  int get hashCode => value.hashCode;
  @override
  String toString() => value;
}

final class WorkspaceId {
  const WorkspaceId(this.id);
  factory WorkspaceId.parse(String input) => WorkspaceId(PublicId.parse(input));
  final PublicId id;
  @override
  bool operator ==(Object other) => other is WorkspaceId && id == other.id;
  @override
  int get hashCode => Object.hash(WorkspaceId, id);
  @override
  String toString() => id.value;
}

/// Retain this identity for retries; generate a fresh one for a new intention.
final class OperationId {
  const OperationId(this.id);
  factory OperationId.parse(String input) => OperationId(PublicId.parse(input));
  final PublicId id;
  @override
  bool operator ==(Object other) => other is OperationId && id == other.id;
  @override
  int get hashCode => Object.hash(OperationId, id);
  @override
  String toString() => id.value;
}

final class OperationKey {
  const OperationKey(this.workspace, this.operation);
  final WorkspaceId workspace;
  final OperationId operation;
  @override
  bool operator ==(Object other) =>
      other is OperationKey &&
      workspace == other.workspace &&
      operation == other.operation;
  @override
  int get hashCode => Object.hash(workspace, operation);
}
