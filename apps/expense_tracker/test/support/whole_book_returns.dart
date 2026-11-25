import 'package:core/percent/percent.dart' show divideRounded;
import 'package:core/time/utc_days.dart' show monthsAfter, yearBefore;
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/features/investments/model/returns.dart';

/// The investments' returns as worked out before review 32 1.1, from every
/// entry each time: what the kept ones must equal (returns_test), and
/// what the gate measures them against.
final class WholeBookReturns {
  WholeBookReturns(this.ledger);

  final Ledger ledger;

  DateTime get today => ledger.today;

  List<Entry> tradesOf(String code) => [
    for (final e in ledger.entries.all)
      if (e.holding == code) e,
  ]..sort(newestFirst(ledger.entries));

  double? rate({String? code}) {
    final codes = code == null
        ? {
            for (final e in countedOn(ledger.entries.all, today))
              if (e.isInvestment) e.holding,
          }
        : {code};
    for (final c in codes) {
      if (c == null) continue;
      if (ledger.holdings.lotsOf(c).any((l) => l.isOpening)) return null;
    }
    final flows = <(DateTime, int)>[
      for (final e in countedOn(ledger.entries.all, today))
        if (e.isInvestment && codes.contains(e.holding))
          if (e.settlement case final cash when cash != 0) (e.date, cash),
    ];
    final held = [
      for (final h in ledger.holdings.all)
        if (codes.contains(h.code)) h.value,
    ].fold(0, (sum, v) => sum + v);
    if (held > 0) flows.add((today, held));
    return xirr(flows);
  }

  int sharesBefore(String code, DateTime day) {
    var shares = ledger.holdings.byCode(code)?.shares ?? 0;
    for (final e in countedOn(tradesOf(code), today)) {
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

  List<DividendGuess> expectedDividends() {
    final since = yearBefore(today);
    final found = <DividendGuess>[];
    for (final h in ledger.holdings.all) {
      if (h.shares <= 0) continue;
      for (final e in tradesOf(h.code)) {
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

  DividendGuess? nextDividend(String code) =>
      expectedDividends().where((g) => g.code == code).firstOrNull;

  List<int> payingMonths(String code) {
    final since = monthsAfter(today, -24);
    return {
      for (final e in tradesOf(code))
        if (e.type == EntryType.dividend &&
            !e.isReduction &&
            e.dividendNet > 0 &&
            e.date.isAfter(since))
          e.date.month,
    }.toList()..sort();
  }
}
