part of 'ledger_store.dart';

final class SessionClosed implements Exception {}

final class PreviewCapacity implements Exception {}

final class AccountSummary {
  const AccountSummary(this.account, this.balance);
  final Account account;
  final Money balance;
}

final class LedgerEntry {
  const LedgerEntry(this.id, this.date, this.kind, this.accountId, this.amount);
  final PublicId id;
  final BusinessDate date;
  final PostingKind kind;
  final PublicId accountId;
  final Money amount;
}

/// Exclusive, bounded command scope. No public SQL or database handle.
/// Preview limits preserve room for portable backups; not full M3 capacity.
final class LedgerSession {
  LedgerSession._(this._db);
  static const maxEvents = 5000;
  static const maxAccounts = 32;
  static const maxCategories = 256;
  static const maxCategoryChanges = 1024;
  static const maxTags = 256;
  static const maxTagChanges = 1024;
  final ProbeDatabase _db;
  Future<void> _tail = Future.value();
  bool _closed = false;
  ({int rows, int bytes})? _capacityUsage;

  Future<T> _write<T>(Future<T> Function() work) async {
    final prior = _capacityUsage;
    try {
      return await _db.transaction(work);
    } catch (_) {
      // Admission and deltas must roll back with SQLite, including failed commit.
      _capacityUsage = prior;
      rethrow;
    }
  }

  Future<T> _enqueue<T>(Future<T> Function() work) {
    if (_closed) return Future.error(SessionClosed());
    final result = _tail.then((_) => work());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<void> _close() async {
    _closed = true;
    await _tail;
  }

  Future<int> _count(String table) async =>
      (await _db.customSelect('SELECT count(*) AS n FROM $table').getSingle())
          .read<int>('n');

  Future<bool> _hasOperation(OperationKey operation) async {
    final prior = await _db
        .customSelect(
          'SELECT operation_id FROM receipts WHERE workspace=? AND operation_id=?',
          variables: [
            Variable.withString(operation.workspace.toString()),
            Variable.withString(operation.operation.toString()),
          ],
        )
        .get();
    return prior.isNotEmpty;
  }

  Future<void> _admitCapacity() async {
    if (_capacityUsage != null) return;
    final admitted = validateSessionCapacity(
      await SnapshotCodec(
        categoryAware: _db.categoryAware,
        generationAware: true,
        categoryReferences: _db.categoryReferences,
        tagsAware: _db.tagsAware,
      ).capture(_db),
      categoryAware: _db.categoryAware,
      categoryReferences: _db.categoryReferences,
      tagsAware: _db.tagsAware,
    );
    _capacityUsage = _snapshotUsage(admitted);
  }

  Future<void> _capacity(Posting posting, {bool account = false}) async {
    // Replays and conflicts must retain their original meaning at capacity.
    if (await _hasOperation(posting.operation)) return;
    await _admitCapacity();
    if (await _count('events') >= maxEvents ||
        (account && await _count('accounts') >= maxAccounts)) {
      throw PreviewCapacity();
    }
  }

  Future<CommitResult> createAccount(Account account, Posting opening) =>
      _enqueue(
        () => _write(() async {
          await _capacity(opening, account: true);
          final result = await FinancialWorkflows(
            _db,
            sourceContext: 'preview-manual-v1',
          ).createAccount(account, opening);
          if (!result.replayed)
            await _checkFinancialRows(opening, account: account);
          return result;
        }),
      );

  Future<CommitResult> post(
    Posting posting, {
    Iterable<TagSelection> tags = const [],
  }) {
    final selections = canonicalTags(tags);
    return _enqueue(
      () => _write(() async {
        if (posting.kind != PostingKind.income &&
            posting.kind != PostingKind.expense) {
          throw UnsupportedError('Preview accepts income and expense only');
        }
        await _capacity(posting);
        final result = await FinancialWorkflows(
          _db,
          sourceContext: 'preview-manual-v1',
        ).post(posting, tags: selections);
        if (!result.replayed) {
          await _checkFinancialRows(posting);
          if (_db.tagsAware)
            await _checkRows('event_tags', 'workspace=? AND event_id=?', [
              posting.operation.workspace.toString(),
              posting.id.value,
            ]);
        }
        return result;
      }),
    );
  }

  Future<List<AccountSummary>> accounts(WorkspaceId workspace) =>
      _enqueue(() async {
        final rows = await _db
            .customSelect(
              'SELECT id FROM accounts WHERE workspace=? ORDER BY id',
              variables: [Variable.withString(workspace.toString())],
            )
            .get();
        final adapter = AccountsAdapter(_db);
        final ledger = LedgerAdapter(_db);
        return List.unmodifiable(
          await Future.wait(
            rows.map((row) async {
              final account = await adapter.read(
                workspace,
                PublicId.parse(row.read<String>('id')),
              );
              final balance = await ledger.balance(
                PostingAccount(
                  id: account.id,
                  workspace: workspace,
                  currency: account.currency,
                  expectedVersion: account.version,
                ),
              );
              return AccountSummary(account, balance);
            }),
          ),
        );
      });

  /// Keyset pagination by business date and public ID; no OFFSET drift.
  Future<List<LedgerEntry>> entries(
    WorkspaceId workspace, {
    LedgerEntry? before,
    int limit = 30,
  }) => _enqueue(() async {
    if (limit < 1 || limit > 100) throw ArgumentError.value(limit, 'limit');
    final rows = await _db
        .customSelect(
          'SELECT e.id,e.business_date,e.kind,l.account_id,l.amount,l.currency,l.scale '
          'FROM events e JOIN legs l ON l.workspace=e.workspace AND l.event_id=e.id AND l.ordinal=0 '
          'WHERE e.workspace=? ${before == null ? '' : 'AND (e.business_date < ? OR (e.business_date = ? AND e.id < ?))'} '
          'ORDER BY e.business_date DESC,e.id DESC LIMIT ?',
          variables: [
            Variable.withString(workspace.toString()),
            if (before != null) ...[
              Variable.withString(before.date.toString()),
              Variable.withString(before.date.toString()),
              Variable.withString(before.id.value),
            ],
            Variable.withInt(limit),
          ],
        )
        .get();
    return List.unmodifiable(
      rows.map(
        (r) => LedgerEntry(
          PublicId.parse(r.read<String>('id')),
          BusinessDate.parse(r.read<String>('business_date')),
          PostingKind.values.byName(r.read<String>('kind')),
          PublicId.parse(r.read<String>('account_id')),
          Money(
            Currency(r.read<String>('currency'), r.read<int>('scale')),
            BigInt.from(r.read<int>('amount')),
          ),
        ),
      ),
    );
  });

  Future<List<int>> snapshot() => _enqueue(
    () => SnapshotCodec(
      generationAware: true,
      categoryAware: _db.categoryAware,
      categoryReferences: _db.categoryReferences,
      tagsAware: _db.tagsAware,
    ).capture(_db),
  );

  Future<List<WorkspaceId>> workspaces() => _enqueue(() async {
    final rows = await _db
        .customSelect(
          'SELECT DISTINCT workspace FROM accounts '
          '${_db.categoryAware ? 'UNION SELECT workspace FROM categories ' : ''}'
          '${_db.tagsAware ? 'UNION SELECT workspace FROM tags ' : ''}'
          'ORDER BY workspace',
        )
        .get();
    return List.unmodifiable(
      rows.map((r) => WorkspaceId.parse(r.read<String>('workspace'))),
    );
  });
}
