import 'dart:convert';

import 'package:core/time/calendar_day.dart';
import 'package:core/fx/dated_figures.dart'
    show DatedFigures, FoundOn, MarketHistory;

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

/// The history kept in the day rows [bodies], by day. Throws a
/// [FormatException] for a row that cannot be read.
MarketHistory historyFrom(Map<BusinessDate, String> bodies) {
  final tables = {
    for (final series in MarketSeries.values)
      series: <String, Map<BusinessDate, double>>{},
  };
  for (final MapEntry(key: day, value: body) in bodies.entries) {
    final json = jsonDecode(body);
    if (json is! Map<String, Object?>) throw const FormatException('day');
    for (final series in MarketSeries.values) {
      final part = json[series.field] ?? const <String, Object?>{};
      if (part is! Map<String, Object?>) {
        throw FormatException(series.field);
      }
      for (final MapEntry(:key, :value) in part.entries) {
        if (value is! num || !value.isFinite || value <= 0) {
          throw FormatException(series.field);
        }
        (tables[series]![key] ??= {})[day] = value.toDouble();
      }
    }
  }
  return _history(tables);
}

MarketHistory _history(
  Map<MarketSeries, Map<String, Map<BusinessDate, double>>> tables,
) => MarketHistory(
  buying: DatedFigures(tables[MarketSeries.buying] ?? const {}),
  selling: DatedFigures(tables[MarketSeries.selling] ?? const {}),
  closes: DatedFigures(tables[MarketSeries.closes] ?? const {}),
);

/// What a fetch adds to [history] (D58), and the day rows it rewrites.
final class MarketDayWrites {
  MarketDayWrites(MarketHistory history)
    : _tables = {
        for (final series in MarketSeries.values)
          series: series.of(history).figures,
      };

  final Map<MarketSeries, Map<String, Map<BusinessDate, double>>> _tables;
  final _touched = <BusinessDate>{};

  /// The history with what was kept.
  MarketHistory get history => _history(_tables);

  /// Keeps [figure], taken from a fetch, for [key] on [day]. [kept] is
  /// the figure it replaces as the latest, of the day [keptOn]: a book
  /// kept before D58 has it only in its latest row, so it is kept for its
  /// day first. A figure the days kept already give for its day (that
  /// day's, or an earlier day's unchanged) is not kept again.
  void keep(
    MarketSeries series,
    String key,
    BusinessDate day,
    double figure, {
    double? kept,
    BusinessDate? keptOn,
  }) {
    if (kept != null && keptOn != null && keptOn.isBefore(day)) {
      _add(series, key, keptOn, kept);
    }
    _add(series, key, day, figure);
  }

  void _add(MarketSeries series, String key, BusinessDate day, double figure) {
    if (!figure.isFinite || figure <= 0) return;
    final table = _tables[series]!;
    final found = DatedFigures({key: ?table[key]}).on(key, day);
    if (found != null &&
        found.found != FoundOn.today &&
        found.figure == figure) {
      return;
    }
    (table[key] ??= {})[day] = figure;
    _touched.add(day);
  }

  /// The day rows to write: each day something was kept for, with all
  /// that day holds.
  Map<String, String> get rows => {
    for (final day in _touched) marketDayId(day): _body(day),
  };

  String _body(BusinessDate day) => jsonEncode({
    for (final series in MarketSeries.values)
      if (_onDay(series, day) case final figures when figures.isNotEmpty)
        series.field: figures,
  });

  Map<String, double> _onDay(MarketSeries series, BusinessDate day) => {
    for (final MapEntry(:key, :value) in _tables[series]!.entries)
      key: ?value[day],
  };
}
