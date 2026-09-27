import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:foundation_values/foundation_values.dart';

import 'database.dart';
import 'tags_adapter.dart';

/// Verify metadata at posting time, then bind exact original IDs/versions to
/// the same receipt as the financial event. A merge never rewrites those IDs.
Future<Set<(String, String)>> validateTagReferences(ProbeDatabase db) async {
  if (!db.tagsAware) throw const InvalidTagHistory();
  final pending = <(String, int), List<QueryRow>>{};
  final byEvent = <(String, String), Map<String, QueryRow>>{};
  final sequences = <(String, String), int>{};
  final rows = await db.customSelect(
    '''SELECT t.*,e.kind FROM event_tags t LEFT JOIN events e
    ON e.workspace=t.workspace AND e.id=t.event_id''',
  ).get();
  for (final row in rows) {
    final ws = row.read<String>('workspace'),
        event = row.read<String>('event_id'),
        tag = row.read<String>('tag_id');
    final key = (ws, event), sequence = row.read<int>('tag_sequence');
    final selected = byEvent[key] ??= {};
    if (sequence < 1 ||
        row.read<int>('tag_version') < 1 ||
        !['income', 'expense'].contains(row.readNullable<String>('kind')) ||
        (sequences.containsKey(key) && sequences[key] != sequence) ||
        selected.containsKey(tag)) {
      throw const InvalidTagHistory();
    }
    sequences[key] = sequence;
    selected[tag] = row;
    (pending[(ws, sequence)] ??= []).add(row);
  }
  final verified = await validateTagHistory(
    db,
    visit: (ws, sequence, state) {
      for (final row in pending.remove((ws, sequence)) ?? <QueryRow>[]) {
        state.requireSelection(
          workspace: WorkspaceId.parse(ws),
          id: PublicId.parse(row.read<String>('tag_id')),
          expectedVersion: row.read<int>('tag_version'),
        );
      }
    },
  );
  if (pending.isNotEmpty) throw const InvalidTagHistory();
  for (final receipt in await db.customSelect('SELECT * FROM receipts').get()) {
    final input = jsonDecode(receipt.read<String>('input'));
    if (input is! List || input.isEmpty) throw const InvalidTagHistory();
    final key = (
      receipt.read<String>('workspace'),
      receipt.read<String>('result_id'),
    );
    // Metadata commands may share a public ID with a different module.
    if (input.first == 'tag-v1' ||
        input.first == 'category-v1' ||
        input.first == 'archive-v1')
      continue;
    final selected = byEvent.remove(key) ?? <String, QueryRow>{};
    if (input.first != 'tagged-post-v1') {
      if (selected.isNotEmpty) throw const InvalidTagHistory();
      continue;
    }
    if (input.length != 3 ||
        input[1] is! List ||
        (input[1] as List).isEmpty ||
        !['posting-v1', 'posting-v2'].contains((input[1] as List).first) ||
        input[2] is! List)
      throw const InvalidTagHistory();
    final entries = input[2] as List;
    if (entries.isEmpty ||
        entries.length > 16 ||
        entries.length != selected.length)
      throw const InvalidTagHistory();
    String? prior;
    for (final entry in entries) {
      if (entry is! List ||
          entry.length != 2 ||
          entry[0] is! String ||
          entry[1] is! int)
        throw const InvalidTagHistory();
      final id = entry[0] as String;
      if ((prior != null && prior.compareTo(id) >= 0) ||
          selected.remove(id)?.read<int>('tag_version') != entry[1])
        throw const InvalidTagHistory();
      prior = id;
    }
  }
  if (byEvent.isNotEmpty) throw const InvalidTagHistory();
  return verified;
}
