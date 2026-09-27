part of 'snapshot.dart';

Future<Map<(String, String), ({String original, String reason})>>
_validateReversalHistory(ProbeDatabase db, List<QueryRow> events) async {
  final byId = {
    for (final e in events)
      (e.read<String>('workspace'), e.read<String>('id')): e,
  };
  final grouped = <String, Map<(String, String), List<Map<String, dynamic>>>>{};
  for (final table in [
    'legs',
    'allocations',
    'event_tags',
    'event_merchants',
    'event_fx',
  ]) {
    final map = <(String, String), List<Map<String, dynamic>>>{};
    for (final r in await db.customSelect('SELECT * FROM $table').get()) {
      (map[(r.read<String>('workspace'), r.read<String>('event_id'))] ??= [])
          .add({
            for (final k in r.data.keys.where(
              (k) => k != 'workspace' && k != 'event_id',
            ))
              k: r.data[k],
          });
    }
    grouped[table] = map;
  }
  String canonical(List<Map<String, dynamic>> rows) => jsonEncode(
    rows.map((r) {
      final keys = r.keys.toList()..sort();
      return jsonEncode({for (final k in keys) k: r[k]});
    }).toList()..sort(),
  );
  final refunded = {
    for (final r
        in await db
            .customSelect('SELECT workspace,original_id FROM event_refunds')
            .get())
      (r.read<String>('workspace'), r.read<String>('original_id')),
  };
  final links = <(String, String), ({String original, String reason})>{};
  final sources = <(String, String)>{};
  for (final r
      in await db.customSelect('SELECT * FROM event_reversals').get()) {
    final ws = r.read<String>('workspace'),
        id = r.read<String>('event_id'),
        original = r.read<String>('original_id'),
        reason = r.read<String>('reason');
    final key = (ws, id), sourceKey = (ws, original);
    final e = byId[key], s = byId[sourceKey];
    if (e == null ||
        s == null ||
        e.read<String>('kind') != 'reversal' ||
        !['income', 'expense', 'transfer'].contains(s.read<String>('kind')) ||
        !sources.add(sourceKey) ||
        refunded.contains(sourceKey) ||
        id == original ||
        reason != reason.trim() ||
        reason.runes.length > 256 ||
        BusinessDate.parse(
              e.read<String>('business_date'),
            ).compareTo(BusinessDate.parse(s.read<String>('business_date'))) <
            0 ||
        e.read<String>('currency') != s.read<String>('currency') ||
        e.read<int>('scale') != s.read<int>('scale') ||
        BigInt.from(e.read<int>('income')) !=
            -BigInt.from(s.read<int>('income')) ||
        BigInt.from(e.read<int>('expense')) !=
            -BigInt.from(s.read<int>('expense'))) {
      throw const InvalidSnapshot();
    }
    for (final entry in grouped.entries) {
      final source = entry.value[sourceKey] ?? [];
      final expected = [
        for (final row in source)
          {
            ...row,
            if (entry.key == 'legs')
              'amount': -BigInt.from(row['amount'] as int).toInt(),
          },
      ];
      if (canonical(entry.value[key] ?? []) != canonical(expected))
        throw const InvalidSnapshot();
    }
    links[key] = (original: original, reason: reason);
  }
  if (events.where((e) => e.read<String>('kind') == 'reversal').length !=
      links.length)
    throw const InvalidSnapshot();
  return links;
}
