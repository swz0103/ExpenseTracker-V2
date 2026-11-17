import 'package:core/foundation_values.dart' show BusinessDate;
import 'package:domain/credit_cards.dart' show CardScheduleChange;

import '../../models/models.dart';
import 'category_refs.dart';

// The ledger's records as JSON, as the data source keeps them and a backup
// carries them. Each reader takes what its writer wrote and fills in the
// defaults for what was left out; anything else is a FormatException.

Map<String, Object?> accountToJson(Account a) => {
  'id': a.id,
  'name': a.name,
  'kind': a.kind.name,
  'opening': a.opening,
  if (a.currency != homeCode) 'currency': a.currency,
  'icon': ?a.icon,
  'closingDay': ?a.closingDay,
  'dueDay': ?a.dueDay,
  'limit': ?a.limit,
  if (a.archived) 'archived': true,
  if (!a.inNetWorth) 'inNetWorth': false,
  'principal': ?a.principal,
  'place': ?a.place,
  'color': ?a.color,
  'rate': ?a.loan?.rate,
  'months': ?a.loan?.months,
  'repay': ?a.loan?.repay?.name,
  'payFrom': ?a.loan?.payFrom,
  if (a.closes.isNotEmpty)
    'closes': {
      for (final MapEntry(:key, :value) in a.closes.entries)
        _day(key): _day(value),
    },
  if (a.history.isNotEmpty)
    'history': [
      for (final h in a.history)
        {
          'until': h.until.toString(),
          'closingDay': h.closingDay,
          'dueDay': h.dueDay,
        },
    ],
};

/// A loan's terms, kept flat beside the account's other fields; null when
/// none is there.
LoanTerms? _loanTerms(Map<String, Object?> json) {
  final terms = LoanTerms(
    rate: _maybe(json['rate']),
    months: _maybe(json['months']),
    repay: switch (json['repay']) {
      final String name => LoanRepay.values.byName(name),
      _ => null,
    },
    payFrom: json['payFrom'] as String?,
  );
  return terms.isEmpty ? null : terms;
}

Account accountFromJson(Map<String, Object?> json) => _read(
  () => Account(
    json['id']! as String,
    json['name']! as String,
    AccountKind.values.byName(json['kind']! as String),
    _int(json['opening']),
    currency: json['currency'] as String? ?? homeCode,
    icon: json['icon'] as String?,
    closingDay: _maybe(json['closingDay']),
    dueDay: _maybe(json['dueDay']),
    limit: _maybe(json['limit']),
    archived: json['archived'] == true,
    inNetWorth: json['inNetWorth'] != false,
    principal: _maybe(json['principal']),
    place: _maybe(json['place']),
    color: _maybe(json['color']),
    loan: _loanTerms(json),
    closes: {
      for (final MapEntry(:key, :value)
          in (json['closes'] as Map<String, Object?>? ?? const {}).entries)
        _date(key): _date(value! as String),
    },
    history: [
      for (final h in json['history'] as List? ?? const [])
        if (h case {
          'until': final String until,
          'closingDay': final int closingDay,
          'dueDay': final int dueDay,
        })
          CardScheduleChange(
            until: BusinessDate.parse(until),
            closingDay: closingDay,
            dueDay: dueDay,
          )
        else
          throw const FormatException('history'),
    ],
  ),
);

/// [c] as JSON. With [refs] its parent is kept by id, so a parent renamed
/// leaves it as it is.
Map<String, Object?> categoryToJson(Category c, [CategoryRefs? refs]) => {
  'id': c.id,
  'name': c.name,
  'icon': c.icon,
  'color': c.color,
  if (c.income) 'income': true,
  ..._ref('parent', c.parent, refs),
  if (c.archived) 'archived': true,
  'place': ?c.place,
};

/// The category [categoryToJson] wrote; one kept before ids has none, and
/// is given one.
Category categoryFromJson(Map<String, Object?> json, [CategoryRefs? refs]) =>
    _read(
      () => Category(
        json['name']! as String,
        json['icon']! as String,
        _int(json['color']),
        id: json['id'] as String?,
        income: json['income'] == true,
        parent: _refName(json, 'parent', refs),
        archived: json['archived'] == true,
        place: _maybe(json['place']),
      ),
    );

/// [e] as JSON, every field the screens keep.
/// With [refs] the category and each part's category are kept by id, so a
/// category renamed leaves the entry as it is.
Map<String, Object?> entryToJson(Entry e, [CategoryRefs? refs]) => {
  'id': e.id,
  'date': _day(e.date),
  'type': e.type.name,
  'amount': e.amount,
  'account': e.account,
  if (e.category.isNotEmpty) ..._ref('category', e.category, refs),
  if (e.note.isNotEmpty) 'note': e.note,
  'to': ?e.to,
  'holding': ?e.holding,
  if (e.shares != 0) 'shares': e.shares,
  'recurring': ?e.recurring,
  if (e.merchant.isNotEmpty) 'merchant': e.merchant,
  if (e.tags.isNotEmpty) 'tags': e.tags,
  if (e.parts.isNotEmpty)
    'parts': [
      for (final (name, amount) in e.parts)
        {..._ref('name', name, refs, idKey: 'categoryId'), 'amount': amount},
    ],
  if (e.fee != 0) 'fee': e.fee,
  if (e.tax != 0) 'tax': e.tax,
  'refundOf': ?e.refundOf,
  if (e.installments != 0) 'installments': e.installments,
  if (e.average) 'average': true,
  if (e.split) 'split': true,
  'home': ?e.home,
  'received': ?e.received,
  'group': ?e.group,
};

/// The entry [entryToJson] wrote.
Entry entryFromJson(Map<String, Object?> json, [CategoryRefs? refs]) => _read(
  () => Entry(
    id: json['id']! as String,
    date: _date(json['date']! as String),
    type: EntryType.values.byName(json['type']! as String),
    amount: _int(json['amount']),
    account: json['account']! as String,
    category: _refName(json, 'category', refs) ?? '',
    note: json['note'] as String? ?? '',
    to: json['to'] as String?,
    holding: json['holding'] as String?,
    shares: _int(json['shares']),
    recurring: json['recurring'] as String?,
    merchant: json['merchant'] as String? ?? '',
    tags: [for (final t in json['tags'] as List? ?? const []) t! as String],
    parts: [
      for (final p in json['parts'] as List? ?? const [])
        if (p case {'amount': final int amount} when p is Map<String, Object?>)
          (
            _refName(p, 'name', refs, idKey: 'categoryId') ??
                (throw const FormatException('parts')),
            amount,
          )
        else
          throw const FormatException('parts'),
    ],
    fee: _int(json['fee']),
    tax: _int(json['tax']),
    refundOf: json['refundOf'] as String?,
    installments: _int(json['installments']),
    average: json['average'] == true,
    split: json['split'] == true,
    home: _maybe(json['home']),
    received: _maybe(json['received']),
    group: json['group'] as String?,
  ),
);

Map<String, Object?> budgetToJson(Budget b, [CategoryRefs? refs]) => {
  ..._ref('category', b.category, refs),
  'limit': b.limit,
  if (b.warning != 80) 'warning': b.warning,
  if (b.carry) 'carry': true,
  if (b.since case final since?) 'since': _day(since),
};

Budget budgetFromJson(Map<String, Object?> json, [CategoryRefs? refs]) => _read(
  () => Budget(
    _refName(json, 'category', refs)!,
    _int(json['limit']),
    warning: _maybe(json['warning']) ?? 80,
    carry: json['carry'] == true,
    since: switch (json['since']) {
      final String day => _date(day),
      _ => null,
    },
  ),
);

Map<String, Object?> recurringToJson(Recurring r, [CategoryRefs? refs]) => {
  'id': r.id,
  'name': r.name,
  'amount': r.amount,
  'day': r.day,
  'account': r.account,
  ..._ref('category', r.category, refs),
  if (!r.active) 'active': false,
  if (r.unit != RepeatUnit.month) 'unit': r.unit.name,
  if (r.every != 1) 'every': r.every,
  if (r.start case final start?) 'start': _day(start),
  if (r.end case final end?) 'end': _day(end),
  if (r.income) 'income': true,
  if (r.merchant.isNotEmpty) 'merchant': r.merchant,
  if (r.auto) 'auto': true,
  if (r.skipped.isNotEmpty)
    'skipped': [for (final d in r.skipped.toList()..sort()) _day(d)],
};

Recurring recurringFromJson(Map<String, Object?> json, [CategoryRefs? refs]) =>
    _read(
      () => Recurring(
        id: json['id']! as String,
        name: json['name']! as String,
        amount: _int(json['amount']),
        day: _int(json['day']),
        account: json['account']! as String,
        category: _refName(json, 'category', refs)!,
        active: json['active'] != false,
        unit: RepeatUnit.values.byName(json['unit'] as String? ?? 'month'),
        every: _maybe(json['every']) ?? 1,
        start: switch (json['start']) {
          final String day => _date(day),
          _ => null,
        },
        end: switch (json['end']) {
          final String day => _date(day),
          _ => null,
        },
        income: json['income'] == true,
        merchant: json['merchant'] as String? ?? '',
        auto: json['auto'] == true,
        skipped: {
          for (final day in json['skipped'] as List? ?? const [])
            _date(day as String),
        },
      ),
    );

Map<String, Object?> trashedToJson(Trashed t, [CategoryRefs? refs]) => {
  'on': _day(t.on),
  'entry': entryToJson(t.entry, refs),
};

Trashed trashedFromJson(Map<String, Object?> json, [CategoryRefs? refs]) =>
    _read(
      () => Trashed(
        entryFromJson(json['entry']! as Map<String, Object?>, refs),
        _date(json['on']! as String),
      ),
    );

/// A category named [name] as it is kept under [key]: by its id, under
/// `${key}Id` (or [idKey]), when [refs] knows it, else by the name.
Map<String, Object?> _ref(
  String key,
  String? name,
  CategoryRefs? refs, {
  String? idKey,
}) {
  if (name == null) return const {};
  final id = refs?.idOf(name);
  return id == null ? {key: name} : {idKey ?? '${key}Id': id};
}

/// The name of the category [json] keeps under [key], by id or by name.
String? _refName(
  Map<String, Object?> json,
  String key,
  CategoryRefs? refs, {
  String? idKey,
}) {
  final id = json[idKey ?? '${key}Id'];
  if (id is String) return refs?.nameOf(id) ?? id;
  return json[key] as String?;
}

/// [read], with any slip in the JSON's shape a [FormatException].
T _read<T>(T Function() read) {
  try {
    return read();
  } on FormatException {
    rethrow;
  } on Object catch (error) {
    throw FormatException('Unreadable record: ${error.runtimeType}');
  }
}

int _int(Object? value) => _maybe(value) ?? 0;

int? _maybe(Object? value) => switch (value) {
  null => null,
  final int n => n,
  _ => throw const FormatException('Expected a whole number'),
};

/// A day as `2026-10-21`: the screens keep days as UTC midnights.
String _day(DateTime d) => BusinessDate(d.year, d.month, d.day).toString();

DateTime _date(String text) {
  final day = BusinessDate.parse(text);
  return DateTime.utc(day.year, day.month, day.day);
}
