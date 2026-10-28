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

/// The money an investment entry moved: a buy paid with its fee, a sale
/// received after fee and tax, a cash dividend after the premium, the cash
/// back of a capital reduction. Shares given carry no money.
int cashOf(Entry e) => switch (e.type) {
  EntryType.buy => -(e.amount + e.fee),
  EntryType.sell => e.amount - e.fee - e.tax,
  EntryType.dividend when e.isReduction => e.amount,
  EntryType.dividend => e.dividendNet,
  _ => 0,
};

/// The yearly money-weighted return of [code], or of everything invested
/// when null: every trade and dividend, and what is still held as if sold
/// at today's close. Null when it cannot be worked out, as for shares
/// held from before the book began (their buying day is not known).
double? returnOf(Ledger ledger, {String? code}) {
  final codes = code == null
      ? {for (final e in ledger.entries) if (e.isInvestment) e.holding}
      : {code};
  for (final c in codes) {
    if (c == null) continue;
    if (ledger.lotsOf(c).any((l) => l.isOpening)) return null;
  }
  final flows = <(DateTime, int)>[
    for (final e in ledger.entries)
      if (e.isInvestment && codes.contains(e.holding))
        if (cashOf(e) case final cash when cash != 0) (e.date, cash),
  ];
  final held = [
    for (final h in ledger.holdings)
      if (codes.contains(h.code)) h.value,
  ].fold(0, (sum, v) => sum + v);
  if (held > 0) flows.add((ledger.today, held));
  return xirr(flows);
}

/// Since when [code] (or anything, when null) has been invested: the
/// first trade.
DateTime? investedSince(Ledger ledger, {String? code}) {
  DateTime? first;
  for (final e in ledger.entries) {
    if (!e.isInvestment || (code != null && e.holding != code)) continue;
    if (first == null || e.date.isBefore(first)) first = e.date;
  }
  return first;
}

/// A dividend expected in [month], from what [code] paid a year before.
typedef DividendGuess = ({String code, String name, DateTime month, int amount});

/// The shares of [code] held on the eve of [day]: those held now, less
/// every change from [day] on.
int sharesBefore(Ledger ledger, String code, DateTime day) {
  var shares = ledger.holding(code)?.shares ?? 0;
  for (final e in ledger.tradesOf(code)) {
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
List<DividendGuess> expectedDividends(Ledger ledger) {
  final today = ledger.today;
  final since = DateTime.utc(today.year - 1, today.month, today.day);
  final found = <DividendGuess>[];
  for (final h in ledger.holdings) {
    if (h.shares <= 0) continue;
    for (final e in ledger.tradesOf(h.code)) {
      if (e.type != EntryType.dividend || e.isReduction) continue;
      if (e.dividendNet <= 0 || !e.date.isAfter(since)) continue;
      final then = sharesBefore(ledger, h.code, e.date);
      if (then <= 0) continue;
      final next = DateTime.utc(e.date.year + 1, e.date.month);
      found.add((
        code: h.code,
        name: h.name,
        month: next,
        amount: (e.dividendNet * h.shares / then).round(),
      ));
    }
  }
  return found..sort((a, b) => a.month.compareTo(b.month));
}

/// The months [code] paid cash dividends in over the last two years, in
/// order: 「1、4、7、10 月」; empty when none.
List<int> payingMonths(Ledger ledger, String code) {
  final today = ledger.today;
  final since = DateTime.utc(today.year - 2, today.month, today.day);
  return {
    for (final e in ledger.tradesOf(code))
      if (e.type == EntryType.dividend &&
          !e.isReduction &&
          e.dividendNet > 0 &&
          e.date.isAfter(since))
        e.date.month,
  }.toList()..sort();
}
