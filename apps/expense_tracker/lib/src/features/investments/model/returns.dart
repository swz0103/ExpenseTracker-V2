import 'package:core/percent/percent.dart' show divideRounded;

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
/// trades of each, as of [today].
final class Returns {
  const Returns({
    required this.entries,
    required this.holdings,
    required this.trades,
    required this.today,
  });

  final EntryReader entries;
  final HoldingReader holdings;
  final EntryQueryService trades;
  final DateTime today;

  /// The yearly money-weighted return of [code], or of everything invested
  /// when null: every trade and dividend, and what is still held as if sold
  /// at today's close. Null when it cannot be worked out, as for shares
  /// held from before the book began (their buying day is not known).
  /// Only what counts [today] ([countsOn]): a trade an old book dated
  /// later joins on its day, as the holdings take it.
  double? rate({String? code}) {
    final codes = code == null
        ? {
            for (final e in countedOn(entries.all, today))
              if (e.isInvestment) e.holding,
          }
        : {code};
    for (final c in codes) {
      if (c == null) continue;
      if (holdings.lotsOf(c).any((l) => l.isOpening)) return null;
    }
    final flows = <(DateTime, int)>[
      for (final e in countedOn(entries.all, today))
        if (e.isInvestment && codes.contains(e.holding))
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
  int sharesBefore(String code, DateTime day) {
    var shares = holdings.byCode(code)?.shares ?? 0;
    for (final e in countedOn(trades.tradesOf(code), today)) {
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
  List<DividendGuess> expectedDividends() {
    final since = DateTime.utc(today.year - 1, today.month, today.day);
    final found = <DividendGuess>[];
    for (final h in holdings.all) {
      if (h.shares <= 0) continue;
      for (final e in trades.tradesOf(h.code)) {
        if (e.type != EntryType.dividend || e.isReduction) continue;
        if (e.dividendNet <= 0 || !e.date.isAfter(since)) continue;
        final then = sharesBefore(h.code, e.date);
        if (then <= 0) continue;
        final next = DateTime.utc(e.date.year + 1, e.date.month);
        found.add((
          code: h.code,
          name: h.name,
          month: next,
          amount: divideRounded(e.dividendNet * h.shares, then),
        ));
      }
    }
    return found..sort((a, b) => a.month.compareTo(b.month));
  }

  /// The next dividend [code] is expected to pay, if any.
  DividendGuess? nextDividend(String code) =>
      expectedDividends().where((g) => g.code == code).firstOrNull;

  /// The months [code] paid cash dividends in over the last two years, in
  /// order: 「1、4、7、10 月」; empty when none.
  List<int> payingMonths(String code) {
    final since = DateTime.utc(today.year - 2, today.month, today.day);
    return {
      for (final e in trades.tradesOf(code))
        if (e.type == EntryType.dividend &&
            !e.isReduction &&
            e.dividendNet > 0 &&
            e.date.isAfter(since))
          e.date.month,
    }.toList()..sort();
  }
}
