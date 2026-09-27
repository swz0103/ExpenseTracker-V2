import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';

import 'database.dart';
import 'tags_adapter.dart';

export 'package:ledger/ledger.dart' show canonicalTags;

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
