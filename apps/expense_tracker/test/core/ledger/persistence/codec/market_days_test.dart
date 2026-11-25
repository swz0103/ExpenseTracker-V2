import 'dart:convert';

import 'package:core/foundation_values.dart' show BusinessDate;
import 'package:core/fx/dated_figures.dart' show FoundOn, MarketHistory;
import 'package:expense_tracker/src/core/ledger/persistence/market_rows.dart';
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

  test('review 39: a row written over the one kept now keeps its other '
      'series', () {
    final writes = MarketDayWrites(MarketHistory())
      ..keep(MarketSeries.closes, '2330', d(9, 30), 1240, fetchedOn: d(10, 3));
    final kept = {
      'day:2026-09-30': '{"rates":{"USD":31.8},"closes":{"2330":1}}',
    };
    expect(
      jsonDecode(
        writes.rowsOver((id) => kept[id], {
          MarketSeries.closes,
        })['day:2026-09-30']!,
      ),
      {
        'rates': {'USD': 31.8},
        'closes': {'2330': 1240.0},
        'fetched': {'2330': '2026-10-03'},
      },
    );
    // None kept, or one that cannot be read: as written.
    for (final stored in [null, 'not json', '[1]']) {
      expect(
        writes.rowsOver((_) => stored, {MarketSeries.closes}),
        writes.rows,
        reason: stored,
      );
    }
  });

  group('review 39: months long gone are one row each', () {
    // Today 2026-11-25: kept whole from 400 days before, 2025-10-21.
    final today = d(11, 25);
    BusinessDate y25(int m, int day) => BusinessDate(2025, m, day);
    Map<BusinessDate, DayFigures> rows(Map<BusinessDate, String> bodies) => {
      for (final MapEntry(:key, :value) in bodies.entries)
        key: dayFiguresOf(value),
    };

    test('a month ended before the window: its last figures, on its first '
        'day', () {
      final changes = foldedDays(
        rows({
          y25(3, 3): '{"rates":{"USD":30.1,"JPY":0.2},"closes":{"2330":600}}',
          y25(3, 20): '{"rates":{"USD":30.4},"closes":{"2330":610}}',
          y25(3, 31): '{"rates":{"USD":30.6}}',
          // September ends 2025-09-30, before 10/21: folded too.
          y25(9, 1): '{"rates":{"USD":31}}',
          // October ends after 10/21: kept whole.
          y25(10, 2): '{"rates":{"USD":32}}',
        }),
        today,
      );
      expect(changes.keys.toSet(), {
        'day:2025-03-01',
        'day:2025-03-03',
        'day:2025-03-20',
        'day:2025-03-31',
      });
      expect(changes['day:2025-03-03'], isNull);
      expect(changes['day:2025-03-31'], isNull);
      // USD 3/31's, JPY 3/3's, 2330 3/20's, fetched at the latest 3/21.
      expect(jsonDecode(changes['day:2025-03-01']!), {
        'rates': {'USD': 30.6, 'JPY': 0.2},
        'closes': {'2330': 610.0},
        'fetched': {'2330': '2025-03-21'},
      });
      // A month already one row on its first day is left.
      expect(
        foldedDays(rows({y25(3, 1): changes['day:2025-03-01']!}), today),
        isEmpty,
      );
    });

    test('the folded row reads as the month\'s figure for each of its days, '
        'within the 30 days (D123)', () {
      final folded = foldedDays(
        rows({
          y25(3, 3): '{"rates":{"USD":30.1},"closes":{"2330":600}}',
          y25(3, 31): '{"rates":{"USD":30.6},"closes":{"2330":300}}',
        }),
        today,
      );
      final history = historyFrom({y25(3, 1): folded['day:2025-03-01']!});
      final usd = history.buying.on('USD', y25(3, 31), earlierWithinDays: 30);
      // 3/1 to 3/31 is 30 days: an earlier day's, taken.
      expect(usd, (figure: 30.6, of: y25(3, 1), found: FoundOn.earlierDay));
      // 3/31's close keeps the day after it as fetched on: a split on
      // 3/31 or before is in it, one after not.
      expect(history.closeFetchedOn('2330', y25(3, 1)), y25(4, 1));
    });

    test('a close fetched days later keeps that day', () {
      final folded = foldedDays(
        rows({
          y25(3, 3): '{"closes":{"2330":600},"fetched":{"2330":"2025-03-10"}}',
          // 3/1's own, fetched on its day: none to keep.
          y25(4, 1): '{"closes":{"2330":620}}',
          y25(4, 2): '{"rates":{"USD":30}}',
        }),
        today,
      );
      expect(jsonDecode(folded['day:2025-03-01']!), {
        'closes': {'2330': 600.0},
        'fetched': {'2330': '2025-03-10'},
      });
      expect(jsonDecode(folded['day:2025-04-01']!), {
        'rates': {'USD': 30.0},
        'closes': {'2330': 620.0},
      });
    });

    test('foldedMarket keeps the rest and names what to write', () {
      final kept = [
        StoredRow(0, marketShelf, 'quotes', '{"prices":{"2330":1000}}'),
        StoredRow(0, marketShelf, 'day:2025-03-03', '{"rates":{"USD":30}}'),
        StoredRow(0, marketShelf, 'day:2025-03-04', '{"rates":{"USD":31}}'),
        StoredRow(0, marketShelf, 'day:2025-03-05', 'not json'),
        StoredRow(0, marketShelf, 'day:2026-11-20', '{"rates":{"USD":32}}'),
      ];
      final told = <Object>[];
      final folded = foldedMarket(kept, today, report: told.add);
      expect(told, hasLength(1));
      expect(
        [for (final r in folded.rows) r.id],
        ['quotes', 'day:2025-03-05', 'day:2026-11-20', 'day:2025-03-01'],
      );
      expect(folded.changes, hasLength(3));
      final market = readMarket(folded.rows, report: told.add);
      expect(market.history.buying.exactly('USD', y25(3, 1)), 31);
      expect(market.prices, {'2330': 1000.0});
      // Read without history, no day row is read at all.
      expect(readMarket(kept, history: false).history.isEmpty, isTrue);
      expect(foldedMarket(folded.rows, today).changes, isEmpty);
    });
  });

  group('N3: a month report fills the past days', () {
    // 2330 kept on 9/1 at 960 and 9/29 at 1,000.
    MarketDayWrites kept() => MarketDayWrites(
      historyFrom({
        d(9, 1): '{"closes":{"2330":960}}',
        d(9, 29): '{"closes":{"2330":1000}}',
      }),
    );
    double? never(DateTime day) => null;

    test('only days before the one given that have none, as fetched', () {
      final writes = kept();
      final count = writes.fillPastCloses(
        '2330',
        [
          (d(9, 29), 999),
          (d(9, 1), 955),
          (d(9, 10), 970),
          (d(8, 28), 950),
          (d(9, 30), 1010),
        ],
        before: d(9, 29),
        fetchedOn: d(9, 30),
        reshapedBy: never,
      );
      // 8/28 and 9/10 kept; 9/1 has its own, 9/29 and 9/30 are not before.
      expect(count, 2);
      expect(writes.rows.keys.toSet(), {'day:2026-08-28', 'day:2026-09-10'});
      final history = writes.history;
      expect(history.closes.exactly('2330', d(9, 1)), 960);
      expect(history.closes.exactly('2330', d(9, 10)), 970);
      expect(history.closeFetchedOn('2330', d(8, 28)), d(9, 30));
      expect(history.closes.exactly('2330', d(9, 30)), isNull);
    });

    test('a close the doubt rules refuse is not kept', () {
      final writes = kept();
      // 96,000 on 9/10 is 100 times 9/1's 960: doubted (D95).
      expect(
        writes.fillPastCloses(
          '2330',
          [(d(9, 10), 96000)],
          before: d(9, 29),
          fetchedOn: d(9, 30),
          reshapedBy: never,
        ),
        0,
      );
      // Before any kept: weighed against the earliest, 9/1's 960.
      expect(
        writes.fillPastCloses(
          '2330',
          [(d(8, 20), 9.6)],
          before: d(9, 29),
          fetchedOn: d(9, 30),
          reshapedBy: never,
        ),
        0,
      );
      expect(writes.rows, isEmpty);
    });

    test('a day before a split the book holds is left', () {
      final writes = kept();
      // A split on 9/15: 9/10's report close may be of either shares.
      expect(
        writes.fillPastCloses(
          '2330',
          [(d(9, 10), 970), (d(9, 20), 490)],
          before: d(9, 29),
          fetchedOn: d(9, 30),
          reshapedBy: (day) =>
              day.isBefore(DateTime.utc(2026, 9, 15)) ? 2 : null,
        ),
        // 9/20, after it, is weighed against 9/1's 960 / 2 = 480: taken.
        1,
      );
      expect(writes.rows.keys, ['day:2026-09-20']);
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

/// The history kept in the day rows [bodies], by day, as an opening reads
/// it (`readMarket`). Throws a [FormatException] for a row that cannot be
/// read.
MarketHistory historyFrom(Map<BusinessDate, String> bodies) => historyOf({
  for (final MapEntry(key: day, value: body) in bodies.entries)
    day: dayFiguresOf(body),
});
