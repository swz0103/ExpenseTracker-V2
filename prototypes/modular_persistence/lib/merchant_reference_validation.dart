import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:foundation_values/foundation_values.dart';

import 'database.dart';
import 'merchants_adapter.dart';

/// Verify metadata at posting time, then bind exact original IDs/versions to
/// the same receipt as the financial event. A merge never rewrites those IDs.
Future<Set<(String, String)>> validateMerchantReferences(
  ProbeDatabase db,
) async {
  if (!db.merchantsAware) throw const InvalidMerchantHistory();
  final pending = <(String, int), List<QueryRow>>{};
  final byEvent = <(String, String), Map<String, QueryRow>>{};
  final sequences = <(String, String), int>{};
  final rows = await db.customSelect(
    '''SELECT t.*,e.kind FROM event_merchants t LEFT JOIN events e
    ON e.workspace=t.workspace AND e.id=t.event_id''',
  ).get();
  for (final row in rows) {
    final ws = row.read<String>('workspace'),
        event = row.read<String>('event_id'),
        merchant = row.read<String>('merchant_id');
    final key = (ws, event), sequence = row.read<int>('merchant_sequence');
    final selected = byEvent[key] ??= {};
    if (sequence < 1 ||
        row.read<int>('merchant_version') < 1 ||
        !['income', 'expense'].contains(row.readNullable<String>('kind')) ||
        (sequences.containsKey(key) && sequences[key] != sequence) ||
        selected.containsKey(merchant)) {
      throw const InvalidMerchantHistory();
    }
    sequences[key] = sequence;
    selected[merchant] = row;
    (pending[(ws, sequence)] ??= []).add(row);
  }
  final verified = await validateMerchantHistory(
    db,
    visit: (ws, sequence, state) {
      for (final row in pending.remove((ws, sequence)) ?? <QueryRow>[]) {
        state.requireSelection(
          workspace: WorkspaceId.parse(ws),
          id: PublicId.parse(row.read<String>('merchant_id')),
          expectedVersion: row.read<int>('merchant_version'),
        );
      }
    },
  );
  if (pending.isNotEmpty) throw const InvalidMerchantHistory();
  for (final receipt in await db.customSelect('SELECT * FROM receipts').get()) {
    final input = jsonDecode(receipt.read<String>('input'));
    if (input is! List || input.isEmpty) throw const InvalidMerchantHistory();
    final key = (
      receipt.read<String>('workspace'),
      receipt.read<String>('result_id'),
    );
    // Metadata commands may share a public ID with a different module.
    if (input.first == 'merchant-v1' ||
        input.first == 'category-v1' ||
        input.first == 'tag-v1' ||
        input.first == 'archive-v1')
      continue;
    final selected = byEvent.remove(key) ?? <String, QueryRow>{};
    if (input.first != 'merchant-post-v1') {
      if (selected.isNotEmpty) throw const InvalidMerchantHistory();
      continue;
    }
    if (input.length != 3 ||
        input[1] is! List ||
        (input[1] as List).isEmpty ||
        ![
          'posting-v1',
          'posting-v2',
          'tagged-post-v1',
        ].contains((input[1] as List).first) ||
        input[2] is! List)
      throw const InvalidMerchantHistory();
    final entries = input[2] as List;
    if (entries.isEmpty ||
        entries.length != 1 ||
        entries.length != selected.length)
      throw const InvalidMerchantHistory();
    String? prior;
    for (final entry in entries) {
      if (entry is! List ||
          entry.length != 2 ||
          entry[0] is! String ||
          entry[1] is! int)
        throw const InvalidMerchantHistory();
      final id = entry[0] as String;
      if ((prior != null && prior.compareTo(id) >= 0) ||
          selected.remove(id)?.read<int>('merchant_version') != entry[1])
        throw const InvalidMerchantHistory();
      prior = id;
    }
  }
  if (byEvent.isNotEmpty) throw const InvalidMerchantHistory();
  return verified;
}
