part of 'snapshot.dart';

/// Linear pass over immutable source references and per-source remaining budgets.
Future<Map<(String, String), String>> _validateRefundHistory(
  ProbeDatabase db,
  List<QueryRow> events,
  Map<(String, String), Map<String, QueryRow>> allocations,
) async {
  final byId = {
    for (final e in events)
      (e.read<String>('workspace'), e.read<String>('id')): e,
  };
  final links = <(String, String), String>{};
  final budgets = <(String, String), RefundBudget>{};
  final metadata = <String, Map<(String, String), List<String>>>{};
  for (final table in ['event_tags', 'event_merchants']) {
    final column = table == 'event_tags' ? 'tag' : 'merchant';
    final grouped = <(String, String), List<String>>{};
    for (final r
        in await db
            .customSelect('SELECT * FROM $table ORDER BY ${column}_id')
            .get()) {
      (grouped[(r.read<String>('workspace'), r.read<String>('event_id'))] ??=
              [])
          .add(
            jsonEncode([
              r.read<String>('${column}_id'),
              r.read<int>('${column}_version'),
              r.read<int>('${column}_sequence'),
            ]),
          );
    }
    metadata[table] = grouped;
  }
  for (final link
      in await db
          .customSelect(
            'SELECT * FROM event_refunds ORDER BY workspace,event_id',
          )
          .get()) {
    final ws = link.read<String>('workspace'),
        id = link.read<String>('event_id'),
        original = link.read<String>('original_id');
    final key = (ws, id), sourceKey = (ws, original);
    final event = byId[key], source = byId[sourceKey];
    if (event == null ||
        source == null ||
        event.read<String>('kind') != 'refund' ||
        source.read<String>('kind') != 'expense' ||
        id == original ||
        links.containsKey(key)) {
      throw const InvalidSnapshot();
    }
    final currency = Currency(
      source.read<String>('currency'),
      source.read<int>('scale'),
    );
    if (Currency(event.read<String>('currency'), event.read<int>('scale')) !=
        currency) {
      throw const InvalidSnapshot();
    }
    List<Allocation> items((String, String) k) => [
      for (final a in (allocations[k] ?? {}).values)
        Allocation(
          PublicId.parse(a.read<String>('category_id')),
          Money(currency, BigInt.from(a.read<int>('amount'))),
          expectedCategoryVersion: a.read<int>('category_version'),
        ),
    ];
    var budget =
        budgets[sourceKey] ??
        RefundBudget(
          originalId: PublicId.parse(original),
          originalDate: BusinessDate.parse(
            source.read<String>('business_date'),
          ),
          amount: Money(currency, BigInt.from(source.read<int>('expense'))),
          allocations: items(sourceKey),
        );
    for (final row in (allocations[key] ?? {}).values) {
      final prior = allocations[sourceKey]?[row.read<String>('category_id')];
      if (prior == null ||
          prior.read<int>('category_version') !=
              row.read<int>('category_version') ||
          prior.read<int>('category_sequence') !=
              row.read<int>('category_sequence')) {
        throw const InvalidSnapshot();
      }
    }
    budget = budget.consume(
      amount: Money(currency, -BigInt.from(event.read<int>('expense'))),
      date: BusinessDate.parse(event.read<String>('business_date')),
      allocations: items(key),
    );
    budgets[sourceKey] = budget;
    for (final table in metadata.values) {
      if (jsonEncode(table[key] ?? []) != jsonEncode(table[sourceKey] ?? [])) {
        throw const InvalidSnapshot();
      }
    }
    links[key] = original;
  }
  if (events.where((e) => e.read<String>('kind') == 'refund').length !=
      links.length) {
    throw const InvalidSnapshot();
  }
  return links;
}
