/// What kind of problem stopped a command. Callers branch on this, never on
/// message text.
enum FailureKind {
  /// The same operation key was reused for different input.
  conflict,

  /// A business rule refused the command; nothing was written.
  rejected,

  /// Something the command refers to does not exist.
  notFound,

  /// Storage could not complete the write; the outcome is known (nothing
  /// was committed) and the same command may be retried.
  unavailable,
}

/// A typed, non-secret failure. [diagnostic] is a stable machine-readable
/// code such as `operation.input-mismatch` that names the rule or table
/// involved, so field reports are diagnosable without leaking user data.
final class AppFailure implements Exception {
  const AppFailure(this.kind, this.diagnostic);

  /// The operation key was already committed with different input.
  const AppFailure.operationConflict()
    : this(FailureKind.conflict, 'operation.input-mismatch');

  final FailureKind kind;
  final String diagnostic;

  @override
  bool operator ==(Object other) =>
      other is AppFailure &&
      kind == other.kind &&
      diagnostic == other.diagnostic;

  @override
  int get hashCode => Object.hash(kind, diagnostic);

  @override
  String toString() => 'AppFailure(${kind.name}, $diagnostic)';
}
