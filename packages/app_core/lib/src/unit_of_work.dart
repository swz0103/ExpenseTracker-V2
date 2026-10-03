import 'package:foundation_values/foundation_values.dart';

/// A committed command: its key, the canonical input it was committed with,
/// and its canonical result, so a retry returns the same result.
final class RecordedOperation {
  const RecordedOperation({
    required this.key,
    required this.input,
    required this.result,
  });

  final OperationKey key;
  final String input;
  final String result;
}

/// Work for another component (cloud backup, reminders) that becomes visible
/// only when the transaction that created it commits.
final class OutboxMessage {
  const OutboxMessage({
    required this.id,
    required this.topic,
    required this.payload,
  });

  final PublicId id;
  final String topic;
  final String payload;
}

/// The operations every write transaction offers. Storage adapters extend
/// this with their own repositories.
abstract interface class WriteTransaction {
  Future<RecordedOperation?> findOperation(OperationKey key);

  Future<void> recordOperation(RecordedOperation operation);

  Future<void> enqueue(OutboxMessage message);
}

/// Runs [write] bodies atomically: all of a body's writes commit together,
/// or none do when it throws.
abstract interface class UnitOfWork<T extends WriteTransaction> {
  Future<R> write<R>(Future<R> Function(T transaction) body);
}
