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

/// The closes and board last fetched, from [rows] of [marketShelf]: each
/// day row read once, each of the few latest rows (the closes, the
/// board) read alone to be checked, then with the others; one that
/// cannot be read is left out, [report] told what reading it threw (a
/// close or rate kept that cannot be read is fetched again). Without [history], the day rows are not read at all,
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
/// each (`foldedDays`, review 39); the changes to keep that so; and the
/// day rows they were worked out from (`from`, body by id), whose month
/// a change names, to check the changes against the rows kept when they
/// are written ([foldStillApplies]). Only a month not yet one row on its
/// first day is read, so once folded an opening reads none (PERF-4); a
/// day row that cannot be read is left as it is, [report] told why.
({List<StoredRow> rows, List<RowChange> changes, Map<String, String> from})
foldedMarket(
  List<StoredRow>? rows,
  BusinessDate today, {
  void Function(Object error) report = _unreported,
}) {
  final all = rows ?? const <StoredRow>[];
  final months = _foldedMonths(all, today, report);
  if (months.isEmpty) return (rows: all, changes: const [], from: const {});
  final old = <BusinessDate, DayFigures>{};
  final from = <String, String>{};
  for (final MapEntry(value: kept) in months.entries) {
    for (final (day, row) in kept) {
      try {
        old[day] = dayFiguresOf(row.body);
        from[row.id] = row.body;
      } on Object catch (error) {
        // Told to [report]: a row that cannot be read is left out.
        report(error);
      }
    }
  }
  final folded = foldedDays(old, today);
  if (folded.isEmpty) return (rows: all, changes: const [], from: const {});
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
    from: from,
  );
}

/// Whether the changes [foldedMarket] worked out from the day rows
/// [from] still fold the market [rows] kept now: every day row of the
/// months they name is as it was, none added or taken away since. A
/// change of those months in between (a month report's closes, a
/// restore) leaves the fold to the next opening.
bool foldStillApplies(Map<String, String> from, List<StoredRow> rows) {
  final months = {for (final id in from.keys) _monthOf(id)};
  var seen = 0;
  for (final row in rows) {
    if (!row.id.startsWith(marketDayPrefix)) continue;
    if (!months.contains(_monthOf(row.id))) continue;
    if (from[row.id] != row.body) return false;
    seen++;
  }
  return seen == from.length;
}

/// The month of the day row [id] (`day:2026-01-15` → `day:2026-01`);
/// an id too short to name one, as it is.
String _monthOf(String id) {
  const length = marketDayPrefix.length + 7;
  return id.length < length ? id : id.substring(0, length);
}

/// The day rows of [rows] by the first day of their month, for each
/// month ended more than [marketDaysKeptWhole] days before [today] that
/// is not one row on its first day already; told only by the rows' ids,
/// none of their bodies read.
Map<BusinessDate, List<(BusinessDate, StoredRow)>> _foldedMonths(
  List<StoredRow> rows,
  BusinessDate today,
  void Function(Object error) report,
) {
  final cutoff = today.addDays(-marketDaysKeptWhole);
  final months = <BusinessDate, List<(BusinessDate, StoredRow)>>{};
  for (final row in rows) {
    if (!row.id.startsWith(marketDayPrefix)) continue;
    final BusinessDate day;
    try {
      day = marketDayOf(row.id)!;
    } on Object catch (error) {
      // Told to [report]: a row that cannot be read is left out.
      report(error);
      continue;
    }
    final first = BusinessDate(day.year, day.month, 1);
    final next = day.month == 12
        ? BusinessDate(day.year + 1, 1, 1)
        : BusinessDate(day.year, day.month + 1, 1);
    if (!next.isAfter(cutoff)) (months[first] ??= []).add((day, row));
  }
  months.removeWhere(
    (first, kept) => kept.length == 1 && kept.single.$1 == first,
  );
  return months;
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
