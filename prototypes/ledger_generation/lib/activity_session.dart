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
  final PublicId _root, _id;
  final String _time;
}

final class LedgerActivity {
  const LedgerActivity._(this.entry, this.recordedAt, this.cursor);
  final LedgerEntry entry;
  final UtcInstant recordedAt;
  final LedgerActivityCursor cursor;
}

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
    final root = PublicId.parse(
      source.readNullable<String>('refund_of') ??
          source.readNullable<String>('reversal_of') ??
          selected.value,
    );
    if (before != null &&
        (before._workspace != workspace || before._root != root)) {
      throw ArgumentError('Activity cursor belongs to another transaction.');
    }
    final query = _entrySelect.replaceFirst(
      'SELECT e.id',
      'SELECT a.recorded_at AS activity_recorded_at,($_activityTime) AS activity_time,e.id',
    );
    final rows = await _db
        .customSelect(
          query +
              "JOIN audit a ON a.workspace=e.workspace AND a.entity_id=e.id "
                  "AND (a.kind='ledger.'||e.kind OR (e.kind='opening' AND a.kind='account.open')) "
                  "WHERE e.workspace=? AND (e.id=? ${_db.refundsAware ? 'OR r.original_id=?' : ''} ${_db.reversalsAware ? 'OR v.original_id=?' : ''}) "
                  "${before == null ? '' : 'AND (($_activityTime)< ? OR (($_activityTime)=? AND e.id<?))'} "
                  'ORDER BY activity_time DESC,e.id DESC LIMIT ?',
          variables: [
            Variable.withString(workspace.toString()),
            Variable.withString(root.value),
            if (_db.refundsAware) Variable.withString(root.value),
            if (_db.reversalsAware) Variable.withString(root.value),
            if (before != null) ...[
              Variable.withString(before._time),
              Variable.withString(before._time),
              Variable.withString(before._id.value),
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
            entry.id,
          ),
        );
      }),
    );
  });
}
