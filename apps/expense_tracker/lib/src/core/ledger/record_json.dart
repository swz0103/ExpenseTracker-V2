import 'package:core/foundation_values.dart' show BusinessDate;
import 'package:domain/credit_cards.dart' show CardScheduleChange;
import 'package:flutter/painting.dart' show Color;

import 'records.dart';

// The ledger's records as JSON, as the journal keeps them and a backup
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

Map<String, Object?> categoryToJson(Category c) => {
  'name': c.name,
  'icon': c.icon,
  'color': c.color.toARGB32(),
  if (c.income) 'income': true,
  'parent': ?c.parent,
  if (c.archived) 'archived': true,
};

Category categoryFromJson(Map<String, Object?> json) => _read(
  () => Category(
    json['name']! as String,
    json['icon']! as String,
    Color(_int(json['color'])),
    income: json['income'] == true,
    parent: json['parent'] as String?,
    archived: json['archived'] == true,
  ),
);

/// [e] as JSON, every field the screens keep.
Map<String, Object?> entryToJson(Entry e) => {
  'id': e.id,
  'date': _day(e.date),
  'type': e.type.name,
  'amount': e.amount,
  'account': e.account,
  if (e.category.isNotEmpty) 'category': e.category,
  if (e.note.isNotEmpty) 'note': e.note,
  'to': ?e.to,
  'holding': ?e.holding,
  if (e.shares != 0) 'shares': e.shares,
  'recurring': ?e.recurring,
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
Entry entryFromJson(Map<String, Object?> json) => _read(
  () => Entry(
    id: json['id']! as String,
    date: _date(json['date']! as String),
    type: EntryType.values.byName(json['type']! as String),
    amount: _int(json['amount']),
    account: json['account']! as String,
    category: json['category'] as String? ?? '',
    note: json['note'] as String? ?? '',
    to: json['to'] as String?,
    holding: json['holding'] as String?,
    shares: _int(json['shares']),
    recurring: json['recurring'] as String?,
    merchant: json['merchant'] as String? ?? '',
    tags: [for (final t in json['tags'] as List? ?? const []) t! as String],
    parts: [
      for (final p in json['parts'] as List? ?? const [])
        if (p case {'name': final String name, 'amount': final int amount})
          (name, amount)
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
  ),
);

Map<String, Object?> budgetToJson(Budget b) => {
  'category': b.category,
  'limit': b.limit,
  if (b.warning != 80) 'warning': b.warning,
  if (b.carry) 'carry': true,
  if (b.since case final since?) 'since': _day(since),
};

Budget budgetFromJson(Map<String, Object?> json) => _read(
  () => Budget(
    json['category']! as String,
    _int(json['limit']),
    warning: _maybe(json['warning']) ?? 80,
    carry: json['carry'] == true,
    since: switch (json['since']) {
      final String day => _date(day),
      _ => null,
    },
  ),
);

Map<String, Object?> recurringToJson(Recurring r) => {
  'id': r.id,
  'name': r.name,
  'amount': r.amount,
  'day': r.day,
  'account': r.account,
  'category': r.category,
  if (!r.active) 'active': false,
  if (r.unit != RepeatUnit.month) 'unit': r.unit.name,
  if (r.every != 1) 'every': r.every,
  if (r.start case final start?) 'start': _day(start),
  if (r.end case final end?) 'end': _day(end),
  if (r.income) 'income': true,
  if (r.merchant.isNotEmpty) 'merchant': r.merchant,
};

Recurring recurringFromJson(Map<String, Object?> json) => _read(
  () => Recurring(
    id: json['id']! as String,
    name: json['name']! as String,
    amount: _int(json['amount']),
    day: _int(json['day']),
    account: json['account']! as String,
    category: json['category']! as String,
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
  ),
);

Map<String, Object?> trashedToJson(Trashed t) => {
  'on': _day(t.on),
  'entry': entryToJson(t.entry),
};

Trashed trashedFromJson(Map<String, Object?> json) => _read(
  () => Trashed(
    entryFromJson(json['entry']! as Map<String, Object?>),
    _date(json['on']! as String),
  ),
);

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
