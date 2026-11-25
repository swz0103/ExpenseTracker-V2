import 'dart:convert';
import 'dart:io';

import 'package:core/app_core.dart';
import 'package:core/foundation_values.dart';
import 'package:expense_tracker/src/core/ledger/persistence/book_opening.dart'
    show marketShelf;
import 'package:expense_tracker/src/core/ledger/persistence/sql_ledger_data_source.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:core/fx/dated_figures.dart' show FoundOn;
import 'package:market/market_data.dart';
import 'package:storage/storage.dart' show EncryptedDatabase, StorageKey;
import 'package:vault/ledger_backup.dart';
import 'package:vault/backup_security.dart';
import 'package:vault/ledger_vault.dart';

const _twse = '''[
  {"Date":"1150929","Code":"2330","Name":"台積電","ClosingPrice":"1,234.50"},
  {"Date":"1150929","Code":"2317","Name":"鴻海","ClosingPrice":"--"}
]''';

/// TWSE's month report of 2317: traded on 9/26, not on 9/29.
const _report = '''{"stat":"OK","fields":["日期","成交股數","成交金額","開盤價","最高價","最低價","收盤價","漲跌價差","成交筆數"],
"data":[["115/09/26","1,000","201,500","201.50","201.50","201.50","201.50","+1.50","3"],
["115/09/29","0","0","--","--","--","--"," 0.00","0"]]}''';

/// Bank of Taiwan's board with one USD row: buy side, then sell side,
/// each with cash, spot and seven forward columns.
String _board() {
  final days = [10, 30, 60, 90, 120, 150, 180];
  final side = ['匯率', '現金', '即期', for (final d in days) '遠期$d天'];
  final header = ['﻿幣別', ...side, ...side].join(',');
  final forwards = List.filled(7, '0.00000').join(',');
  final row = [
    'USD',
    ...['本行買入', '31.48500', '31.83500', forwards],
    ...['本行賣出', '32.15500', '31.98500', forwards],
  ].join(',');
  return [header, row].join('\r\n');
}

final class _Market implements MarketTransport {
  var calls = 0;

  @override
  Future<MarketResponse> get(Uri uri) async {
    calls++;
    if (uri == MarketDataGateway.twseUri) return MarketResponse(200, _twse);
    if (uri.host == MarketDataGateway.twseHistoryHost) {
      return const MarketResponse(200, _report);
    }
    if (uri == MarketDataGateway.bankRatesUri) {
      return MarketResponse(200, _board());
    }
    return const MarketResponse(404, '');
  }
}

/// Closing prices and the bank's rates reach the holdings and foreign
/// accounts, and the rates are kept for opening offline.
void main() {
  test('closes and rates are fetched, shown and kept', () async {
    final directory = Directory.systemTemp.createTempSync('market-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final vault = LedgerVault(
      directory,
      codec: KeyringCodec(kdf: PasswordKdf.insecureForTests),
    );
    final clock = FixedClock(UtcInstant(DateTime.utc(2026, 9, 30, 4)));
    final market = MarketDataGateway(
      transport: _Market(),
      clock: () => DateTime.utc(2026, 9, 30, 4),
    );
    var (open, _) = await vault.create('market password');
    var dataSource = SqlLedgerDataSource(
      open.store,
      clock: clock,
      market: market,
    );
    var ledger = await dataSource.load();
    final bank = Account(ledger.newId(), '證券戶', AccountKind.bank, 500000);
    final usd = Account(
      ledger.newId(),
      '美元',
      AccountKind.bank,
      10000,
      currency: 'USD',
    );
    ledger
      ..accountCommands.addAccount(bank)
      ..accountCommands.addAccount(usd)
      ..entryCommands.add(
        Entry(
          id: ledger.newId(),
          date: DateTime.utc(2026, 9, 1),
          type: EntryType.buy,
          amount: 100000,
          account: bank.id,
          category: '投資',
          holding: '2330',
          shares: 100,
        ),
      );
    await ledger.settled;

    expect(await dataSource.refreshQuotes(['2330']), isTrue);
    expect(await dataSource.refreshRates(), isTrue);
    // Nothing changed since.
    expect(await dataSource.refreshQuotes(['2330']), isFalse);
    expect(await dataSource.refreshRates(), isFalse);
    ledger = await dataSource.load();
    expect(ledger.holding('2330')!.price, 1234.5);
    expect(ledger.holding('2330')!.value, 123450);
    expect(ledger.marketData.rates['USD'], closeTo(31.835, 1e-9));
    // The selling rate is kept too, for what is owed in US$ (D59).
    expect(ledger.marketData.sellRates['USD'], closeTo(31.985, 1e-9));
    // US$100 at the spot buying rate.
    expect(ledger.balanceService.worthOf(ledger.account(usd.id)), 3184);

    // Opened again without a connection, the last board still values
    // the dollars.
    open.close();
    open = await vault.unlockWithPassword('market password');
    dataSource = SqlLedgerDataSource(open.store, clock: clock);
    ledger = await dataSource.load();
    expect(ledger.balanceService.worthOf(ledger.account(usd.id)), 3184);
    open.close();
  });

  test('a stock not traded on the day takes its last close, dated', () async {
    final directory = Directory.systemTemp.createTempSync('market-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final vault = LedgerVault(
      directory,
      codec: KeyringCodec(kdf: PasswordKdf.insecureForTests),
    );
    final clock = FixedClock(UtcInstant(DateTime.utc(2026, 9, 30, 4)));
    final market = MarketDataGateway(
      transport: _Market(),
      clock: () => DateTime.utc(2026, 9, 30, 4),
    );
    final (open, _) = await vault.create('market password');
    addTearDown(open.close);
    final dataSource = SqlLedgerDataSource(
      open.store,
      clock: clock,
      market: market,
    );
    expect(await dataSource.refreshQuotes(['2330', '2317']), isTrue);
    expect(dataSource.unquoted, isEmpty);
    final ledger = await dataSource.load();
    expect(ledger.holdings.hasQuote('2317'), isTrue);
    expect(ledger.marketData.olderQuote('2317'), DateTime.utc(2026, 9, 26));
    expect(ledger.marketData.olderQuote('2330'), isNull);
    // D123: 2317's close of 9/26, fetched on 9/30, keeps its fetch day;
    // 2330's of 9/29, fetched the day after, needs none.
    final history = ledger.marketData.history;
    expect(
      history.closeFetchedOn('2317', BusinessDate(2026, 9, 26)),
      BusinessDate(2026, 9, 30),
    );
    expect(history.closeFetchedOn('2330', BusinessDate(2026, 9, 29)), isNull);
  });

  group('D95: a figure fetched that cannot be right is not taken', () {
    /// The exchanges and the bank as [daily] and [spot] say, the clock
    /// [now].
    late String daily;
    late String spot;
    var now = DateTime.utc(2026, 9, 30, 4);
    String closes(String date, String tsmc) =>
        '[{"Date":"$date","Code":"2330","ClosingPrice":"$tsmc"},'
        '{"Date":"$date","Code":"0050","ClosingPrice":"62.75"}]';
    String board(String rate) => _board().replaceFirst('31.83500', rate);

    late EncryptedDatabase store;
    late FixedClock sourceClock;

    Future<SqlLedgerDataSource> source() async {
      final directory = Directory.systemTemp.createTempSync('market-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final vault = LedgerVault(
        directory,
        codec: KeyringCodec(kdf: PasswordKdf.insecureForTests),
      );
      final (open, _) = await vault.create('market password');
      addTearDown(open.close);
      store = open.store;
      sourceClock = FixedClock(UtcInstant(DateTime.utc(2026, 9, 30, 4)));
      return SqlLedgerDataSource(
        open.store,
        clock: sourceClock,
        market: MarketDataGateway(
          transport: _Pages(() => daily, () => spot),
          clock: () => now,
        ),
      );
    }

    setUp(() {
      now = DateTime.utc(2026, 9, 30, 4);
      daily = closes('1150929', '1,234.50');
      spot = board('31.83500');
    });

    test(
      'a close ten times away is doubted: the kept one stays, older',
      () async {
        final data = await source();
        expect(await data.refreshQuotes(['2330', '0050']), isTrue);
        // The next day's list: 1,234.50 became 99,999.00, over ten times.
        daily = closes('1150930', '99,999.00');
        now = now.add(const Duration(hours: 1));
        expect(await data.refreshQuotes(['2330', '0050']), isTrue);
        expect(data.doubtfulCloses, ['2330']);
        final ledger = await data.load();
        expect(ledger.holdings.hasQuote('2330'), isTrue);
        final market = data.market();
        expect(
          market.holdings.firstWhere((h) => h.code == '2330').price,
          1234.5,
        );
        // 0050 moved the quotes on to 9/30; 2330 shows its close of 9/29.
        expect(market.quotedOn, DateTime.utc(2026, 9, 30));
        expect(ledger.marketData.olderQuote('2330'), DateTime.utc(2026, 9, 29));
      },
    );

    test('a rate ten times away is doubted, the kept one stays', () async {
      final data = await source();
      expect(await data.refreshRates(), isTrue);
      spot = board('0.00001');
      now = now.add(const Duration(hours: 1));
      expect(await data.refreshRates(), isFalse);
      expect(data.doubtfulRates, ['USD']);
      expect(data.market().rates['USD'], closeTo(31.835, 1e-9));
    });

    test('a rate doubted is remembered while its currency is off the board, '
        'as a close is (review 18)', () async {
      Map<String, Object?> rates() =>
          jsonDecode(store.row(marketShelf, 'rates')!.body)
              as Map<String, Object?>;
      Object? doubtedKept() => rates()['doubted'];
      final data = await source();
      expect(await data.refreshRates(), isTrue);
      // 400 / 31.835 = 12.6 times: doubted, kept to weigh the next by.
      spot = board('400.00000');
      now = now.add(const Duration(hours: 1));
      await data.refreshRates();
      expect(data.doubtfulRates, ['USD']);
      expect(doubtedKept(), {'USD': 400.0});
      // With the board's day (review 25).
      expect(rates()['doubtedOn'], {'USD': '2026-09-30T00:00:00.000Z'});
      // A board without the dollar: its doubt stays.
      spot = _board().replaceFirst('USD', 'JPY');
      now = now.add(const Duration(hours: 1));
      await data.refreshRates();
      expect(data.doubtfulRates, isEmpty);
      expect(doubtedKept(), {'USD': 400.0});
      // 9/30 to 10/31 is 31 days, more than 30: let go of (review 25).
      now = DateTime.utc(2026, 10, 31, 4);
      await data.refreshRates();
      expect(doubtedKept(), isNull);
      expect(rates()['doubtedOn'], isNull);
    });

    double tsmc(SqlLedgerDataSource data) =>
        data.market().holdings.firstWhere((h) => h.code == '2330').price;

    group('a doubted close weighs the next fetch only while it is recent '
        '(review 25)', () {
      /// 2330 kept at 1,234.50 of 9/29, a fetch of 117.28 doubted as
      /// [doubtedOn] says (none: kept by a version before days were).
      Future<SqlLedgerDataSource> doubtedAt(String? doubtedOn) async {
        final data = await source();
        await data.refreshQuotes(['2330', '0050']);
        store.write(
          (w) => w.put(
            marketShelf,
            'quotes',
            jsonEncode({
              'prices': {'2330': 1234.5, '0050': 62.75},
              'days': {
                '2330': '2026-09-29T00:00:00.000Z',
                '0050': '2026-09-29T00:00:00.000Z',
              },
              'on': '2026-09-29T00:00:00.000Z',
              'doubted': {'2330': 117.28},
              if (doubtedOn != null) 'doubtedOn': {'2330': doubtedOn},
            }),
          ),
          counts: false,
        );
        // 1,234.50 / 117.28 = 10.5 times: doubted alone.
        daily = closes('1150930', '117.28');
        now = now.add(const Duration(hours: 1));
        await data.refreshQuotes(['2330', '0050']);
        return data;
      }

      test('a doubt of the day before agrees: taken', () async {
        final data = await doubtedAt('2026-09-29T00:00:00.000Z');
        expect(data.doubtfulCloses, isEmpty);
        expect(tsmc(data), 117.28);
      });

      test('a doubt 31 days older than the fetch is let go of', () async {
        // 8/30 to 9/30 is 31 days, more than 30.
        final data = await doubtedAt('2026-08-30T00:00:00.000Z');
        expect(data.doubtfulCloses, ['2330']);
        expect(tsmc(data), 1234.5);
      });

      test('a doubt kept with no day is let go of', () async {
        final data = await doubtedAt(null);
        expect(data.doubtfulCloses, ['2330']);
        expect(tsmc(data), 1234.5);
      });
    });

    test(
      'D101: a split of one for twenty the book holds is taken at once',
      () async {
        final data = await source();
        await data.refreshQuotes(['2330', '0050']);
        // 1,234.50 / 20 = 61.725: twenty times smaller, a split after 9/29.
        daily = closes('1150930', '61.73');
        now = now.add(const Duration(days: 1));
        DateTime? askedAfter;
        expect(
          await data.refreshQuotes(
            ['2330', '0050'],
            reshapedBy: (code, day) {
              askedAfter = day;
              return code == '2330' ? 20 : null;
            },
          ),
          isTrue,
        );
        expect(askedAfter, DateTime.utc(2026, 9, 29));
        expect(data.doubtfulCloses, isEmpty);
        expect(tsmc(data), 61.73);
      },
    );

    test('D123: a close kept as fetched days later is weighed in the shares '
        'of its fetch day', () async {
      final data = await source();
      // 9/29's close first fetched on 10/3: a price of the shares after
      // any split dated before 10/3.
      sourceClock.advance(const Duration(days: 3));
      now = DateTime.utc(2026, 10, 3, 4);
      await data.refreshQuotes(['2330', '0050']);
      expect(
        (await data.load()).marketData.history.closeFetchedOn(
          '2330',
          BusinessDate(2026, 9, 29),
        ),
        BusinessDate(2026, 10, 3),
      );
      daily = closes('1151003', '1,240.00');
      now = now.add(const Duration(hours: 1));
      DateTime? askedAfter;
      await data.refreshQuotes(
        ['2330', '0050'],
        reshapedBy: (code, day) {
          if (code == '2330') askedAfter = day;
          return null;
        },
      );
      // Only the splits from 10/3 on are still to come in it: after 10/2.
      expect(askedAfter, DateTime.utc(2026, 10, 2));
    });

    test('a split of one for twenty with a close garbled a hundred times is '
        'doubted (review 18)', () async {
      final data = await source();
      await data.refreshQuotes(['2330', '0050']);
      // Expected 1,234.50 / 20 = 61.725; 6,173.00 is 100 times that,
      // though only 5 times the close kept before the split.
      daily = closes('1150930', '6,173.00');
      now = now.add(const Duration(days: 1));
      await data.refreshQuotes([
        '2330',
        '0050',
      ], reshapedBy: (code, _) => code == '2330' ? 20 : null);
      expect(data.doubtfulCloses, ['2330']);
      expect(tsmc(data), 1234.5);
    });

    test('D101: a split of one for ten then a 5% fall is taken when fetched '
        'again', () async {
      final data = await source();
      await data.refreshQuotes(['2330', '0050']);
      // 1,234.50 / 10 x 0.95 = 117.2775: 1,234.50 / 117.28 = 10.5 times.
      daily = closes('1150930', '117.28');
      now = now.add(const Duration(hours: 1));
      await data.refreshQuotes(['2330', '0050']);
      expect(data.doubtfulCloses, ['2330']);
      expect(tsmc(data), 1234.5);
      // Fetched again, the same close (it agrees within a tenth): taken.
      now = now.add(const Duration(hours: 1));
      await data.refreshQuotes(['2330', '0050']);
      expect(data.doubtfulCloses, isEmpty);
      expect(tsmc(data), 117.28);
    });

    test('D101: after a long gap the kept close gives way', () async {
      final data = await source();
      await data.refreshQuotes(['2330', '0050']);
      // 11/08 is 40 days after 9/29 (more than 30): 1,234.50 to 20.
      now = DateTime.utc(2026, 11, 8, 4);
      sourceClock.advance(now.difference(DateTime.utc(2026, 9, 30, 4)));
      daily = closes('1151108', '20.00');
      await data.refreshQuotes(['2330', '0050']);
      expect(data.doubtfulCloses, isEmpty);
      expect(tsmc(data), 20);
    });

    test('D101: a garbled close is still refused, and forgotten once a '
        'sound one comes', () async {
      final data = await source();
      await data.refreshQuotes(['2330', '0050']);
      daily = closes('1150930', '123,450.00');
      now = now.add(const Duration(hours: 1));
      await data.refreshQuotes(['2330', '0050']);
      expect(data.doubtfulCloses, ['2330']);
      // The next fetch is sound: 1,240 is near 1,234.50, taken.
      daily = closes('1150930', '1,240.00');
      now = now.add(const Duration(hours: 1));
      await data.refreshQuotes(['2330', '0050']);
      expect(data.doubtfulCloses, isEmpty);
      expect(tsmc(data), 1240);
      // The garbled one is forgotten: 123,450 again is doubted again.
      daily = closes('1150930', '123,450.00');
      now = now.add(const Duration(hours: 1));
      await data.refreshQuotes(['2330', '0050']);
      expect(data.doubtfulCloses, ['2330']);
      expect(tsmc(data), 1240);
    });

    test('D101: a rate doubted once and found again is taken', () async {
      final data = await source();
      await data.refreshRates();
      // 31.835 to 3.18 (a tenth less a little): doubted.
      spot = board('3.18000');
      now = now.add(const Duration(hours: 1));
      expect(await data.refreshRates(), isFalse);
      expect(data.doubtfulRates, ['USD']);
      expect(data.market().rates['USD'], closeTo(31.835, 1e-9));
      // Again at 3.18: agreed, taken.
      now = now.add(const Duration(hours: 1));
      expect(await data.refreshRates(), isTrue);
      expect(data.doubtfulRates, isEmpty);
      expect(data.market().rates['USD'], closeTo(3.18, 1e-9));
    });

    test('a close dated after today is not taken (F7)', () async {
      final data = await source();
      // 9991231 is ROC 999: the year 2910.
      daily = closes('9991231', '1,234.50');
      expect(await data.refreshQuotes(['2330']), isFalse);
      expect(data.unquoted, ['2330']);
      expect(data.market().quotedOn, isNull);
    });

    test('a quote day kept ahead of today is let go of', () async {
      final data = await source();
      // An earlier version kept the day of a close dated 2910.
      const ahead = '2910-12-31T00:00:00.000Z';
      store.write(
        (w) => w.put(
          'market',
          'quotes',
          jsonEncode({
            'prices': {'2330': 1234.5},
            'days': {'2330': ahead},
            'on': ahead,
          }),
        ),
        counts: false,
      );
      expect(data.market().quotedOn, DateTime.utc(2910, 12, 31));
      now = now.add(const Duration(hours: 1));
      await data.refreshQuotes(['2330', '0050']);
      expect(data.market().quotedOn, DateTime.utc(2026, 9, 29));
    });

    group('D58: each fetch is kept for its day', () {
      Map<String, Object?>? dayRow(String day) =>
          switch (store.row(marketShelf, 'day:$day')) {
            final row? => jsonDecode(row.body) as Map<String, Object?>,
            null => null,
          };

      test('rates: each board on its day, a doubted one on none', () async {
        final data = await source();
        expect(await data.refreshRates(), isTrue);
        expect(dayRow('2026-09-30'), {
          'rates': {'USD': 31.835},
          'sell': {'USD': 31.985},
        });
        // 10/2: the buying rate moved, the selling rate did not; the
        // selling rate of 9/30 stands for 10/2, so it is not kept again.
        now = DateTime.utc(2026, 10, 2, 4);
        spot = board('32.10000');
        expect(await data.refreshRates(), isTrue);
        expect(dayRow('2026-10-02'), {
          'rates': {'USD': 32.1},
        });
        // 10/3: 0.00001 is doubted (D95): kept for no day.
        now = DateTime.utc(2026, 10, 3, 4);
        spot = board('0.00001');
        await data.refreshRates();
        expect(data.doubtfulRates, ['USD']);
        expect(dayRow('2026-10-03'), isNull);

        final ledger = await data.load();
        final m = ledger.marketData;
        expect(m.rateOn('USD', DateTime.utc(2026, 9, 30)), (
          figure: 31.835,
          of: BusinessDate(2026, 9, 30),
          found: FoundOn.theDay,
        ));
        // 10/1: none of its own, 9/30's.
        expect(m.rateOn('USD', DateTime.utc(2026, 10, 1))?.figure, 31.835);
        expect(m.rateOn('USD', DateTime.utc(2026, 10, 3))?.figure, 32.1);
        expect(
          m.rateOn('USD', DateTime.utc(2026, 10, 2), side: BoardSide.selling),
          (
            figure: 31.985,
            of: BusinessDate(2026, 9, 30),
            found: FoundOn.earlierDay,
          ),
        );
        // Before any board kept: today's.
        expect(m.rateOn('USD', DateTime.utc(2026, 9, 1))?.found, FoundOn.today);
        // US$100 on 10/1: 100 x 31.835 = 3,183.5 -> 3,184; on 10/2:
        // 100 x 32.1 = 3,210.
        expect(m.toHomeOn(10000, 'USD', DateTime.utc(2026, 10, 1)), 3184);
        expect(m.toHomeOn(10000, 'USD', DateTime.utc(2026, 10, 2)), 3210);
      });

      test(
        'closes: each on the day it is for, a doubted one on none',
        () async {
          final data = await source();
          expect(await data.refreshQuotes(['2330', '0050']), isTrue);
          expect(dayRow('2026-09-29'), {
            'closes': {'2330': 1234.5, '0050': 62.75},
          });
          daily = closes('1150930', '1,240.00');
          now = now.add(const Duration(hours: 1));
          await data.refreshQuotes(['2330', '0050']);
          // 0050 is unchanged: 9/29's stands for 9/30.
          expect(dayRow('2026-09-30'), {
            'closes': {'2330': 1240.0},
          });
          // 99,999 is doubted (D95): kept for no day.
          daily = closes('1151001', '99,999.00');
          now = DateTime.utc(2026, 10, 1, 4);
          sourceClock.advance(const Duration(days: 1));
          await data.refreshQuotes(['2330', '0050']);
          expect(data.doubtfulCloses, ['2330']);
          expect(dayRow('2026-10-01'), isNull);

          final m = (await data.load()).marketData;
          expect(m.closeOn('2330', DateTime.utc(2026, 9, 29))?.figure, 1234.5);
          expect(m.closeOn('2330', DateTime.utc(2026, 10, 1)), (
            figure: 1240.0,
            of: BusinessDate(2026, 9, 30),
            found: FoundOn.earlierDay,
          ));
          expect(m.closeOn('0050', DateTime.utc(2026, 9, 30))?.figure, 62.75);
          expect(
            m.closeOn('2330', DateTime.utc(2026, 9, 1))?.found,
            FoundOn.today,
          );
        },
      );

      test('a book kept before D58 keeps its latest close for its day '
          'when a new one comes', () async {
        final data = await source();
        store.write(
          (w) => w.put(
            marketShelf,
            'quotes',
            jsonEncode({
              'prices': {'2330': 1200.0},
              'days': {'2330': '2026-09-26T00:00:00.000Z'},
              'on': '2026-09-26T00:00:00.000Z',
            }),
          ),
          counts: false,
        );
        // Before any fetch, its one close is read as of its day.
        expect(
          data.market().history.closes.on('2330', BusinessDate(2026, 9, 28)),
          (
            figure: 1200.0,
            of: BusinessDate(2026, 9, 26),
            found: FoundOn.earlierDay,
          ),
        );
        await data.refreshQuotes(['2330', '0050']);
        expect(dayRow('2026-09-26'), {
          'closes': {'2330': 1200.0},
        });
        expect(dayRow('2026-09-29')?['closes'], {
          '2330': 1234.5,
          '0050': 62.75,
        });
      });

      test('a backup carries the days, and a restore keeps them', () async {
        final data = await source();
        await data.refreshRates();
        await data.refreshQuotes(['2330', '0050']);
        final keys = (await KeyringCodec(
          kdf: PasswordKdf.insecureForTests,
        ).create('backup password')).unlocked;
        final directory = Directory.systemTemp.createTempSync('market-b-');
        addTearDown(() => directory.deleteSync(recursive: true));
        final file = File('${directory.path}/b.etbk');
        await LedgerBackup.write(
          store: store,
          keys: keys,
          file: file,
          backupId: 'b',
          createdAt: now,
        );
        final into = EncryptedDatabase.open(
          File('${directory.path}/into.db'),
          StorageKey.random(),
        );
        addTearDown(into.close);
        await LedgerBackup.restore(
          file: file,
          keys: keys,
          into: into,
          accept: SqlLedgerDataSource.check,
        );
        expect(into.row(marketShelf, 'day:2026-09-30'), isNotNull);
        expect(into.row(marketShelf, 'day:2026-09-29'), isNotNull);
        final m = (await SqlLedgerDataSource(
          into,
          clock: sourceClock,
        ).load()).marketData;
        expect(m.closeOn('2330', DateTime.utc(2026, 9, 29))?.figure, 1234.5);
        expect(
          m.rateOn('USD', DateTime.utc(2026, 9, 30))?.found,
          FoundOn.theDay,
        );
      });

      test('a day row is checked as a backup is restored', () {
        expect(
          () => SqlLedgerDataSource.check(
            marketShelf,
            'day:2026-09-30',
            '{"rates":{"USD":31.8},"closes":{"2330":1234.5}}',
          ),
          returnsNormally,
        );
        for (final (id, body) in [
          ('day:2026-13-01', '{}'),
          ('day:2026-09-30', '{"rates":{"USD":"high"}}'),
          ('day:2026-09-30', '{"closes":{"2330":-1}}'),
          ('day:2026-09-30', '{"sell":[1]}'),
          ('days', '{}'),
        ]) {
          expect(
            () => SqlLedgerDataSource.check(marketShelf, id, body),
            throwsFormatException,
            reason: '$id $body',
          );
        }
      });
    });
  });
}

/// The day's list and the bank's board as the test has them now.
final class _Pages implements MarketTransport {
  _Pages(this.daily, this.spot);

  final String Function() daily;
  final String Function() spot;

  @override
  Future<MarketResponse> get(Uri uri) async {
    if (uri == MarketDataGateway.twseUri) return MarketResponse(200, daily());
    if (uri == MarketDataGateway.bankRatesUri) {
      return MarketResponse(200, spot());
    }
    return const MarketResponse(404, '');
  }
}
