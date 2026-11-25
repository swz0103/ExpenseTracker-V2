import '../time/calendar_day.dart';
import '../time/month_arithmetic.dart' show monthIndex;

/// Which day a figure asked for on a day was found on (D58): the one
/// rule for a day's exchange rate or close.
enum FoundOn {
  /// A figure kept for that very day.
  theDay,

  /// None kept for the day: the nearest earlier day's, as a board or a
  /// close stands until the next one (a weekend, a holiday, a day the app
  /// was not opened).
  earlierDay,

  /// None kept for the day or any day before it: today's, the latest
  /// kept, standing in for a day no figure is known of.
  today,
}

/// A figure found for a day ([DatedFigures.on]): what it is, the day it
/// is of (null for a today's figure of no known day) and by which rule
/// it was found.
typedef FigureOn = ({double figure, BusinessDate? of, FoundOn found});

/// Figures kept by key and day: exchange rates by currency, closes by
/// code (D58). Each day's figure is the one taken from that day's fetch
/// (D95, D101: a doubted one is never kept for its day). Unchanged once
/// made.
final class DatedFigures {
  DatedFigures([Map<String, Map<BusinessDate, double>> figures = const {}])
    : _byKey = {
        for (final MapEntry(:key, :value) in figures.entries)
          if (value.isNotEmpty) key: _Series(value),
      };

  final Map<String, _Series> _byKey;

  /// Whether no figure is kept at all.
  bool get isEmpty => _byKey.isEmpty;

  /// The figures kept, by key and day.
  Map<String, Map<BusinessDate, double>> get figures => {
    for (final MapEntry(:key, :value) in _byKey.entries)
      key: {for (final (i, day) in value.days.indexed) day: value.figures[i]},
  };

  /// The latest day a figure of [key] is kept for; null when none is.
  BusinessDate? latestOf(String key) => _byKey[key]?.days.last;

  /// The figure of [key] kept for exactly [day]; null when none is.
  double? exactly(String key, BusinessDate day) {
    final series = _byKey[key];
    if (series == null) return null;
    final i = series.atOrBefore(day);
    return i >= 0 && series.days[i] == day ? series.figures[i] : null;
  }

  /// The figure of [key] for [day], by the one rule ([FoundOn]): the
  /// day's own, else the nearest earlier day's, else [today] (of the day
  /// [todayOf], when known), else the latest kept. Null when there is
  /// none of any.
  FigureOn? on(
    String key,
    BusinessDate day, {
    double? today,
    BusinessDate? todayOf,
  }) {
    final series = _byKey[key];
    if (series != null) {
      final i = series.atOrBefore(day);
      if (i >= 0) {
        final of = series.days[i];
        return (
          figure: series.figures[i],
          of: of,
          found: of == day ? FoundOn.theDay : FoundOn.earlierDay,
        );
      }
    }
    if (today != null) {
      return (figure: today, of: todayOf, found: FoundOn.today);
    }
    if (series == null) return null;
    return (
      figure: series.figures.last,
      of: series.days.last,
      found: FoundOn.today,
    );
  }

  /// These figures with [figure] kept for [key] on [day], in place of
  /// any kept for that day.
  DatedFigures withFigure(String key, BusinessDate day, double figure) {
    final all = figures;
    return DatedFigures({
      ...all,
      key: {...?all[key], day: figure},
    });
  }
}

/// One key's figures, oldest day first, with each day's number for
/// finding a day quickly.
final class _Series {
  factory _Series(Map<BusinessDate, double> byDay) {
    final days = byDay.keys.toList()..sort((a, b) => _number(a) - _number(b));
    return _Series._(
      days,
      [for (final day in days) byDay[day]!],
      [for (final day in days) _number(day)],
    );
  }

  _Series._(this.days, this.figures, this._numbers);

  final List<BusinessDate> days;
  final List<double> figures;
  final List<int> _numbers;

  static int _number(BusinessDate day) =>
      monthIndex(day.year, day.month) * 31 + day.day - 1;

  /// The place of the latest day not after [day]; -1 when every day is.
  int atOrBefore(BusinessDate day) {
    final n = _number(day);
    var low = 0;
    var high = _numbers.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (_numbers[mid] <= n) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low - 1;
  }
}

/// The dated rates and closes (D58): 臺灣銀行's spot [buying] and
/// [selling] rate of each currency (D59) and each stock's [closes], each
/// by the day the board or close is for.
final class MarketHistory {
  MarketHistory({
    DatedFigures? buying,
    DatedFigures? selling,
    DatedFigures? closes,
  }) : buying = buying ?? DatedFigures(),
       selling = selling ?? DatedFigures(),
       closes = closes ?? DatedFigures();

  final DatedFigures buying;
  final DatedFigures selling;
  final DatedFigures closes;

  /// Whether nothing is kept.
  bool get isEmpty => buying.isEmpty && selling.isEmpty && closes.isEmpty;
}
