import 'dart:convert';

import 'package:core/time/calendar_day.dart';
import 'package:core/fx/dated_figures.dart'
    show DatedFigures, FoundOn, MarketHistory;
import 'package:domain/investments.dart' show takesFetched;

import 'row_decoding.dart' show decodeBodies;

/// How the row of the rates and closes of one day is named among the
/// market rows (D58): this, then the day, `day:2026-03-09`.
const marketDayPrefix = 'day:';

/// The row id of [day]'s rates and closes.
String marketDayId(BusinessDate day) => '$marketDayPrefix$day';

/// The day a market row of [id] keeps the rates and closes of; null for
/// any other row (the latest closes, the latest board). Throws a
/// [FormatException] for a day row whose day cannot be read.
BusinessDate? marketDayOf(String id) => id.startsWith(marketDayPrefix)
    ? BusinessDate.parse(id.substring(marketDayPrefix.length))
    : null;

/// The three dated tables of a market history, as a day row names them.
enum MarketSeries {
  /// 臺灣銀行's spot buying rate, by currency.
  buying('rates'),

  /// Its spot selling rate, by currency (D59).
  selling('sell'),

  /// Each stock's close, by code.
  closes('closes');

  const MarketSeries(this.field);

  /// Its field in a day row.
  final String field;

  DatedFigures of(MarketHistory history) => switch (this) {
    buying => history.buying,
    selling => history.selling,
    closes => history.closes,
  };
}

/// The field of a day row naming, by code, the later day each of its
/// closes was fetched on (D123); left out for closes fetched on the day
/// or the next, as no split can fall between.
const fetchedField = 'fetched';

/// What one day row holds: each series' figures by key, and the later
/// day each close was fetched on, by code (D123).
typedef DayFigures = ({
  Map<MarketSeries, Map<String, double>> figures,
  Map<String, BusinessDate> fetched,
});

/// The figures of the day row [body]. Throws a [FormatException] for a
/// row that cannot be read.
DayFigures dayFiguresOf(String body) {
  final json = jsonDecode(body);
  if (json is! Map<String, Object?>) throw const FormatException('day');
  final on = json[fetchedField] ?? const <String, Object?>{};
  if (on is! Map<String, Object?>) throw const FormatException(fetchedField);
  final fetched = <String, BusinessDate>{};
  for (final MapEntry(:key, :value) in on.entries) {
    if (value is! String) throw const FormatException(fetchedField);
    fetched[key] = BusinessDate.parse(value);
  }
  final figures = <MarketSeries, Map<String, double>>{};
  for (final series in MarketSeries.values) {
    final part = json[series.field] ?? const <String, Object?>{};
    if (part is! Map<String, Object?>) throw FormatException(series.field);
    final kept = figures[series] = <String, double>{};
    for (final MapEntry(:key, :value) in part.entries) {
      if (value is! num || !value.isFinite || value <= 0) {
        throw FormatException(series.field);
      }
      kept[key] = value.toDouble();
    }
  }
  return (figures: figures, fetched: fetched);
}

/// The history kept in the day rows [bodies], by day. Throws a
/// [FormatException] for a row that cannot be read.
MarketHistory historyFrom(Map<BusinessDate, String> bodies) => historyOf({
  for (final MapEntry(key: day, value: body) in bodies.entries)
    day: dayFiguresOf(body),
});

/// The history of the day rows read as [days].
MarketHistory historyOf(Map<BusinessDate, DayFigures> days) {
  final tables = {
    for (final series in MarketSeries.values)
      series: <String, Map<BusinessDate, double>>{},
  };
  final fetched = <String, Map<BusinessDate, BusinessDate>>{};
  for (final MapEntry(key: day, value: row) in days.entries) {
    for (final MapEntry(:key, :value) in row.fetched.entries) {
      (fetched[key] ??= {})[day] = value;
    }
    for (final MapEntry(key: series, value: figures) in row.figures.entries) {
      final table = tables[series]!;
      for (final MapEntry(:key, :value) in figures.entries) {
        (table[key] ??= {})[day] = value;
      }
    }
  }
  return _history(tables, fetched);
}

/// How many days before today the day rows are kept each by itself
/// (review 39): a month ended longer ago is folded into one row
/// ([foldedDays]), so the table grows by twelve rows a year, not 365.
const marketDaysKeptWhole = 400;

/// The day rows to write (a body) and to take away (null), by id, so
/// that each month of [days] ended more than [marketDaysKeptWhole] days
/// before [today] is one row on its first day (review 39). It holds,
/// for each currency and code, the month's last figure taken, which
/// stands for every day of the month as an earlier day's (D58), within
/// `doubtfulMoveKeptDays` of each (D123). A close is kept with the day
/// after its own as the day it was fetched on at the latest, so it stays
/// a price of the shares of its own day ([MarketHistory.closeFetchedOn]).
/// A month already one row on its first day is left.
Map<String, String?> foldedDays(
  Map<BusinessDate, DayFigures> days,
  BusinessDate today,
) {
  final cutoff = today.addDays(-marketDaysKeptWhole);
  final months = <BusinessDate, List<BusinessDate>>{};
  for (final day in days.keys) {
    final first = BusinessDate(day.year, day.month, 1);
    final next = day.month == 12
        ? BusinessDate(day.year + 1, 1, 1)
        : BusinessDate(day.year, day.month + 1, 1);
    if (!next.isAfter(cutoff)) (months[first] ??= []).add(day);
  }
  final changes = <String, String?>{};
  for (final MapEntry(key: first, value: kept) in months.entries) {
    if (kept.length == 1 && kept.single == first) continue;
    kept.sort();
    final figures = {
      for (final series in MarketSeries.values) series: <String, double>{},
    };
    final fetched = <String, String>{};
    for (final day in kept) {
      final row = days[day]!;
      for (final MapEntry(key: series, value: of) in row.figures.entries) {
        for (final MapEntry(:key, :value) in of.entries) {
          figures[series]![key] = value;
          if (series != MarketSeries.closes) continue;
          final on = row.fetched[key] ?? (day == first ? null : day.addDays(1));
          if (on != null && on.isAfter(first.addDays(1))) {
            fetched[key] = '$on';
          } else {
            fetched.remove(key);
          }
        }
      }
      if (day != first) changes[marketDayId(day)] = null;
    }
    changes[marketDayId(first)] = jsonEncode({
      for (final series in MarketSeries.values)
        if (figures[series]!.isNotEmpty) series.field: figures[series],
      if (fetched.isNotEmpty) fetchedField: fetched,
    });
  }
  return changes;
}

MarketHistory _history(
  Map<MarketSeries, Map<String, Map<BusinessDate, double>>> tables,
  Map<String, Map<BusinessDate, BusinessDate>> fetched,
) => MarketHistory(
  buying: DatedFigures(tables[MarketSeries.buying] ?? const {}),
  selling: DatedFigures(tables[MarketSeries.selling] ?? const {}),
  closes: DatedFigures(tables[MarketSeries.closes] ?? const {}),
  closesFetched: {
    for (final MapEntry(:key, :value) in fetched.entries) key: {...value},
  },
);

/// What a fetch adds to [history] (D58), and the day rows it rewrites.
final class MarketDayWrites {
  MarketDayWrites(MarketHistory history)
    : _tables = {
        for (final series in MarketSeries.values)
          series: series.of(history).figures,
      },
      _fetched = {
        for (final MapEntry(:key, :value) in history.closesFetched.entries)
          key: {...value},
      };

  final Map<MarketSeries, Map<String, Map<BusinessDate, double>>> _tables;
  final Map<String, Map<BusinessDate, BusinessDate>> _fetched;
  final _touched = <BusinessDate>{};

  /// The history with what was kept.
  MarketHistory get history => _history(_tables, _fetched);

  /// Keeps [figure], taken from a fetch, for [key] on [day]. [kept] is
  /// the figure it replaces as the latest, of the day [keptOn]: a book
  /// kept before D58 has it only in its latest row, so it is kept for its
  /// day first. A figure the days kept already give for its day (that
  /// day's, as first fetched, or an earlier day's unchanged, fetched
  /// alike) is not kept again. A close [fetchedOn] a day more than one after [day] is kept
  /// with that day (D123): fetched after a split, it is a price of the
  /// shares since.
  void keep(
    MarketSeries series,
    String key,
    BusinessDate day,
    double figure, {
    double? kept,
    BusinessDate? keptOn,
    BusinessDate? fetchedOn,
  }) {
    if (kept != null && keptOn != null && keptOn.isBefore(day)) {
      _add(series, key, keptOn, kept);
    }
    _add(series, key, day, figure, fetchedOn: fetchedOn);
  }

  /// Keeps [figure] for [key] on [day] unless the days kept already give
  /// it; whether it was kept.
  bool _add(
    MarketSeries series,
    String key,
    BusinessDate day,
    double figure, {
    BusinessDate? fetchedOn,
  }) {
    if (!figure.isFinite || figure <= 0) return false;
    // Only a fetch day a split could fall between it and [day] on: one
    // dated after the close's day and before the fetch's.
    final later =
        series == MarketSeries.closes &&
            fetchedOn != null &&
            fetchedOn.isAfter(day.addDays(1))
        ? fetchedOn
        : null;
    final table = _tables[series]!;
    final found = DatedFigures({key: ?table[key]}).on(key, day);
    if (found != null &&
        found.found != FoundOn.today &&
        found.figure == figure &&
        // The day's own stands, as first fetched; an earlier day's only
        // when fetched alike, or of no known fetch day.
        (found.found == FoundOn.theDay ||
            fetchedOn == null ||
            _fetched[key]?[found.of] == later)) {
      return false;
    }
    (table[key] ??= {})[day] = figure;
    if (later != null) {
      (_fetched[key] ??= {})[day] = later;
    } else {
      _fetched[key]?.remove(day);
    }
    _touched.add(day);
    return true;
  }

  /// Keeps the closes of [code] a month report gave ([closes], fetched
  /// on [fetchedOn]) for the days before [before] none is kept for (N3),
  /// the oldest first, each only if taken by the doubt rules (D95, D101)
  /// against the close kept for the nearest earlier day (the earliest
  /// kept, for a day before it), as a daily fetch is weighed; a day after which the book holds a split or
  /// reduction ([reshapedBy] not null) is left, as whether the report
  /// gives it in the shares of before or after is not known. How many
  /// were kept.
  int fillPastCloses(
    String code,
    Iterable<(BusinessDate, double)> closes, {
    required BusinessDate before,
    required BusinessDate fetchedOn,
    required double? Function(DateTime day) reshapedBy,
  }) {
    final table = _tables[MarketSeries.closes]!;
    final sorted = [
      for (final c in closes)
        if (c.$1.isBefore(before)) c,
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    var kept = 0;
    for (final (day, close) in sorted) {
      if (table[code]?[day] != null) continue;
      if (reshapedBy(day.asUtcMidnight) != null) continue;
      final series = table[code] ?? const <BusinessDate, double>{};
      final found = DatedFigures({code: series}).on(code, day);
      final BusinessDate? of = switch (found?.found) {
        null => null,
        FoundOn.theDay || FoundOn.earlierDay => found!.of,
        // None before it: the earliest kept, after it.
        _ => series.keys.reduce((a, b) => a.isBefore(b) ? a : b),
      };
      final fetched = of == null ? null : _fetched[code]?[of];
      if (!takesFetched(
        kept: of == null ? null : series[of],
        fetched: close,
        keptDaysAgo: of?.daysUntil(day).abs(),
        reshapedBy: of == null
            ? null
            : reshapedBy((fetched?.addDays(-1) ?? of).asUtcMidnight),
      )) {
        continue;
      }
      if (_add(MarketSeries.closes, code, day, close, fetchedOn: fetchedOn)) {
        kept++;
      }
    }
    return kept;
  }

  /// The day rows to write: each day something was kept for, with all
  /// that day holds.
  Map<String, String> get rows => {
    for (final day in _touched) marketDayId(day): _body(day),
  };

  /// [rows], each laid over the row kept now ([stored], by id): the
  /// fields of the [owned] series (with the closes, their fetch days)
  /// as this writes them, the rest as kept. A fetch whose read went
  /// before another fetch's write keeps what that one wrote (review 39:
  /// the closes and the board of a day share its row). A row kept that
  /// cannot be read is written over.
  Map<String, String> rowsOver(
    String? Function(String id) stored,
    Set<MarketSeries> owned,
  ) {
    final fields = {
      for (final series in owned) series.field,
      if (owned.contains(MarketSeries.closes)) fetchedField,
    };
    return {
      for (final day in _touched)
        marketDayId(day): switch (_stored(stored(marketDayId(day)))) {
          null => _body(day),
          final kept => jsonEncode({
            for (final MapEntry(:key, :value) in kept.entries)
              if (!fields.contains(key)) key: value,
            for (final MapEntry(:key, :value) in _json(day).entries)
              if (fields.contains(key)) key: value,
          }),
        },
    };
  }

  static Map<String, Object?>? _stored(String? body) => switch (body) {
    null => null,
    final body => switch (decodeBodies([body]).values.single) {
      final Map<String, Object?> json => json,
      _ => null,
    },
  };

  String _body(BusinessDate day) => jsonEncode(_json(day));

  Map<String, Object> _json(BusinessDate day) => {
    for (final series in MarketSeries.values)
      if (_onDay(series, day) case final figures when figures.isNotEmpty)
        series.field: figures,
    if (_fetchedOnDay(day) case final fetched when fetched.isNotEmpty)
      fetchedField: fetched,
  };

  Map<String, String> _fetchedOnDay(BusinessDate day) => {
    for (final MapEntry(:key, :value) in _fetched.entries)
      if (value[day] case final on?) key: '$on',
  };

  Map<String, double> _onDay(MarketSeries series, BusinessDate day) => {
    for (final MapEntry(:key, :value) in _tables[series]!.entries)
      key: ?value[day],
  };
}

/// The dated rates and closes of a book (D58): its day rows' [history],
/// with the latest board ([rates], [sellRates], of [ratesOn]) and closes
/// ([prices], each of its day in [days]) on their days where the rows do
/// not already give them, as for a book kept before D58, whose only days
/// are those.
MarketHistory datedMarket({
  required MarketHistory history,
  required Map<String, double> rates,
  required Map<String, double> sellRates,
  required DateTime? ratesOn,
  required Map<String, double> prices,
  required Map<String, DateTime> days,
}) {
  final writes = MarketDayWrites(history);
  void latest(MarketSeries series, Map<String, double> figures, DateTime? on) {
    if (on == null) return;
    for (final MapEntry(:key, :value) in figures.entries) {
      writes.keep(series, key, BusinessDate.of(on), value);
    }
  }

  latest(MarketSeries.buying, rates, ratesOn);
  latest(MarketSeries.selling, sellRates, ratesOn);
  for (final MapEntry(:key, :value) in prices.entries) {
    latest(MarketSeries.closes, {key: value}, days[key]);
  }
  return writes.history;
}
