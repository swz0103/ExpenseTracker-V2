import 'package:core/foundation_values.dart' show BusinessDate;
import 'package:domain/credit_cards.dart' show CardScheduleChange;
import 'package:ledger_trade_costs/calc/broker_discount.dart'
    show BrokerDiscountRange;

import '../../models/models.dart';
import 'category_refs.dart';
import 'same_values.dart';

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
  'brokerDiscount': ?a.brokerDiscount,
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
    payFrom: _text(json, 'payFrom'),
  );
  return terms.isEmpty ? null : terms;
}

/// An account's own broker discount; null when none is kept, or when
/// what is kept is no discount a fee is charged at, which then takes the
/// phone-wide one (a book of a later version, or a damaged one).
int? _discount(Object? value) => switch (_maybe(value)) {
  final int points when BrokerDiscountRange.holds(points) => points,
  _ => null,
};

Account accountFromJson(Map<String, Object?> json) => _read(
  () => Account(
    _need(json, 'id'),
    _need(json, 'name'),
    AccountKind.values.byName(_need(json, 'kind')),
    _int(json['opening']),
    currency: _text(json, 'currency') ?? homeCode,
    icon: _text(json, 'icon'),
    closingDay: _maybe(json['closingDay']),
    dueDay: _maybe(json['dueDay']),
    limit: _maybe(json['limit']),
    archived: json['archived'] == true,
    inNetWorth: json['inNetWorth'] != false,
    principal: _maybe(json['principal']),
    place: _maybe(json['place']),
    color: _maybe(json['color']),
    loan: _loanTerms(json),
    brokerDiscount: _discount(json['brokerDiscount']),
    closes: {
      for (final MapEntry(:key, :value)
          in (_object(json, 'closes') ?? const {}).entries)
        _date(key): _date(_words(value)),
    },
    history: [
      for (final h in _list(json, 'history') ?? const [])
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
        _need(json, 'name'),
        _need(json, 'icon'),
        _int(json['color']),
        id: _text(json, 'id'),
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
  if (e.dayTrade) 'dayTrade': true,
  'home': ?e.home,
  'received': ?e.received,
  'group': ?e.group,
  'mark': ?e.mark?.name,
};

/// The entry [entryToJson] wrote.
/// An entry from its record. With [same], the values entries repeat
/// (accounts, categories kept by name, merchants, stocks, tags, days) are
/// shared with the entries read before through it ([SameValues]), as the
/// book opens.
Entry entryFromJson(
  Map<String, Object?> json, [
  CategoryRefs? refs,
  SameValues? same,
]) => _read(
  () => Entry(
    id: _need(json, 'id'),
    date: switch (_need(json, 'date')) {
      final day when same != null => same.day(day, _date),
      final day => _date(day),
    },
    type: EntryType.values.byName(_need(json, 'type')),
    amount: _int(json['amount']),
    account: _same(same, _need(json, 'account')),
    category: _same(same, _refName(json, 'category', refs) ?? ''),
    note: _text(json, 'note') ?? '',
    to: _sameOrNone(same, _text(json, 'to')),
    holding: _sameOrNone(same, _text(json, 'holding')),
    shares: _int(json['shares']),
    recurring: _sameOrNone(same, _text(json, 'recurring')),
    merchant: _same(same, _text(json, 'merchant') ?? ''),
    // None shares one empty list: a book's every entry comes through
    // here, most with neither, and each list made is one more object kept
    // and handed from the worker the book is read on.
    tags: switch (_list(json, 'tags')) {
      null => const [],
      final tags => [for (final t in tags) _same(same, t! as String)],
    },
    parts: switch (_list(json, 'parts')) {
      null => const [],
      final parts => [
        for (final p in parts)
          if (p case {'amount': final int amount}
              when p is Map<String, Object?>)
            (
              _refName(p, 'name', refs, idKey: 'categoryId') ??
                  (throw const FormatException('parts')),
              amount,
            )
          else
            throw const FormatException('parts'),
      ],
    },
    fee: _int(json['fee']),
    tax: _int(json['tax']),
    refundOf: _text(json, 'refundOf'),
    installments: _int(json['installments']),
    average: json['average'] == true,
    split: json['split'] == true,
    // Only a sale is a day trade: an older version that kept the field
    // of a sale it changed into something else left it behind.
    dayTrade: json['dayTrade'] == true && json['type'] == EntryType.sell.name,
    home: _maybe(json['home']),
    received: _maybe(json['received']),
    group: _text(json, 'group'),
    // A mark a later version knows and this one does not reads as none.
    mark: _marks[json['mark']],
  ),
);

/// Each entry mark by its name, looked up once (not a map made for each
/// entry read).
final _marks = EntryMark.values.asNameMap();

String _same(SameValues? same, String text) =>
    same == null ? text : same.text(text);

String? _sameOrNone(SameValues? same, String? text) =>
    text == null || same == null ? text : same.text(text);

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
  if (r.openFrom case final from?) 'openFrom': _day(from),
};

Recurring recurringFromJson(Map<String, Object?> json, [CategoryRefs? refs]) =>
    _read(
      () => Recurring(
        id: _need(json, 'id'),
        name: _need(json, 'name'),
        amount: _int(json['amount']),
        day: _int(json['day']),
        account: _need(json, 'account'),
        category: _refName(json, 'category', refs)!,
        active: json['active'] != false,
        unit: RepeatUnit.values.byName(_text(json, 'unit') ?? 'month'),
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
        merchant: _text(json, 'merchant') ?? '',
        auto: json['auto'] == true,
        skipped: {
          for (final day in _list(json, 'skipped') ?? const [])
            _date(_words(day)),
        },
        openFrom: switch (json['openFrom']) {
          final String day => _date(day),
          _ => null,
        },
      ),
    );

Map<String, Object?> trashedToJson(Trashed t, [CategoryRefs? refs]) => {
  'on': _day(t.on),
  'entry': entryToJson(t.entry, refs),
  if (t.letGo case final day?) 'letGo': _day(day),
};

Trashed trashedFromJson(
  Map<String, Object?> json, [
  CategoryRefs? refs,
  SameValues? same,
]) => _read(
  () => Trashed(
    entryFromJson(_needObject(json, 'entry'), refs, same),
    _date(_need(json, 'on')),
    letGo: switch (json['letGo']) {
      final String day => _date(day),
      _ => null,
    },
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
  return _text(json, key);
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

// Each field read as its type, a slip named by its field. Written out for
// each type rather than through JsonFields' generic need: a book's every
// record comes through here, and the generic check cost a fifth more.

String _need(Map<String, Object?> json, String key) => switch (json[key]) {
  final String value => value,
  final other => throw _slip(key, 'words', other),
};

String? _text(Map<String, Object?> json, String key) => switch (json[key]) {
  null => null,
  final String value => value,
  final other => throw _slip(key, 'words', other),
};

Map<String, Object?> _needObject(Map<String, Object?> json, String key) =>
    switch (json[key]) {
      final Map<String, Object?> value => value,
      final other => throw _slip(key, 'an object', other),
    };

Map<String, Object?>? _object(Map<String, Object?> json, String key) =>
    switch (json[key]) {
      null => null,
      final Map<String, Object?> value => value,
      final other => throw _slip(key, 'an object', other),
    };

List<Object?>? _list(Map<String, Object?> json, String key) =>
    switch (json[key]) {
      null => null,
      final List<Object?> value => value,
      final other => throw _slip(key, 'a list', other),
    };

FormatException _slip(String key, String expected, Object? found) =>
    FormatException(
      '$key: expected $expected, found ${found?.runtimeType ?? 'nothing'}',
    );

String _words(Object? value) => switch (value) {
  final String words => words,
  _ => throw const FormatException('Expected words'),
};

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
