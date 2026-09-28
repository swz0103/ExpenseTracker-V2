part of 'ledger_store.dart';

const _simpleImportPrefix = 'import-simple-v1:';
final _simpleImportDigest = RegExp(r'^[0-9a-f]{64}$');

final class ImportProvenanceInvalid implements Exception {}

final class SimpleImportResult {
  SimpleImportResult(List<PublicId> entryIds, this.inserted, this.replayed)
    : entryIds = List.unmodifiable(entryIds);

  final List<PublicId> entryIds;
  final int inserted;
  final int replayed;
}

/// A whole document commits or rolls back. Provenance lives with each event in
/// the portable snapshot, so a retry after commit-without-response skips it.
extension SimpleImportSession on LedgerSession {
  Future<SimpleImportResult> importSimple(
    SimpleImportPreview preview,
  ) => _enqueue(
    () => _write(() async {
      final workspace = preview.destinationWorkspace;
      final known = await _simpleImportProvenance(workspace);
      final pending = <SimpleImportRow>[];
      final ids = List<PublicId?>.filled(preview.rows.length, null);
      for (final row in preview.rows) {
        final source = row.source;
        final key = (preview.sourceWorkspace, source.sourceRecordId);
        final previous = known[key];
        if (previous == null) {
          pending.add(row);
        } else if (previous.$1 != _simpleFingerprint(source)) {
          throw ExchangeException('source_conflict', row.number);
        } else {
          ids[row.number - 1] = previous.$2;
        }
      }
      if (pending.isEmpty) {
        return SimpleImportResult(ids.cast<PublicId>(), 0, ids.length);
      }
      await _admitCapacity();
      if (await _count('events') > LedgerSession.maxEvents - pending.length ||
          (!_db.notesAware &&
              pending.any((row) => row.source.note.isNotEmpty)) ||
          (_db.notesAware &&
              await _count('event_note_revisions') >
                  LedgerSession.maxNoteChanges -
                      pending
                          .where((row) => row.source.note.isNotEmpty)
                          .length)) {
        throw PreviewCapacity();
      }

      final accounts = AccountsAdapter(_db);
      for (final row in pending) {
        final source = row.source;
        final target = row.targetAccount;
        Account live;
        try {
          live = await accounts.read(workspace, target.id);
          live.requirePosting(
            workspace: workspace,
            currency: source.amount.currency,
            expectedVersion: target.version,
            date: source.date,
          );
        } on AccountException catch (error) {
          throw ExchangeException('target_${error.code.name}', row.number);
        }
        final account = PostingAccount(
          id: live.id,
          workspace: workspace,
          currency: live.currency,
          expectedVersion: live.version,
        );
        final id = PublicId.generate();
        final posting = source.kind == PostingKind.income
            ? Posting.income(
                id: id,
                operation: OperationKey(
                  workspace,
                  OperationId(PublicId.generate()),
                ),
                date: source.date,
                account: account,
                amount: source.amount,
              )
            : Posting.expense(
                id: id,
                operation: OperationKey(
                  workspace,
                  OperationId(PublicId.generate()),
                ),
                date: source.date,
                account: account,
                amount: source.amount,
              );
        await _capacity(posting);
        final provenance =
            '$_simpleImportPrefix${preview.sourceWorkspace}:${source.sourceRecordId.value}:${_simpleFingerprint(source)}';
        await FinancialWorkflows(_db, sourceContext: provenance).post(posting);
        await _checkFinancialRows(posting);
        if (source.note.isNotEmpty) {
          final noteOperation = OperationKey(
            workspace,
            OperationId(PublicId.generate()),
          );
          await NotesAdapter(_db)
              .revise(noteOperation, NoteChange(id, 0, source.note));
          await _checkRows(
            'event_note_revisions',
            'workspace=? AND operation_id=?',
            [workspace.toString(), noteOperation.operation.toString()],
          );
          await _checkOperationRows(noteOperation);
        }
        ids[row.number - 1] = id;
      }
      return SimpleImportResult(
        ids.cast<PublicId>(),
        pending.length,
        preview.rows.length - pending.length,
      );
    }),
  );

  Future<Map<(WorkspaceId, PublicId), (String, PublicId)>>
  _simpleImportProvenance(WorkspaceId workspace) async {
    final rows = await _db
        .customSelect(
          'SELECT id,source_context FROM events WHERE workspace=? '
          'AND source_context LIKE ?',
          variables: [
            Variable.withString(workspace.toString()),
            Variable.withString('$_simpleImportPrefix%'),
          ],
        )
        .get();
    final known = <(WorkspaceId, PublicId), (String, PublicId)>{};
    for (final row in rows) {
      final parts = row.read<String>('source_context').split(':');
      if (parts.length != 4 ||
          parts[0] != 'import-simple-v1' ||
          !_simpleImportDigest.hasMatch(parts[3])) {
        throw ImportProvenanceInvalid();
      }
      try {
        final sourceWorkspace = WorkspaceId.parse(parts[1]);
        final recordId = PublicId.parse(parts[2]);
        if (sourceWorkspace.toString() != parts[1] ||
            recordId.value != parts[2]) {
          throw ImportProvenanceInvalid();
        }
        final key = (sourceWorkspace, recordId);
        if (known.containsKey(key)) throw ImportProvenanceInvalid();
        known[key] = (parts[3], PublicId.parse(row.read<String>('id')));
      } on FormatException {
        throw ImportProvenanceInvalid();
      }
    }
    return known;
  }
}

String _simpleFingerprint(SimpleTransaction row) => sha256
    .convert(
      utf8.encode(
        jsonEncode([
          row.date.toString(),
          row.kind.name,
          row.accountId.value,
          row.amount.currency.code,
          row.amount.currency.scale,
          row.amount.minorUnits.toString(),
          row.note,
        ]),
      ),
    )
    .toString();
