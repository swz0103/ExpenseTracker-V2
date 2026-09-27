part of 'ledger_store.dart';

extension NoteSession on LedgerSession {
  Future<EntryNote> entryNote(WorkspaceId workspace, PublicId id) =>
      _enqueue(() => NotesAdapter(_db).read(workspace, id));

  /// Presence alone never authorizes consuming a draft; replay verifies input.
  Future<bool> noteOperationExists(OperationKey operation) =>
      _enqueue(() => _hasOperation(operation));
  Future<CommitResult> reviseNote(
    OperationKey operation,
    NoteChange change, {
    void Function(String)? checkpoint,
  }) => _enqueue(
    () => _write(() async {
      if (!_db.notesAware) throw UnsupportedError('Notes are not enabled.');
      if (!await _hasOperation(operation)) {
        await _admitCapacity();
        if (await _count('event_note_revisions') >=
            LedgerSession.maxNoteChanges)
          throw PreviewCapacity();
      }
      final result = await NotesAdapter(_db)
          .revise(operation, change, checkpoint: checkpoint);
      if (!result.replayed) {
        await _checkRows(
          'event_note_revisions',
          'workspace=? AND operation_id=?',
          [operation.workspace.toString(), operation.operation.toString()],
        );
        await _checkOperationRows(operation);
      }
      return result;
    }),
  );
}
