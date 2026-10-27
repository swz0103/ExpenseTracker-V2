import 'dart:convert';

import 'package:core/app_core.dart';
import 'package:core/foundation_values.dart';
import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/painting.dart' show Color;
import 'package:market/market_data.dart';
import 'package:storage/storage.dart';

import 'journal.dart';
import 'ledger.dart';
import 'record_json.dart';
import '../perf.dart';

/// The categories a new ledger starts with, with their marks and colours.
const _starters = [
  ('居家生活', 'home', 0xFF5C9A83, false),
  ('飲食日常', 'food', 0xFFD08B5B, false),
  ('交通通勤', 'travel', 0xFF5B8DB0, false),
  ('購物休閒', 'bag', 0xFF8E7CC0, false),
  ('訂閱服務', 'subscription', 0xFFC9A34A, false),
  ('其他支出', 'other', 0xFFB07A8C, false),
  ('薪資收入', 'salary', 0xFF2F7A65, true),
  ('股息收入', 'dividend', 0xFF5A6FA8, true),
  ('其他收入', 'income', 0xFF4E8A9A, true),
];

/// How long a deleted entry is kept to be restored.
const _keptInTrash = Duration(days: 30);

/// The shelf of the last closing prices and rate board, kept so holdings
/// and foreign accounts are valued offline.
const _market = 'market';

/// The book kept in the encrypted ledger: each of the screens' records a
/// row of JSON, written as the [Ledger] hands over each change.
final class TableJournal implements Journal {
  TableJournal(
    this._store, {
    Clock clock = const SystemClock(),
    MarketDataGateway? market,
  }) : _clock = clock,
       _gateway = market;

  final RowStore _store;
  final Clock _clock;

  /// Where closing prices and rates come from; none in tests.
  final MarketDataGateway? _gateway;

  DateTime _today() {
    final day = _clock.today();
    return DateTime.utc(day.year, day.month, day.day);
  }

  @override
  Future<Ledger> load() => Perf.instance.timeLoad(() async {
    try {
      return _load();
    } on StateError catch (error) {
      throw JournalFailure(error);
    }
  });

  Ledger _load() {
    _start();
    final shelves = <String, List<StoredRow>>{};
    for (final row in _store.rows()) {
      (shelves[row.shelf] ??= []).add(row);
    }
    List<T> read<T>(Shelf shelf, T Function(Map<String, Object?>) from) => [
      for (final row in shelves[shelf.name] ?? const <StoredRow>[])
        from(jsonDecode(row.body) as Map<String, Object?>),
    ];
    final market = _marketFrom(shelves[_market] ?? const []);
    final today = _today();
    final trash = read(Shelf.trash, trashedFromJson);
    final from = today.subtract(_keptInTrash);
    final expired = [
      for (final t in trash)
        if (t.on.isBefore(from)) t.entry.id,
    ];
    if (expired.isNotEmpty) {
      _store.write((w) {
        for (final id in expired) {
          w
            ..drop(Shelf.trash.name, id)
            ..drop(Shelf.receipt.name, id);
        }
      });
    }
    return Ledger(
      today: today,
      clock: _today,
      accounts: read(Shelf.account, accountFromJson),
      categories: read(Shelf.category, categoryFromJson),
      entries: read(Shelf.entry, entryFromJson),
      holdings: _holdingsOf(market),
      budgets: read(Shelf.budget, budgetFromJson),
      recurring: read(Shelf.recurring, recurringFromJson),
      rates: market.rates,
      moves: market.moves,
      quotedOn: market.quotedOn,
      trash: [
        for (final t in trash.reversed)
          if (!t.on.isBefore(from)) t,
      ],
      receipts: {
        for (final row in shelves[Shelf.receipt.name] ?? const <StoredRow>[])
          row.id: row.body,
      },
      journal: this,
    );
  }

  /// Gives a ledger that has none its first categories, and a cash and a
  /// bank account, so the first entry can be written at once.
  void _start() {
    final noCategories = _store.rows(shelf: Shelf.category.name).isEmpty;
    final noAccounts = _store.rows(shelf: Shelf.account.name).isEmpty;
    if (!noCategories && !noAccounts) return;
    _write(
      Batch(
        categories: [
          if (noCategories)
            for (final (name, icon, color, income) in _starters)
              Category(name, icon, Color(color), income: income),
        ],
        accounts: [
          if (noAccounts) ...[
            Account(PublicId.generate().value, '現金', AccountKind.cash, 0),
            Account(PublicId.generate().value, '銀行帳戶', AccountKind.bank, 0),
          ],
        ],
      ),
    );
  }

  @override
  Future<void> keep(Batch batch) async {
    try {
      _write(batch);
    } on Object catch (error) {
      throw JournalFailure(error);
    }
  }

  void _write(Batch batch) {
    String text(Map<String, Object?> json) => jsonEncode(json);
    _store.write((w) {
      for (final a in batch.accounts) {
        w.put(Shelf.account.name, a.id, text(accountToJson(a)));
      }
      for (final c in batch.categories) {
        w.put(Shelf.category.name, c.name, text(categoryToJson(c)));
      }
      for (final e in batch.entries) {
        w.put(Shelf.entry.name, e.id, text(entryToJson(e)));
      }
      for (final b in batch.budgets) {
        w.put(Shelf.budget.name, b.category, text(budgetToJson(b)));
      }
      for (final r in batch.recurring) {
        w.put(Shelf.recurring.name, r.id, text(recurringToJson(r)));
      }
      for (final t in batch.trash) {
        w.put(Shelf.trash.name, t.entry.id, text(trashedToJson(t)));
      }
      for (final MapEntry(key: id, value: file) in batch.receipts.entries) {
        if (file == null) {
          w.drop(Shelf.receipt.name, id);
        } else {
          w.put(Shelf.receipt.name, id, file);
        }
      }
      for (final (shelf, id) in batch.dropped) {
        w.drop(shelf.name, id);
      }
    });
  }

  /// Throws a [FormatException] for a record this app cannot read, so a
  /// backup with one is refused rather than restored.
  static void check(String shelf, String id, String body) {
    if (shelf == Shelf.receipt.name) {
      if (!RegExp(r'^[\w.-]+$').hasMatch(body)) {
        throw const FormatException('receipt');
      }
      return;
    }
    final Map<String, Object?> json;
    try {
      json = jsonDecode(body) as Map<String, Object?>;
    } on Object {
      throw FormatException('Unreadable $shelf');
    }
    if (shelf == _market) {
      if (id != 'quotes' && id != 'rates') throw FormatException(id);
      _marketFrom([StoredRow(0, shelf, id, body)]);
      return;
    }
    final reader = switch (Shelf.values.asNameMap()[shelf]) {
      Shelf.account => accountFromJson,
      Shelf.category => categoryFromJson,
      Shelf.entry => entryFromJson,
      Shelf.budget => budgetFromJson,
      Shelf.recurring => recurringFromJson,
      Shelf.trash => trashedFromJson,
      _ => throw FormatException('Unknown shelf $shelf'),
    };
    reader(json);
  }

  // Market data.

  /// The closes and board last fetched, for [Ledger.setMarket].
  ({
    List<Holding> holdings,
    Map<String, double> moves,
    Map<String, double> rates,
    DateTime? quotedOn,
  })
  market() {
    final kept = _marketFrom(_store.rows(shelf: _market));
    return (
      holdings: _holdingsOf(kept),
      moves: kept.moves,
      rates: kept.rates,
      quotedOn: kept.quotedOn,
    );
  }

  /// Fetches 臺灣銀行's board: the spot buying rate of each currency, what
  /// a foreign balance is worth in NT$. Returns whether any rate changed.
  Future<bool> refreshRates() async {
    final gateway = _gateway;
    if (gateway == null) return false;
    final board = (await gateway.bankRates()).value;
    if (board == null) return false;
    final fetched = <String, double>{};
    for (final MapEntry(key: code, value: row) in board.rates.entries) {
      final rate = row.valuation;
      if (rate != null) fetched[code] = rate.numerator / rate.denominator;
    }
    final kept = _marketFrom(_store.rows(shelf: _market));
    if (fetched.isEmpty || mapEquals(fetched, kept.rates)) return false;
    // Fetched, not changed by the person: no new backup is due for it.
    _store.write(
      (w) => w.put(
        _market,
        'rates',
        jsonEncode({'asOf': '${board.asOf}', 'rates': fetched}),
      ),
      counts: false,
    );
    return true;
  }

  /// Fetches the latest close of each of [codes], for the holdings' value;
  /// one not found on TWSE is tried on TPEx. Returns whether any price
  /// changed.
  Future<bool> refreshQuotes(Iterable<String> codes) async {
    final gateway = _gateway;
    if (gateway == null) return false;
    final kept = _marketFrom(_store.rows(shelf: _market));
    final prices = {...kept.prices};
    final moves = {...kept.moves};
    final names = {...kept.names};
    var quotedOn = kept.quotedOn;
    var changed = false;
    for (final code in codes) {
      try {
        var result = await gateway.stockClose(Listing(code));
        if (result.state == MarketState.missing) {
          result = await gateway.stockClose(Listing(code, market: 'TPEX'));
        }
        final close = result.value;
        final price = close == null
            ? null
            : double.tryParse(close.decimalPrice);
        if (close == null || price == null) continue;
        final day = DateTime.utc(
          close.asOf.year,
          close.asOf.month,
          close.asOf.day,
        );
        if (quotedOn == null || day.isAfter(quotedOn)) {
          quotedOn = day;
          changed = true;
        }
        final move = double.tryParse(close.decimalChange ?? '');
        final name = close.name;
        if (prices[code] == price &&
            moves[code] == move &&
            (name == null || names[code] == name)) {
          continue;
        }
        prices[code] = price;
        if (move == null) {
          moves.remove(code);
        } else {
          moves[code] = move;
        }
        if (name != null) names[code] = name;
        changed = true;
      } on Object {
        continue;
      }
    }
    if (changed) {
      _store.write(
        (w) => w.put(
          _market,
          'quotes',
          jsonEncode({
            'prices': prices,
            'moves': moves,
            'names': names,
            'on': ?quotedOn?.toIso8601String(),
          }),
        ),
        counts: false,
      );
    }
    return changed;
  }
}

typedef _Market = ({
  Map<String, double> prices,
  Map<String, double> moves,
  Map<String, String> names,
  DateTime? quotedOn,
  Map<String, double> rates,
});

/// The closes and board last fetched, from the [_market] shelf.
_Market _marketFrom(List<StoredRow> rows) {
  final prices = <String, double>{};
  final moves = <String, double>{};
  final names = <String, String>{};
  final rates = <String, double>{};
  DateTime? quotedOn;
  Map<String, Object?> part(Map<String, Object?> json, String key) =>
      json[key] as Map<String, Object?>? ?? const {};
  for (final row in rows) {
    final json = jsonDecode(row.body) as Map<String, Object?>;
    switch (row.id) {
      case 'quotes':
        for (final MapEntry(:key, :value) in part(json, 'prices').entries) {
          prices[key] = (value! as num).toDouble();
        }
        for (final MapEntry(:key, :value) in part(json, 'moves').entries) {
          moves[key] = (value! as num).toDouble();
        }
        for (final MapEntry(:key, :value) in part(json, 'names').entries) {
          names[key] = value! as String;
        }
        if (json['on'] case final String on) quotedOn = DateTime.parse(on);
      case 'rates':
        for (final MapEntry(:key, :value) in part(json, 'rates').entries) {
          rates[key] = (value! as num).toDouble();
        }
    }
  }
  return (
    prices: prices,
    moves: moves,
    names: names,
    quotedOn: quotedOn,
    rates: rates,
  );
}

/// A reference price and name for each stock with a kept close.
List<Holding> _holdingsOf(_Market market) => [
  for (final MapEntry(key: code, value: price) in market.prices.entries)
    Holding(
      code,
      market.names[code] ?? code,
      shares: 0,
      price: price,
      cost: 0,
      change: 0,
    ),
];
