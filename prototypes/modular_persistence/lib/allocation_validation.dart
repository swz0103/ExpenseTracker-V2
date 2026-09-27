import 'package:categories/categories.dart';
import 'package:drift/drift.dart';
import 'package:foundation_values/foundation_values.dart';

import 'categories_adapter.dart';
import 'database.dart';

/// Verify each selection at its recorded metadata boundary, not today's state.
/// A single history replay serves all events; no per-event history rescans.
Future<Set<(String, String)>> validateAllocationHistory(
  ProbeDatabase db,
) async {
  if (!db.categoryReferences) throw const InvalidCategoryHistory();
  final pending = <(String, int), List<QueryRow>>{};
  final rows = await db.customSelect('''SELECT a.*,e.kind
    FROM allocations a LEFT JOIN events e
    ON e.workspace=a.workspace AND e.id=a.event_id''').get();
  final eventSequences = <(String, String), int>{};
  for (final row in rows) {
    final ws = row.read<String>('workspace');
    final sequence = row.read<int>('category_sequence');
    final event = (ws, row.read<String>('event_id'));
    if (sequence < 1 ||
        row.read<int>('category_version') < 1 ||
        ![
          'income',
          'expense',
          if (db.refundsAware) 'refund',
        ].contains(row.readNullable<String>('kind')) ||
        (eventSequences.containsKey(event) &&
            eventSequences[event] != sequence)) {
      throw const InvalidCategoryHistory();
    }
    eventSequences[event] = sequence;
    (pending[(ws, sequence)] ??= []).add(row);
  }
  final verified = await validateCategoryHistory(
    db,
    visit: (ws, sequence, state) {
      for (final row in pending.remove((ws, sequence)) ?? <QueryRow>[]) {
        state.requireSelection(
          workspace: WorkspaceId.parse(ws),
          id: PublicId.parse(row.read<String>('category_id')),
          expectedVersion: row.read<int>('category_version'),
          kind: row.read<String>('kind') == 'refund'
              ? CategoryKind.expense
              : CategoryKind.values.byName(row.read<String>('kind')),
        );
      }
    },
  );
  if (pending.isNotEmpty) throw const InvalidCategoryHistory();
  return verified;
}
