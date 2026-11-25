// The market rows of a book: the latest closes and board, and the day
// rows of the dated table (D58), read, checked and folded.
import 'dart:convert';

import 'package:core/time/calendar_day.dart';
import 'package:domain/investments.dart' show DoubtedFigure;
import 'package:core/fx/dated_figures.dart' show MarketHistory;
import 'package:storage/storage.dart';

import '../models/models.dart';
import 'codec/market_days.dart';

import 'package:core/time/utc_days.dart';

/// The shelf of the closes and board last fetched.
const marketShelf = 'market';

/// The closes and board last fetched, from the [marketShelf] rows.
typedef Market = ({
  Map<String, double> prices,
  Map<String, double> moves,
  Map<String, String> names,
  Map<String, DateTime> days,
  DateTime? quotedOn,
  Map<String, double> rates,
  Map<String, double> sellRates,
  Map<String, DoubtedFigure> doubtedCloses,
  Map<String, DoubtedFigure> doubtedRates,
  Map<String, DoubtedFigure> doubtedSellRates,
  DateTime? ratesOn,
  MarketHistory history,
});

/// The closes and board last fetched, from [rows] of [marketShelf].
/// Throws for a row that cannot be read.
Market marketFrom(List<StoredRow> rows) => _marketFrom(rows, {});

/// The closes and board last fetched, from [rows] of [marketShelf], each
/// row read once: one that cannot be read is left out, [report] told
/// what reading it threw (a close or rate kept that cannot be read is
/// fetched again). Without [history], the day rows are not read at all,
/// for a reader that needs only the latest figures (review 39: they are
/// most of the rows).
Market readMarket(
  List<StoredRow>? rows, {
  void Function(Object error) report = _unreported,
  bool history = true,
}) {
  final latest = <StoredRow>[];
  final days = <BusinessDate, DayFigures>{};
  for (final row in rows ?? const <StoredRow>[]) {
    if (row.id.startsWith(marketDayPrefix)) {
      if (!history) continue;
      try {
        days[marketDayOf(row.id)!] = dayFiguresOf(row.body);
      } on Object catch (error) {
        // Told to [report]: a day that cannot be read is fetched again.
        report(error);
      }
      continue;
    }
    try {
      marketFrom([row]);
      latest.add(row);
    } on Object catch (error) {
      // Told to [report]: a row that cannot be read is left out.
      report(error);
    }
  }
  return _marketFrom(latest, days);
}

Market _marketFrom(
  List<StoredRow> rows,
  Map<BusinessDate, DayFigures> dayRows,
) {
  final prices = <String, double>{};
  final moves = <String, double>{};
  final names = <String, String>{};
  final days = <String, DateTime>{};
  final rates = <String, double>{};
  final sellRates = <String, double>{};
  final doubtedCloses = <String, DoubtedFigure>{};
  final doubtedRates = <String, DoubtedFigure>{};
  final doubtedSellRates = <String, DoubtedFigure>{};
  DateTime? quotedOn;
  DateTime? ratesOn;
  Map<String, Object?> part(Map<String, Object?> json, String key) =>
      json[key] as Map<String, Object?>? ?? const {};
  // What the last fetch doubted (D101), kept beside the figures, each
  // with its day under [field]`On`; a row kept before has none. A doubt
  // kept with no day (before review 25) is read as too old to weigh.
  void doubted(
    Map<String, Object?> json,
    String field,
    Map<String, DoubtedFigure> to,
  ) {
    final days = part(json, '${field}On');
    for (final MapEntry(:key, :value) in part(json, field).entries) {
      if (value is! num) throw FormatException(field);
      if (days[key] case final String on) {
        if (DateTime.tryParse(on) case final d?) {
          to[key] = (figure: value.toDouble(), day: dayOf(d));
        }
      }
    }
  }

  for (final row in rows) {
    // A day's rates and closes (D58), read below.
    if (marketDayOf(row.id) case final day?) {
      dayRows[day] = dayFiguresOf(row.body);
      continue;
    }
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
        for (final MapEntry(:key, :value) in part(json, 'days').entries) {
          days[key] = DateTime.parse(value! as String);
        }
        if (json['on'] case final String on) quotedOn = DateTime.parse(on);
        doubted(json, 'doubted', doubtedCloses);
      case 'rates':
        for (final MapEntry(:key, :value) in part(json, 'rates').entries) {
          rates[key] = (value! as num).toDouble();
        }
        // The selling rates, kept since D59; a board kept before has none.
        for (final MapEntry(:key, :value) in part(json, 'sell').entries) {
          if (value is! num) throw const FormatException('sell');
          sellRates[key] = value.toDouble();
        }
        doubted(json, 'doubted', doubtedRates);
        doubted(json, 'doubtedSell', doubtedSellRates);
        // The board's day: what a rate doubted is weighed by (D101); a
        // day that cannot be read only leaves it unknown.
        if (json['asOf'] case final String on) {
          if (DateTime.tryParse(on) case final d?) {
            ratesOn = dayOf(d);
          }
        }
    }
  }
  return (
    prices: prices,
    moves: moves,
    names: names,
    days: days,
    quotedOn: quotedOn,
    rates: rates,
    sellRates: sellRates,
    doubtedCloses: doubtedCloses,
    doubtedRates: doubtedRates,
    doubtedSellRates: doubtedSellRates,
    ratesOn: ratesOn,
    history: historyOf(dayRows),
  );
}

void _unreported(Object error) {}

/// The market [rows] with the months ended more than
/// [marketDaysKeptWhole] days before [today] folded into one day row
/// each (`foldedDays`, review 39), and the changes to keep that so; a
/// day row that cannot be read is left as it is, [report] told why.
({List<StoredRow> rows, List<RowChange> changes}) foldedMarket(
  List<StoredRow>? rows,
  BusinessDate today, {
  void Function(Object error) report = _unreported,
}) {
  final all = rows ?? const <StoredRow>[];
  final before = today.addDays(-marketDaysKeptWhole);
  final old = <BusinessDate, DayFigures>{};
  for (final row in all) {
    if (!row.id.startsWith(marketDayPrefix)) continue;
    try {
      final day = marketDayOf(row.id)!;
      if (day.isBefore(before)) old[day] = dayFiguresOf(row.body);
    } on Object catch (error) {
      // Told to [report]: a row that cannot be read is left out.
      report(error);
    }
  }
  final folded = foldedDays(old, today);
  if (folded.isEmpty) return (rows: all, changes: const []);
  return (
    rows: [
      for (final row in all)
        if (!folded.containsKey(row.id)) row,
      for (final MapEntry(key: id, value: body) in folded.entries)
        if (body != null) StoredRow(0, marketShelf, id, body),
    ],
    changes: [
      for (final MapEntry(key: id, value: body) in folded.entries)
        body == null
            ? RowChange.drop(marketShelf, id)
            : RowChange.put(marketShelf, id, body),
    ],
  );
}

/// A reference price and name for each stock with a kept close: the
/// holdings a book starts from.
List<Holding> holdingsOf(Market market) => [
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
