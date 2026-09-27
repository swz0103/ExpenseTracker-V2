import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';

import 'database.dart';
import 'operations.dart';

final class InvalidNoteHistory implements Exception {
  const InvalidNoteHistory();
}

final class NotesAdapter {
  NotesAdapter(this.db);
  final ProbeDatabase db;
  Future<EntryNote> read(WorkspaceId workspace, PublicId id) async {
    if (!db.notesAware) throw UnsupportedError('Notes are not enabled.');
    final vars = [
      Variable.withString(workspace.toString()),
      Variable.withString(id.value),
    ];
    final event = await db
        .customSelect(
          'SELECT id FROM events WHERE workspace=? AND id=?',
          variables: vars,
        )
        .getSingleOrNull();
    if (event == null) throw const NoteException(NoteError.missingEntry);
    final row = await db
        .customSelect(
          'SELECT revision,text FROM event_note_revisions WHERE workspace=? AND event_id=? ORDER BY revision DESC LIMIT 1',
          variables: vars,
        )
        .getSingleOrNull();
    return row == null
        ? const EntryNote(0, '')
        : EntryNote(row.read<int>('revision'), row.read<String>('text'));
  }

  Future<CommitResult> revise(
    OperationKey operation,
    NoteChange change, {
    void Function(String)? checkpoint,
  }) {
    if (!db.notesAware) throw UnsupportedError('Notes are not enabled.');
    return OperationWriter(db).commit(
      operation,
      jsonEncode(change.input),
      change.entryId,
      () async {
        final next = change.apply(
          await read(operation.workspace, change.entryId),
        );
        await db.customStatement(
          'INSERT INTO event_note_revisions VALUES(?,?,?,?,?)',
          [
            operation.workspace.toString(),
            change.entryId.value,
            next.revision,
            operation.operation.toString(),
            next.text,
          ],
        );
        checkpoint?.call('note');
      },
      'ledger.note',
      checkpoint,
    );
  }
}

/// Rebuilds every version from its exact receipt; no mutable note projection.
Future<Set<(String, String)>> validateNoteHistory(ProbeDatabase db) async {
  final operations = <(String, String)>{};
  final previous = <(String, String), EntryNote>{};
  final rows = await db.customSelect(
    '''SELECT n.*, r.input,r.result_id,a.entity_id,a.kind
    FROM event_note_revisions n
    LEFT JOIN receipts r ON r.workspace=n.workspace AND r.operation_id=n.operation_id
    LEFT JOIN audit a ON a.workspace=n.workspace AND a.operation_id=n.operation_id
    ORDER BY n.workspace,n.event_id,n.revision''',
  ).get();
  try {
    for (final row in rows) {
      final ws = WorkspaceId.parse(row.read<String>('workspace'));
      final id = PublicId.parse(row.read<String>('event_id'));
      final op = OperationId.parse(row.read<String>('operation_id'));
      final command = NoteChange.fromInput(
        jsonDecode(row.read<String>('input')),
      );
      final key = (ws.toString(), id.value);
      final next = command.apply(previous[key] ?? const EntryNote(0, ''));
      if (command.entryId != id ||
          row.read<String>('result_id') != id.value ||
          row.read<String>('entity_id') != id.value ||
          row.read<String>('kind') != 'ledger.note' ||
          next.revision != row.read<int>('revision') ||
          next.text != row.read<String>('text') ||
          !operations.add((ws.toString(), op.toString())))
        throw const InvalidNoteHistory();
      previous[key] = next;
    }
    return operations;
  } catch (_) {
    throw const InvalidNoteHistory();
  }
}
