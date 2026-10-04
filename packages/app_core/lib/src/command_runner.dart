import 'package:foundation_values/foundation_values.dart';

import 'failure.dart';
import 'unit_of_work.dart';

/// A request to change state. [input] is the canonical encoding of every
/// field that matters; a retry with the same [operation] must produce the
/// same input, or it is a conflict.
abstract interface class Command<R> {
  OperationKey get operation;

  String get input;

  String encodeResult(R result);

  R decodeResult(String encoded);
}

final class CommandOutcome<R> {
  const CommandOutcome(this.value, {required this.replayed});

  final R value;

  /// True when an earlier attempt had already committed this operation and
  /// its recorded result was returned without running the handler again.
  final bool replayed;
}

/// Runs commands one at a time, each in its own unit of work.
///
/// Writes queue behind each other instead of failing as busy, so screens,
/// draft saves and background jobs never see a spurious "try again". A
/// command's journal entry commits in the same transaction as its effects,
/// so a retry after a crash or a lost reply returns the original result.
final class CommandRunner<T extends WriteTransaction> {
  CommandRunner(this._unitOfWork);

  final UnitOfWork<T> _unitOfWork;
  Future<void> _tail = Future.value();

  Future<CommandOutcome<R>> run<R>(
    Command<R> command,
    Future<R> Function(T transaction) handler,
  ) {
    final result = _tail.then((_) => _execute(command, handler));
    _tail = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  /// Runs [job] in the same queue as commands, after every command already
  /// queued and before any queued later. Use it for work that needs the
  /// store to itself, such as a backup; [job] opens its own transaction.
  Future<R> exclusive<R>(Future<R> Function() job) {
    final result = _tail.then((_) => job());
    _tail = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  Future<CommandOutcome<R>> _execute<R>(
    Command<R> command,
    Future<R> Function(T transaction) handler,
  ) => _unitOfWork.write((transaction) async {
    final earlier = await transaction.findOperation(command.operation);
    if (earlier != null) {
      if (earlier.input != command.input) {
        throw const AppFailure.operationConflict();
      }
      return CommandOutcome(
        command.decodeResult(earlier.result),
        replayed: true,
      );
    }
    final value = await handler(transaction);
    await transaction.recordOperation(
      RecordedOperation(
        key: command.operation,
        input: command.input,
        result: command.encodeResult(value),
      ),
    );
    return CommandOutcome(value, replayed: false);
  });
}
