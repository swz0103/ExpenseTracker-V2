part of 'ledger_store.dart';

/// Opaque keyset bound to one workspace and original transaction.
final class LedgerActivityCursor {
  const LedgerActivityCursor._(
    this._workspace,
    this._root,
    this._time,
    this._id,
  );
  final WorkspaceId _workspace;
  final PublicId _root;
  final String _id;
  final String _time;
}

final class LedgerActivity {
  const LedgerActivity._(
    this.entry,
    this.recordedAt,
    this.cursor,
    this.noteRevision,
    this.correctionRole,
    this.auditKind,
  );
  final LedgerEntry entry;
  final UtcInstant recordedAt;
  final LedgerActivityCursor cursor;
  final EntryNote? noteRevision;
  final CorrectionActivityRole? correctionRole;
  final String auditKind;
  String get key => cursor._id;
}

enum CorrectionActivityRole { original, reversal, replacement }

/// Audit timestamps accept 0..6 fractional digits. Normalize before lexical
/// ordering; neither SQLite millisecond date functions nor floating point can
/// preserve every supported instant.
const _activityTime =
    "substr(a.recorded_at,1,19)||'.'||substr("
    "(CASE WHEN substr(a.recorded_at,20,1)='.' "
    "THEN substr(a.recorded_at,21,length(a.recorded_at)-21) ELSE '' END)"
    "||'000000',1,6)";

extension ActivitySession on LedgerSession {
  /// The selected event and its refund family, newest recorded operation first.
  /// This read never turns metadata operations into financial events.
  Future<List<LedgerActivity>> activity(
    WorkspaceId workspace,
    PublicId selected, {
    LedgerActivityCursor? before,
    int limit = 30,
  }) => _enqueue(() async {
    if (limit < 1 || limit > 100) throw ArgumentError.value(limit, 'limit');
    final source = await _db
        .customSelect(
          _entrySelect + 'WHERE e.workspace=? AND e.id=?',
          variables: [
            Variable.withString(workspace.toString()),
            Variable.withString(selected.value),
          ],
        )
        .getSingleOrNull();
    if (source == null) throw StateError('Ledger event not found.');
    var root = PublicId.parse(
      source.readNullable<String>('refund_of') ??
          source.readNullable<String>('reversal_of') ??
          selected.value,
    );
    if (_db.correctionsAware) {
      // A replacement may itself be corrected. Walk toward the oldest source
      // so every member of the chain shares one cursor and activity family.
      final ancestor = await _db
          .customSelect(
            'WITH RECURSIVE ancestors(id) AS ('
            'SELECT ? UNION SELECT c.original_id FROM event_corrections c '
            'JOIN ancestors a ON c.replacement_id=a.id WHERE c.workspace=?) '
            'SELECT id FROM ancestors WHERE id NOT IN '
            '(SELECT replacement_id FROM event_corrections WHERE workspace=?) LIMIT 1',
            variables: [
              Variable.withString(root.value),
              Variable.withString(workspace.toString()),
              Variable.withString(workspace.toString()),
            ],
          )
          .getSingleOrNull();
      if (ancestor == null) throw StateError('Invalid correction chain.');
      root = PublicId.parse(ancestor.read<String>('id'));
    }
    if (before != null &&
        (before._workspace != workspace || before._root != root)) {
      throw ArgumentError('Activity cursor belongs to another transaction.');
    }
    final key =
        "CASE WHEN a.kind='ledger.note' THEN 'n:'||a.operation_id "
        "WHEN a.kind='ledger.tombstone' THEN 't:'||a.operation_id "
        "ELSE 'e:'||e.id END";
    final correctionRole = _db.correctionsAware
        ? "CASE WHEN cp.replacement_id IS NOT NULL THEN 'replacement' "
              "WHEN cr.reversal_id IS NOT NULL THEN 'reversal' "
              "WHEN c.original_id IS NOT NULL THEN 'original' ELSE NULL END"
        : 'NULL';
    final query = _entrySelect.replaceFirst(
      'SELECT e.id',
      'SELECT a.kind AS activity_kind,a.recorded_at AS activity_recorded_at,($_activityTime) AS activity_time,($key) AS activity_key,'
          '${_db.notesAware ? "n.text" : "NULL"} AS revision_text,${_db.notesAware ? "n.revision" : "NULL"} AS revision_number,'
          '$correctionRole AS correction_role,e.id',
    );
    final family = _db.correctionsAware
        ? 'WITH RECURSIVE family(id) AS ('
              'SELECT ? UNION SELECT c.replacement_id FROM event_corrections c '
              'JOIN family f ON c.original_id=f.id WHERE c.workspace=?) '
        : '';
    final scope = _db.correctionsAware
        ? 'e.id IN (SELECT id FROM family) '
              '${_db.refundsAware ? 'OR r.original_id IN (SELECT id FROM family) ' : ''}'
              '${_db.reversalsAware ? 'OR v.original_id IN (SELECT id FROM family)' : ''}'
        : 'e.id=? ${_db.refundsAware ? 'OR r.original_id=?' : ''} '
              '${_db.reversalsAware ? 'OR v.original_id=?' : ''}';
    final rows = await _db
        .customSelect(
          family +
              query +
              "JOIN audit a ON a.workspace=e.workspace AND a.entity_id=e.id "
                  "AND (a.kind='ledger.'||e.kind OR (e.kind='opening' AND a.kind='account.open') ${_db.notesAware ? "OR a.kind='ledger.note'" : ''} ${_db.tombstonesAware ? "OR a.kind='ledger.tombstone'" : ''}) "
                  "${_db.notesAware ? 'LEFT JOIN event_note_revisions n ON n.workspace=a.workspace AND n.operation_id=a.operation_id ' : ''}"
                  "${_db.correctionsAware ? 'LEFT JOIN event_corrections cr ON cr.workspace=e.workspace AND cr.reversal_id=e.id LEFT JOIN event_corrections cp ON cp.workspace=e.workspace AND cp.replacement_id=e.id ' : ''}"
                  'WHERE e.workspace=? AND ($scope) '
                  "${before == null ? '' : 'AND (($_activityTime)< ? OR (($_activityTime)=? AND ($key)<?))'} "
                  'ORDER BY activity_time DESC,activity_key DESC LIMIT ?',
          variables: [
            if (_db.correctionsAware) ...[
              Variable.withString(root.value),
              Variable.withString(workspace.toString()),
            ],
            Variable.withString(workspace.toString()),
            if (!_db.correctionsAware) ...[
              Variable.withString(root.value),
              if (_db.refundsAware) Variable.withString(root.value),
              if (_db.reversalsAware) Variable.withString(root.value),
            ],
            if (before != null) ...[
              Variable.withString(before._time),
              Variable.withString(before._time),
              Variable.withString(before._id),
            ],
            Variable.withInt(limit),
          ],
        )
        .get();
    return List.unmodifiable(
      rows.map((row) {
        final entry = _entryFromRow(row);
        return LedgerActivity._(
          entry,
          UtcInstant.parse(row.read<String>('activity_recorded_at')),
          LedgerActivityCursor._(
            workspace,
            root,
            row.read<String>('activity_time'),
            row.read<String>('activity_key'),
          ),
          row.readNullable<int>('revision_number') == null
              ? null
              : EntryNote(
                  row.read<int>('revision_number'),
                  row.read<String>('revision_text'),
                ),
          row.readNullable<String>('correction_role') == null
              ? null
              : CorrectionActivityRole.values.byName(
                  row.read<String>('correction_role'),
                ),
          row.read<String>('activity_kind'),
        );
      }),
    );
  });
}
