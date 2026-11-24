// The fields this version of the app reads of each kind of record, as
// record_json.dart writes them. A row can carry others: written by a later
// version, which added them without raising the record version since an
// earlier reader loses nothing by passing over them. They are kept as they
// are when the record is written again, so a record edited here does not
// lose what a later version put in it.

/// The fields read of each collection's records, by collection name;
/// `_v` and `_at`, the row's own version and time, are the data source's.
const recordFields = <String, Set<String>>{
  'account': {
    'id',
    'name',
    'kind',
    'opening',
    'currency',
    'icon',
    'closingDay',
    'dueDay',
    'limit',
    'archived',
    'inNetWorth',
    'principal',
    'place',
    'color',
    'rate',
    'months',
    'repay',
    'payFrom',
    'brokerDiscount',
    'closes',
    'history',
  },
  'category': {
    'id',
    'name',
    'icon',
    'color',
    'income',
    'parent',
    'parentId',
    'archived',
    'place',
  },
  'entry': {
    'id',
    'date',
    'type',
    'amount',
    'account',
    'category',
    'categoryId',
    'note',
    'to',
    'holding',
    'shares',
    'recurring',
    'merchant',
    'tags',
    'parts',
    'fee',
    'tax',
    'refundOf',
    'installments',
    'average',
    'split',
    'dayTrade',
    'home',
    'received',
    'group',
    'mark',
  },
  'budget': {'category', 'categoryId', 'limit', 'warning', 'carry', 'since'},
  'recurring': {
    'id',
    'name',
    'amount',
    'day',
    'account',
    'category',
    'categoryId',
    'active',
    'unit',
    'every',
    'start',
    'end',
    'income',
    'merchant',
    'auto',
    'skipped',
  },
  'trash': {'on', 'entry'},
};

/// The row's own fields, kept by the data source beside each record.
const _rowFields = {'_v', '_at'};

/// The fields of [json], a record of [collection], that this version does
/// not read; null when there are none, as for nearly every row.
Map<String, Object?>? unknownFields(
  String collection,
  Map<String, Object?> json,
) {
  final known = recordFields[collection];
  if (known == null) return null;
  Map<String, Object?>? unknown;
  // By key, not by entry: every record of a book comes through here.
  for (final key in json.keys) {
    if (known.contains(key) || _rowFields.contains(key)) continue;
    (unknown ??= {})[key] = json[key];
  }
  return unknown;
}
