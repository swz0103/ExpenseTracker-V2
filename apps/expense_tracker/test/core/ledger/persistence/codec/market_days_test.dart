import 'dart:convert';

import 'package:core/foundation_values.dart' show BusinessDate;
import 'package:core/fx/dated_figures.dart' show FoundOn, MarketHistory;
import 'package:expense_tracker/src/core/ledger/persistence/book_opening.dart';
import 'package:expense_tracker/src/core/ledger/persistence/codec/market_days.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storage/storage.dart' show StoredRow;

/// D58: a day's rates and closes in one market row, `day:` and the day.
MarketHistory datedOf(Market market) => datedMarket(
  history: market.history,
  rates: market.rates,
  sellRates: market.sellRates,
  ratesOn: market.ratesOn,
  prices: market.prices,
  days: market.days,
);

void main() {
  BusinessDate d(int m, int day) => BusinessDate(2026, m, day);

  test('a day row is named by its day, and only a day row is', () {
    expect(marketDayId(d(3, 9)), 'day:2026-03-09');
    expect(marketDayOf('day:2026-03-09'), d(3, 9));
    expect(marketDayOf('quotes'), isNull);
    expect(marketDayOf('rates'), isNull);
    expect(() => marketDayOf('day:3/9'), throwsFormatException);
  });

  test('the rows read back as the tables', () {
    final history = historyFrom({
      d(3, 2): '{"rates":{"USD":31.5},"sell":{"USD":32},"closes":{"2330":900}}',
      d(3, 9): '{"rates":{"USD":31.9}}',
    });
    expect(history.buying.exactly('USD', d(3, 9)), 31.9);
    expect(history.selling.exactly('USD', d(3, 2)), 32.0);
    expect(history.closes.on('2330', d(3, 9))?.figure, 900);
    expect(historyFrom({}).isEmpty, isTrue);
  });

  test('a row that cannot be right is refused', () {
    for (final body in [
      '[]',
      '{"rates":[1]}',
      '{"rates":{"USD":"31"}}',
      '{"closes":{"2330":0}}',
      '{"sell":{"USD":-1}}',
    ]) {
      expect(
        () => historyFrom({d(3, 2): body}),
        throwsFormatException,
        reason: body,
      );
    }
  });

  group('what a fetch keeps', () {
    test('only what the days kept do not already give', () {
      final writes = MarketDayWrites(
        historyFrom({d(3, 2): '{"rates":{"USD":31.5}}'}),
      );
      // 3/5 at 31.5: 3/2's stands for it.
      writes.keep(MarketSeries.buying, 'USD', d(3, 5), 31.5);
      expect(writes.rows, isEmpty);
      writes.keep(MarketSeries.buying, 'USD', d(3, 6), 31.7);
      writes.keep(MarketSeries.closes, '2330', d(3, 6), 910);
      expect(writes.rows.keys, ['day:2026-03-06']);
      expect(jsonDecode(writes.rows['day:2026-03-06']!), {
        'rates': {'USD': 31.7},
        'closes': {'2330': 910.0},
      });
      expect(writes.history.buying.exactly('USD', d(3, 6)), 31.7);
      // No price is kept.
      writes.keep(MarketSeries.selling, 'USD', d(3, 7), 0);
      writes.keep(MarketSeries.selling, 'USD', d(3, 7), double.nan);
      expect(writes.rows.keys, ['day:2026-03-06']);
    });

    test('the figure replaced is kept for its own day first', () {
      final writes = MarketDayWrites(MarketHistory());
      writes.keep(
        MarketSeries.closes,
        '2330',
        d(3, 9),
        950,
        kept: 900,
        keptOn: d(3, 6),
      );
      expect(writes.rows.keys.toSet(), {'day:2026-03-06', 'day:2026-03-09'});
      // One kept for the same day is no earlier figure.
      final same = MarketDayWrites(MarketHistory())
        ..keep(
          MarketSeries.closes,
          '2330',
          d(3, 9),
          950,
          kept: 900,
          keptOn: d(3, 9),
        );
      expect(same.rows.keys, ['day:2026-03-09']);
    });
  });

  group('D123: a close fetched on a later day keeps that day', () {
    test('written beside the close, read back', () {
      final writes = MarketDayWrites(MarketHistory());
      writes.keep(
        MarketSeries.closes,
        '2330',
        d(3, 6),
        910,
        fetchedOn: d(3, 10),
      );
      // A rate is never kept with a fetch day; a close fetched on its
      // own day neither.
      writes.keep(
        MarketSeries.buying,
        'USD',
        d(3, 6),
        31.7,
        fetchedOn: d(3, 10),
      );
      writes.keep(
        MarketSeries.closes,
        '0050',
        d(3, 6),
        150,
        fetchedOn: d(3, 6),
      );
      // Nor one fetched the next day: no split falls between.
      writes.keep(
        MarketSeries.closes,
        '2317',
        d(3, 6),
        201,
        fetchedOn: d(3, 7),
      );
      expect(jsonDecode(writes.rows['day:2026-03-06']!), {
        'rates': {'USD': 31.7},
        'closes': {'2330': 910.0, '0050': 150.0, '2317': 201.0},
        'fetched': {'2330': '2026-03-10'},
      });
      expect(writes.history.closeFetchedOn('2330', d(3, 6)), d(3, 10));
      expect(writes.history.closeFetchedOn('0050', d(3, 6)), isNull);
      final read = historyFrom({d(3, 6): writes.rows['day:2026-03-06']!});
      expect(read.closeFetchedOn('2330', d(3, 6)), d(3, 10));
      expect(read.closes.exactly('2330', d(3, 6)), 910);
    });

    test('a close kept stands as first fetched', () {
      final kept = historyFrom({
        d(3, 6): '{"closes":{"2330":910},"fetched":{"2330":"2026-03-10"}}',
      });
      // The same close of 3/6 fetched again, on any day or none known:
      // nothing is written, its fetch day stays.
      for (final on in [d(3, 6), d(3, 20), null]) {
        final writes = MarketDayWrites(kept)
          ..keep(MarketSeries.closes, '2330', d(3, 6), 910, fetchedOn: on);
        expect(writes.rows, isEmpty, reason: '$on');
        expect(writes.history.closeFetchedOn('2330', d(3, 6)), d(3, 10));
      }
      // A new figure for the day takes its own fetch day, or none.
      final changed = MarketDayWrites(kept)
        ..keep(MarketSeries.closes, '2330', d(3, 6), 455, fetchedOn: d(3, 7));
      expect(jsonDecode(changed.rows['day:2026-03-06']!), {
        'closes': {'2330': 455.0},
      });
      // 3/9 at 910 fetched on 3/9: of other shares than 3/6's fetched on
      // 3/10, so kept for its day; fetched on 3/12, alike, it is not.
      final later = MarketDayWrites(kept)
        ..keep(MarketSeries.closes, '2330', d(3, 9), 910, fetchedOn: d(3, 9));
      expect(later.rows.keys, ['day:2026-03-09']);
      final alike = MarketDayWrites(
        historyFrom({
          d(3, 6): '{"closes":{"2330":910},"fetched":{"2330":"2026-03-12"}}',
        }),
      )..keep(MarketSeries.closes, '2330', d(3, 9), 910, fetchedOn: d(3, 12));
      expect(alike.rows, isEmpty);
    });

    test('a fetch day that cannot be read is refused', () {
      for (final body in ['{"fetched":[1]}', '{"fetched":{"2330":5}}']) {
        expect(
          () => historyFrom({d(3, 2): body}),
          throwsFormatException,
          reason: body,
        );
      }
    });
  });

  group('a book kept before D58', () {
    StoredRow row(String id, Object body) =>
        StoredRow(0, marketShelf, id, jsonEncode(body));

    test('reads its latest board and closes as of their days', () {
      final market = marketFrom([
        row('rates', {
          'asOf': '2026-03-09',
          'rates': {'USD': 31.9},
          'sell': {'USD': 32.2},
        }),
        row('quotes', {
          'prices': {'2330': 950, '0050': 60},
          'days': {'2330': '2026-03-06T00:00:00.000Z'},
        }),
      ]);
      expect(market.history.isEmpty, isTrue);
      final dated = datedOf(market);
      expect(dated.buying.on('USD', d(3, 10)), (
        figure: 31.9,
        of: d(3, 9),
        found: FoundOn.earlierDay,
      ));
      expect(dated.selling.exactly('USD', d(3, 9)), 32.2);
      expect(dated.closes.exactly('2330', d(3, 6)), 950);
      // A close with no day kept is in no day's row.
      expect(dated.closes.on('0050', d(3, 9)), isNull);
    });

    test('a board of no known day is in no day\'s row', () {
      final dated = datedOf(
        marketFrom([
          row('rates', {
            'rates': {'USD': 31.9},
          }),
        ]),
      );
      expect(dated.isEmpty, isTrue);
    });

    test('with day rows, the latest is added only where it differs', () {
      final market = marketFrom([
        row('rates', {
          'asOf': '2026-03-09',
          'rates': {'USD': 31.9},
        }),
        row('day:2026-03-02', {
          'rates': {'USD': 31.9},
        }),
      ]);
      final dated = datedOf(market);
      // 3/2's stands for 3/9: not added again.
      expect(dated.buying.figures['USD'], {d(3, 2): 31.9});
    });
  });
}
