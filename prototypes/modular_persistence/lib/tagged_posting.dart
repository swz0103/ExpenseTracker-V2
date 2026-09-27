import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';

import 'database.dart';
import 'tags_adapter.dart';

/// Canonical selection order makes retries independent of chip selection order.
List<TagSelection> canonicalTags(Iterable<TagSelection> tags) {
  final values = tags.toList()
    ..sort((a, b) => a.id.value.compareTo(b.id.value));
  if (values.length > 16 ||
      values.map((v) => v.id).toSet().length != values.length) {
    throw ArgumentError('At most 16 distinct tags are supported per posting.');
  }
  return List.unmodifiable(values);
}

Future<int?> validatePostingTags(
  ProbeDatabase db,
  Posting posting,
  List<TagSelection> tags,
) async {
  if (tags.isEmpty) return null;
  if (!db.tagsAware ||
      ![PostingKind.income, PostingKind.expense].contains(posting.kind)) {
    throw UnsupportedError('Tags require schema 6 and an income or expense.');
  }
  final adapter = TagsAdapter(db);
  final catalog = await adapter.read(posting.operation.workspace);
  for (final tag in tags) {
    catalog.requireSelection(
      workspace: posting.operation.workspace,
      id: tag.id,
      expectedVersion: tag.expectedVersion,
    );
  }
  return adapter.currentSequence(posting.operation.workspace);
}

Future<void> insertPostingTags(
  ProbeDatabase db,
  WorkspaceId workspace,
  PublicId event,
  List<TagSelection> tags,
  int? sequence,
) async {
  for (final tag in tags) {
    await db.customStatement('INSERT INTO event_tags VALUES(?,?,?,?,?)', [
      workspace.toString(),
      event.value,
      tag.id.value,
      tag.expectedVersion,
      sequence,
    ]);
  }
}
