part of 'ledger_store.dart';

/// Immutable historical attribution. Current category names/resolution are read
/// through categories(), leaving the recorded ID/version/sequence unchanged.
final class LedgerAllocation {
  const LedgerAllocation(
    this.categoryId,
    this.amount,
    this.categoryVersion,
    this.categorySequence,
  );
  final PublicId categoryId;
  final Money amount;
  final int categoryVersion, categorySequence;
}

extension AllocationSession on LedgerSession {
  /// Missing/wrong-workspace events are distinct from a valid unallocated event.
  Future<List<LedgerAllocation>> allocations(
    WorkspaceId workspace,
    PublicId eventId,
  ) => _enqueue(() async {
    if (!_db.categoryReferences) {
      throw UnsupportedError('Category references are not enabled.');
    }
    final variables = [
      Variable.withString(workspace.toString()),
      Variable.withString(eventId.value),
    ];
    final event = await _db
        .customSelect(
          'SELECT currency,scale FROM events WHERE workspace=? AND id=?',
          variables: variables,
        )
        .getSingleOrNull();
    if (event == null) throw StateError('Ledger event not found.');
    final currency = Currency(
      event.read<String>('currency'),
      event.read<int>('scale'),
    );
    final rows = await _db
        .customSelect(
          'SELECT * FROM allocations WHERE workspace=? AND event_id=? ORDER BY category_id',
          variables: variables,
        )
        .get();
    return List.unmodifiable(
      rows.map(
        (row) => LedgerAllocation(
          PublicId.parse(row.read<String>('category_id')),
          Money(currency, BigInt.from(row.read<int>('amount'))),
          row.read<int>('category_version'),
          row.read<int>('category_sequence'),
        ),
      ),
    );
  });
}
