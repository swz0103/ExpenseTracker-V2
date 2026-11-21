/// Checks the closing prices and rates fetched for a ledger: the prices
/// reach the holdings, a stock the exchanges do not quote is named, a
/// stock bought without a close is fetched at once, and a holding's daily
/// closes are read month by month, the finished months kept on the phone.
library;

import 'dart:convert';
import 'dart:io';

import 'package:core/app_core.dart';
import 'package:core/foundation_values.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/ledger/persistence/sql_ledger_data_source.dart';
import 'package:expense_tracker/src/features/investments/model/market_feed.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market/market_data.dart';
import 'package:vault/backup_security.dart';
import 'package:vault/ledger_vault.dart';

final _now = DateTime.utc(2026, 9, 30, 4);

const _twse = '''[
  {"Date":"1150929","Code":"2330","Name":"台積電","ClosingPrice":"1,234.50"}
]''';

/// A month report with a close on each of [days] (ROC dates).
String _report(List<(String, String)> days) => jsonEncode({
  'stat': 'OK',
  'fields': ['日期', '收盤價'],
  'data': [
    for (final (day, close) in days) [day, close],
  ],
});

/// The exchanges as the tests need them: 2330 on TWSE, with closes in
/// August and September; 6488 over the counter, on TPEx only; anything
/// else unknown. [failing] codes have their month reports refused.
final class _Exchanges implements MarketTransport {
  _Exchanges({this.failing = const {}});

  final Set<String> failing;
  final asked = <Uri>[];

  int get twseMonths =>
      asked.where((u) => u.host == MarketDataGateway.twseHistoryHost).length;
  int get tpexMonths => asked.where((u) => u.host == 'www.tpex.org.tw').length;

  @override
  Future<MarketResponse> get(Uri uri) async {
    asked.add(uri);
    if (uri == MarketDataGateway.twseUri) return MarketResponse(200, _twse);
    if (uri.host == MarketDataGateway.twseHistoryHost) {
      final code = uri.queryParameters['stockNo'];
      final date = uri.queryParameters['date'];
      if (failing.contains(code)) return const MarketResponse(500, '');
      if (code != '2330') {
        return MarketResponse(200, jsonEncode({'stat': '沒有符合條件的資料'}));
      }
      return MarketResponse(
        200,
        date == '20260801'
            ? _report([('115/08/28', '1,100.00'), ('115/08/31', '1,110.00')])
            : _report([('115/09/29', '1,234.50')]),
      );
    }
    if (uri.host == 'www.tpex.org.tw' &&
        uri.queryParameters['code'] == '6488') {
      final september = uri.queryParameters['date'] == '2026/09/01';
      return MarketResponse(
        200,
        jsonEncode({
          'stat': 'ok',
          'tables': [
            {
              'fields': ['日期', '收盤'],
              'data': [
                if (september) ['115/09/15', '520.00'],
              ],
            },
          ],
        }),
      );
    }
    return const MarketResponse(404, '');
  }
}

Entry buy(Ledger ledger, String code) => Entry(
  id: ledger.newId(),
  date: DateTime.utc(2026, 9, 1),
  type: EntryType.buy,
  amount: 10000,
  account: 'broker',
  holding: code,
  shares: 10,
);

void main() {
  late Directory directory;
  setUp(() => directory = Directory.systemTemp.createTempSync('feed-'));
  tearDown(() => directory.deleteSync(recursive: true));

  /// A ledger of its own on [exchanges], with a brokerage account that
  /// bought [held], and the feed for it keeping months in [kept].
  Future<(Ledger, MarketFeed)> open(
    _Exchanges exchanges, {
    Directory? kept,
    bool gateway = true,
    List<String> held = const [],
    bool letGo = true,
  }) async {
    final vault = LedgerVault(
      directory.createTempSync('book-'),
      codec: KeyringCodec(kdf: PasswordKdf.insecureForTests),
    );
    final (store, _) = await vault.create('feed password');
    addTearDown(store.close);
    final dataSource = SqlLedgerDataSource(
      store.store,
      clock: FixedClock(UtcInstant(_now)),
      market: gateway
          ? MarketDataGateway(transport: exchanges, clock: () => _now)
          : null,
    );
    final ledger = await dataSource.load();
    ledger.accountCommands.addAccount(
      const Account('broker', '證券戶', AccountKind.bank, 500000),
    );
    for (final code in held) {
      ledger.entryCommands.add(buy(ledger, code));
    }
    final feed = MarketFeed(
      dataSource,
      changes: ledger,
      holdings: ledger.holdings,
      commands: ledger.holdingCommands,
      today: () => ledger.today,
      clock: () => _now,
      historyDir: kept,
    );
    if (letGo) addTearDown(feed.dispose);
    return (ledger, feed);
  }

  test('a refresh puts the closing price on the holding', () async {
    final (ledger, feed) = await open(_Exchanges(), held: ['2330']);
    expect(ledger.holding('2330')!.price, 1000);
    await feed.refresh(force: true);
    expect(ledger.holding('2330')!.price, 1234.5);
    expect(ledger.holding('2330')!.value, 12345);
    expect(feed.problem, isNull);
    expect(feed.lastSuccess, _now);
    expect(feed.busy, isFalse);
  });

  test('a stock the exchanges do not quote is named', () async {
    final (_, feed) = await open(_Exchanges(), held: ['2330', '9999']);
    await feed.refresh(force: true);
    expect(feed.problem, '9999 抓不到收盤價');
  });

  test('a refresh within twenty minutes of the last is not made', () async {
    final exchanges = _Exchanges();
    final (_, feed) = await open(exchanges);
    await feed.refresh();
    final asked = exchanges.asked.length;
    await feed.refresh();
    expect(exchanges.asked, hasLength(asked));
  });

  test('a stock bought without a close is fetched at once', () async {
    final (ledger, _) = await open(_Exchanges());
    expect(ledger.holdings.hasQuote('2330'), isFalse);
    ledger.entryCommands.add(buy(ledger, '2330'));
    await pumpEventQueue();
    expect(ledger.holding('2330')!.price, 1234.5);
  });

  test('once let go, the feed no longer follows the ledger', () async {
    final exchanges = _Exchanges();
    final (ledger, feed) = await open(exchanges, letGo: false);
    feed.dispose();
    ledger.entryCommands.add(buy(ledger, '2330'));
    await pumpEventQueue();
    expect(exchanges.asked, isEmpty);
    expect(ledger.holdings.hasQuote('2330'), isFalse);
  });

  group('a holding\'s daily closes', () {
    test('run from the month asked to today, oldest first', () async {
      final (_, feed) = await open(_Exchanges());
      final closes = await feed.history('2330', DateTime.utc(2026, 8, 15));
      expect(closes, [
        (DateTime.utc(2026, 8, 28), 1100.0),
        (DateTime.utc(2026, 8, 31), 1110.0),
        (DateTime.utc(2026, 9, 29), 1234.5),
      ]);
    });

    test(
      'of a finished month are kept on the phone and not asked again',
      () async {
        final kept = Directory('${directory.path}/prices');
        final first = _Exchanges();
        final (_, feed) = await open(first, kept: kept);
        await feed.history('2330', DateTime.utc(2026, 8));
        expect(first.twseMonths, 2);
        final file = File('${kept.path}/2330.json');
        final json = jsonDecode(file.readAsStringSync()) as Map;
        expect(json['otc'], isFalse);
        expect((json['months'] as Map).keys, ['2026-08']);

        // Opened again: only this month, which is still going, is asked.
        final again = _Exchanges();
        final (_, later) = await open(again, kept: kept);
        final closes = await later.history('2330', DateTime.utc(2026, 8));
        expect(again.twseMonths, 1);
        // Days read back from the phone are UTC midnight, as fetched ones
        // are, so a buy's day and the span's first day match them.
        expect(closes, [
          (DateTime.utc(2026, 8, 28), 1100.0),
          (DateTime.utc(2026, 8, 31), 1110.0),
          (DateTime.utc(2026, 9, 29), 1234.5),
        ]);
      },
    );

    test('of a stock traded over the counter come from TPEx, asked there '
        'first once known', () async {
      final kept = Directory('${directory.path}/prices');
      final first = _Exchanges();
      final (_, feed) = await open(first, kept: kept);
      final closes = await feed.history('6488', DateTime.utc(2026, 8));
      expect(closes, [(DateTime.utc(2026, 9, 15), 520.0)]);
      final json = jsonDecode(
        File('${kept.path}/6488.json').readAsStringSync(),
      );
      expect((json as Map)['otc'], isTrue);
      // August, when it traded nowhere, is kept as a month with no closes.
      expect(json['months'], {'2026-08': <Object?>[]});

      final again = _Exchanges();
      final (_, later) = await open(again, kept: kept);
      await later.history('6488', DateTime.utc(2026, 9));
      expect(again.twseMonths, 0);
      expect(again.tpexMonths, 1);
    });

    test('of a month that cannot be read are left out, not kept', () async {
      final kept = Directory('${directory.path}/prices');
      final (_, feed) = await open(_Exchanges(failing: {'2330'}), kept: kept);
      expect(await feed.history('2330', DateTime.utc(2026, 8)), isEmpty);
      expect(File('${kept.path}/2330.json').existsSync(), isFalse);
    });

    test('kept in a file that cannot be read are fetched again', () async {
      final kept = Directory('${directory.path}/prices')..createSync();
      File('${kept.path}/2330.json').writeAsStringSync(
        jsonEncode({
          'otc': false,
          'months': {
            '2026-08': [
              ['2026-08-28'],
            ],
          },
        }),
      );
      final exchanges = _Exchanges();
      final (_, feed) = await open(exchanges, kept: kept);
      final closes = await feed.history('2330', DateTime.utc(2026, 8));
      expect(exchanges.twseMonths, 2);
      expect(closes, hasLength(3));
    });

    test('are none without a connection to the exchanges', () async {
      final (_, feed) = await open(_Exchanges(), gateway: false);
      expect(await feed.history('2330', DateTime.utc(2026, 8)), isEmpty);
    });
  });
}
