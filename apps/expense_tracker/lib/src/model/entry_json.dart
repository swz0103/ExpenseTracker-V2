import 'records.dart';

/// [e] as JSON, every field the screens keep but its recurring link, for
/// keeping a deleted entry until it is restored.
Map<String, Object?> entryToJson(Entry e) => {
  'id': e.id,
  'date': e.date.toIso8601String(),
  'type': e.type.name,
  'amount': e.amount,
  'account': e.account,
  if (e.category.isNotEmpty) 'category': e.category,
  if (e.note.isNotEmpty) 'note': e.note,
  'to': ?e.to,
  'holding': ?e.holding,
  if (e.shares != 0) 'shares': e.shares,
  if (e.merchant.isNotEmpty) 'merchant': e.merchant,
  if (e.tags.isNotEmpty) 'tags': e.tags,
  if (e.parts.isNotEmpty)
    'parts': [
      for (final (name, amount) in e.parts) {'name': name, 'amount': amount},
    ],
  if (e.fee != 0) 'fee': e.fee,
  if (e.tax != 0) 'tax': e.tax,
  'refundOf': ?e.refundOf,
  if (e.installments != 0) 'installments': e.installments,
  if (e.average) 'average': true,
  if (e.split) 'split': true,
  'home': ?e.home,
  'received': ?e.received,
};

/// The entry [entryToJson] wrote.
Entry entryFromJson(Map<String, Object?> json) {
  int count(String key) => (json[key] as num?)?.toInt() ?? 0;
  int? maybe(String key) => (json[key] as num?)?.toInt();
  return Entry(
    id: json['id']! as String,
    date: DateTime.parse(json['date']! as String),
    type: EntryType.values.byName(json['type']! as String),
    amount: count('amount'),
    account: json['account']! as String,
    category: json['category'] as String? ?? '',
    note: json['note'] as String? ?? '',
    to: json['to'] as String?,
    holding: json['holding'] as String?,
    shares: count('shares'),
    merchant: json['merchant'] as String? ?? '',
    tags: [for (final t in json['tags'] as List? ?? const []) t as String],
    parts: [
      for (final p in json['parts'] as List? ?? const [])
        if (p case {'name': final String name, 'amount': final num amount})
          (name, amount.toInt()),
    ],
    fee: count('fee'),
    tax: count('tax'),
    refundOf: json['refundOf'] as String?,
    installments: count('installments'),
    average: json['average'] == true,
    split: json['split'] == true,
    home: maybe('home'),
    received: maybe('received'),
  );
}
