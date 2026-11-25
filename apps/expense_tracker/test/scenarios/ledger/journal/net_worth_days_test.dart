// The journal's net worth on any past day, with a foreign currency
// held at the buying rate and owed at the selling rate, equals the app's
// (parity only compares today's).
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/ledger/repositories/holding_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kernel/kernel.dart';
import 'package:core/foundation_values.dart' show BusinessDate;
import 'package:domain/investments.dart' show DatedFigures, MarketHistory;

import '../../../core/ledger/journal/posted_book.dart';
import 'random_book.dart' as rt;

Future<List<String>> run({
  required bool stocks,
  required bool foreign,
  required bool sell,
  MarketHistory? history,
  int seeds = 40,
}) async {
  final bad = <String>[];
  for (var seed = 1; seed <= seeds; seed++) {
    final today = DateTime.utc(2026, 10, 31);
    final (src, all) = rt.gen(seed, 120, today);
    final log = [
      for (final e in all)
        if ((stocks ||
                !(e.type == EntryType.buy ||
                    e.type == EntryType.sell ||
                    e.type == EntryType.dividend)) &&
            (foreign ||
                (e.account != 'usd' &&
                    e.account != 'ucard' &&
                    e.to != 'usd' &&
                    e.to != 'ucard')))
          e,
    ];
    final Ledger l;
    try {
      l = Ledger(
        today: today,
        accounts: rt.accts,
        categories: src.categories.all.toList(),
        entries: log,
        holdings: (src.holdings as HoldingRepository).start,
        budgets: const [],
        recurring: const [],
        rates: const {'USD': 32.0},
        sellRates: sell ? const {'USD': 32.75} : const {},
        history: history,
      );
    } catch (_) {
      continue; // a filtered book that no longer holds together
    }
    final b = await post(l);
    for (
      var d = DateTime.utc(2026, 8, 1);
      !d.isAfter(today);
      d = d.add(const Duration(days: 3))
    ) {
      final app = l.balanceService.netWorthAt(d);
      final jr = b.reader.netWorth(Day.of(BusinessDate.of(d))).net;
      if (app != jr) {
        bad.add(
          'seed $seed ${d.toIso8601String().substring(0, 10)}: app $app journal $jr (diff ${jr - app})',
        );
        break;
      }
    }
  }
  return bad;
}

/// D58: rates and closes kept on scattered days, as fetches leave them:
/// a past day is valued at its own, or the nearest earlier day's.
final scattered = (() {
  BusinessDate d(int m, int day) => BusinessDate(2026, m, day);
  return MarketHistory(
    buying: DatedFigures({
      'USD': {d(8, 3): 31.2, d(8, 20): 31.65, d(9, 14): 30.9, d(10, 9): 32.0},
    }),
    selling: DatedFigures({
      'USD': {d(8, 20): 32.1, d(10, 1): 32.75},
    }),
    closes: DatedFigures({
      '2330': {
        d(8, 5): 912.0,
        d(8, 27): 955.5,
        d(9, 1): 480.25,
        d(10, 30): 1001.0,
      },
      '0050': {d(8, 10): 61.4, d(9, 22): 64.05},
    }),
  );
})();

void main() {
  test('past days, no stocks, no foreign money', () async {
    final bad = await run(stocks: false, foreign: false, sell: false);
    expect(bad, isEmpty, reason: bad.take(5).join('\n'));
  });
  test('past days, no stocks, US\$ with a buying rate only', () async {
    final bad = await run(stocks: false, foreign: true, sell: false);
    expect(bad, isEmpty, reason: bad.take(5).join('\n'));
  });
  test('past days, no stocks, US\$ held at the buying and owed at the selling rate', () async {
    final bad = await run(stocks: false, foreign: true, sell: true);
    expect(bad, isEmpty, reason: bad.take(5).join('\n'));
  });
  test('past days, stocks only (no foreign money)', () async {
    final bad = await run(stocks: true, foreign: false, sell: false);
    expect(bad, isEmpty, reason: bad.take(5).join('\n'));
  });
  test('past days, everything, two rates', () async {
    final bad = await run(stocks: true, foreign: true, sell: true);
    expect(bad, isEmpty, reason: bad.take(5).join('\n'));
  }, timeout: const Timeout(Duration(minutes: 10)));
  test('D58: past days at rates and closes kept on scattered days', () async {
    final bad = await run(
      stocks: true,
      foreign: true,
      sell: true,
      history: scattered,
    );
    expect(bad, isEmpty, reason: bad.take(5).join('\n'));
  }, timeout: const Timeout(Duration(minutes: 10)));
}
