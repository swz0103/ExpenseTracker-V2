import 'package:foundation_values/foundation_values.dart';

import 'unit_of_work.dart';

/// Reference in-memory unit of work. It defines the behaviour every storage
/// adapter must match: writes become visible only on commit, a throwing body
/// commits nothing, and overlapping writes are a programming error.
final class MemoryStore implements UnitOfWork<MemoryTransaction> {
  final _operations = <OperationKey, RecordedOperation>{};
  final _events = <String>[];
  bool _writing = false;
  int _commits = 0;

  List<String> get events => List.unmodifiable(_events);

  int get commits => _commits;

  @override
  Future<R> write<R>(
    Future<R> Function(MemoryTransaction transaction) body,
  ) async {
    if (_writing) throw StateError('Overlapping write transactions.');
    _writing = true;
    final transaction = MemoryTransaction._(this);
    try {
      final result = await body(transaction);
      _operations.addAll(transaction._operations);
      _events.addAll(transaction._events);
      _commits++;
      return result;
    } finally {
      transaction._open = false;
      _writing = false;
    }
  }
}

final class MemoryTransaction implements WriteTransaction {
  MemoryTransaction._(this._store);

  final MemoryStore _store;
  final _operations = <OperationKey, RecordedOperation>{};
  final _events = <String>[];
  bool _open = true;

  /// Committed events followed by this transaction's own writes.
  List<String> get events => List.unmodifiable([..._store._events, ..._events]);

  void append(String event) {
    _requireOpen();
    _events.add(event);
  }

  @override
  Future<RecordedOperation?> findOperation(OperationKey key) async {
    _requireOpen();
    return _operations[key] ?? _store._operations[key];
  }

  @override
  Future<void> recordOperation(RecordedOperation operation) async {
    if (await findOperation(operation.key) != null) {
      throw StateError('Operation recorded twice.');
    }
    _operations[operation.key] = operation;
  }

  void _requireOpen() {
    if (!_open) throw StateError('Transaction already finished.');
  }
}
