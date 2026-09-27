part of 'ledger_store.dart';

final class SavedTagReference {
  const SavedTagReference(this.id, this.version, this.sequence);
  final PublicId id;
  final int version, sequence;
}

extension TagReferences on LedgerSession {
  Future<List<SavedTagReference>> tagsFor(
    WorkspaceId workspace,
    PublicId event,
  ) => _enqueue(() async {
    if (!_db.tagsAware) throw UnsupportedError('Tags require schema 6.');
    final rows = await _db
        .customSelect(
          'SELECT tag_id,tag_version,tag_sequence FROM event_tags WHERE workspace=? AND event_id=? ORDER BY tag_id',
          variables: [
            Variable.withString(workspace.toString()),
            Variable.withString(event.value),
          ],
        )
        .get();
    return List.unmodifiable(
      rows.map(
        (r) => SavedTagReference(
          PublicId.parse(r.read<String>('tag_id')),
          r.read<int>('tag_version'),
          r.read<int>('tag_sequence'),
        ),
      ),
    );
  });
}
