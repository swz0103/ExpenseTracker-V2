import 'package:core/percent/percent.dart' show divideRounded;
import 'package:core/time/utc_days.dart' show monthsAfter, yearBefore;

import 'dart:math';

import '../../../core/ledger/ledger.dart';

/// The yearly rate at which [flows] (money in positive, money out
/// negative, by day) come to nothing: the money-weighted return, as
/// spreadsheets' XIRR gives it. Null when there is no such rate: flows of
/// one sign only, or fewer than two.
double? xirr(List<(DateTime, int)> flows) {
  if (flows.length < 2) return null;
  if (!flows.any((f) => f.$2 < 0) || !flows.any((f) => f.$2 > 0)) {
    return null;
  }
  final first = flows.map((f) => f.$1).reduce((a, b) => a.isBefore(b) ? a : b);
  double worth(double rate) {
    var sum = 0.0;
    for (final (day, amount) in flows) {
      final years = day.difference(first).inDays / 365;
      sum += amount / pow(1 + rate, years);
    }
    return sum;
  }

  // Halving between a loss of almost everything and a hundredfold gain:
  // slower than Newton's method, but it never runs off.
  var low = -0.9999;
  var high = 100.0;
  var atLow = worth(low);
  if (atLow.isNaN || atLow * worth(high) > 0) return null;
  for (var i = 0; i < 200 && high - low > 1e-10; i++) {
    final middle = (low + high) / 2;
    final atMiddle = worth(middle);
    if (atMiddle == 0) return middle;
    if (atMiddle * atLow < 0) {
      high = middle;
    } else {
      low = middle;
      atLow = atMiddle;
    }
  }
  return (low + high) / 2;
}

/// A dividend expected in `month`, from what `code` paid a year before.
typedef DividendGuess = ({
  String code,
  String name,
  DateTime month,
  int amount,
});

/// What was made on investments, from the entries, the holdings and the
/// trades of each, as of [today]: each answer worked out once, on the
/// first ask, and kept with this object. A [Returns] is for the book as it
/// was made; the screens take one kept until the entries, the market or
/// the day change (`returnsOf`), so a rebuild, as on 隱藏金額, works
/// nothing out again (review 32 1.1).
final class Returns {
  Returns({
    required this.entries,
    required this.holdings,
    required this.trades,
    required this.today,
  });

  final EntryReader entries;
  final HoldingReader holdings;
  final EntryQueryService trades;
  final DateTime today;

  /// Each rate asked for, by stock; under null, that of everything.
  final _rates = <String?, double?>{};

  /// Each stock's guesses, as [expectedDividends] lists them.
  final _guesses = <String, List<DividendGuess>>{};

  /// Each stock's months of [payingMonths].
  final _months = <String, List<int>>{};

  /// The yearly money-weighted return of [code], or of everything invested
  /// when null: every trade and dividend, and what is still held as if sold
  /// at today's close. Null when it cannot be worked out, as for shares
  /// held from before the book began (their buying day is not known).
  /// Only what counts [today] ([countsOn]): a trade an old book dated
  /// later joins on its day, as the holdings take it.
  double? rate({String? code}) =>
      _rates.containsKey(code) ? _rates[code] : (_rates[code] = _rate(code));

  double? _rate(String? code) {
    // The investments that count, in the order written: those of [code]
    // from its own list, those of every stock from the whole book.
    final invested = [
      for (final e in countedOn(
        code == null ? entries.all : trades.tradesInBookOrder(code),
        today,
      ))
        if (e.isInvestment) e,
    ];
    final codes = code == null ? {for (final e in invested) e.holding} : {code};
    for (final c in codes) {
      if (c == null) continue;
      if (holdings.lotsOf(c).any((l) => l.isOpening)) return null;
    }
    final flows = <(DateTime, int)>[
      for (final e in invested)
        if (codes.contains(e.holding))
          if (e.settlement case final cash when cash != 0) (e.date, cash),
    ];
    final held = [
      for (final h in holdings.all)
        if (codes.contains(h.code)) h.value,
    ].fold(0, (sum, v) => sum + v);
    if (held > 0) flows.add((today, held));
    return xirr(flows);
  }

  /// The shares of [code] held on the eve of [day]: those held now, less
  /// every change from [day] on that counts [today], as the holdings take
  /// them.
  int sharesBefore(String code, DateTime day) => _sharesBefore(
    code,
    countedOn(trades.tradesInBookOrder(code), today),
    day,
  );

  /// [sharesBefore], from [counted], the trades of [code] that count.
  int _sharesBefore(String code, Iterable<Entry> counted, DateTime day) {
    var shares = holdings.byCode(code)?.shares ?? 0;
    for (final e in counted) {
      if (e.date.isBefore(day)) continue;
      shares -= switch (e.type) {
        EntryType.buy => e.shares,
        EntryType.sell => -e.shares,
        EntryType.dividend => e.shares,
        _ => 0,
      };
    }
    return shares;
  }

  /// The cash dividends expected in the next twelve months: each one paid in
  /// the last twelve, per share then, times the shares held now, a year on.
  /// A guess from the book alone, not from what the companies announced.
  /// By month; those of one month in the order found (by stock as the
  /// holdings list them, each stock's newest first).
  late final List<DividendGuess> _expected = _byMonth([
    for (final h in holdings.all) ..._guessesOf(h),
  ]);

  List<DividendGuess> expectedDividends() => _expected;

  /// [found] by month, those of one month in the order found.
  static List<DividendGuess> _byMonth(List<DividendGuess> found) {
    final at = [for (var i = 0; i < found.length; i++) i]
      ..sort((a, b) {
        final byMonth = found[a].month.compareTo(found[b].month);
        return byMonth != 0 ? byMonth : a.compareTo(b);
      });
    return List.unmodifiable([for (final i in at) found[i]]);
  }

  /// What [h] is expected to pay, in the order its trades are listed
  /// (newest first): from its own trades alone, the shares held at each
  /// dividend worked out from the same few.
  List<DividendGuess> _guessesOf(Holding h) =>
      _guesses[h.code] ??= h.shares <= 0 ? const [] : _guessed(h);

  List<DividendGuess> _guessed(Holding h) {
    final since = yearBefore(today);
    final counted = countedOn(trades.tradesInBookOrder(h.code), today).toList();
    final found = <DividendGuess>[];
    for (final e in trades.tradesOf(h.code)) {
      if (e.type != EntryType.dividend || e.isReduction) continue;
      if (e.dividendNet <= 0 || !e.date.isAfter(since)) continue;
      final then = _sharesBefore(h.code, counted, e.date);
      if (then <= 0) continue;
      final next = DateTime.utc(e.date.year + 1, e.date.month);
      found.add((
        code: h.code,
        name: h.name,
        month: next,
        amount: divideRounded(e.dividendNet * h.shares, then),
      ));
    }
    return found;
  }

  /// The next dividend [code] is expected to pay, if any: its first in
  /// [expectedDividends], worked out from its own trades alone.
  DividendGuess? nextDividend(String code) {
    final held = holdings.byCode(code);
    if (held == null) return null;
    return _byMonth(_guessesOf(held)).firstOrNull;
  }

  /// The months [code] paid cash dividends in over the last two years, in
  /// order: 「1、4、7、10 月」; empty when none.
  List<int> payingMonths(String code) => _months[code] ??= () {
    final since = monthsAfter(today, -24);
    return List<int>.unmodifiable(
      {
        for (final e in trades.tradesInBookOrder(code))
          if (e.type == EntryType.dividend &&
              !e.isReduction &&
              e.dividendNet > 0 &&
              e.date.isAfter(since))
            e.date.month,
      }.toList()..sort(),
    );
  }();
}
