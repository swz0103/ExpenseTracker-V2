// Work package 2.5: rates and quotes keep what they last knew.
import 'dart:io';

import 'package:expense_tracker/src/core/diagnostics/error_log.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/ledger/persistence/sql_ledger_data_source.dart';
import 'package:expense_tracker/src/features/investments/model/dividend_outlook.dart';
import 'package:expense_tracker/src/features/investments/ui/investments.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market/market_data.dart';
import 'package:storage/storage.dart';

import '../baseline/baseline_ledger.dart';
import 'known_defect.dart';

final class _Transport implements MarketTransport {
  _Transport(this.body);
  final String body;
  @override
  Future<MarketResponse> get(Uri uri) async => MarketResponse(200, body);
}

/// The bank's rate board as CSV, with one buying rate per row.
String board(List<String> rows) {
  final days = [10, 30, 60, 90, 120, 150, 180];
  final side = ['匯率', '現金', '即期', for (final d in days) '遠期$d天'];
  return [
    ['﻿幣別', ...side, ...side].join(','),
    ...rows,
  ].join('\r\n');
}

String row(String code, String spot) {
  final forward = List.filled(7, '0.00000').join(',');
  return [
    code,
    '本行買入',
    '0',
    spot,
    forward,
    '本行賣出',
    '0',
    spot,
    forward,
  ].join(',');
}

void main() {
  test(
    'PKG-02: a currency missing from one refresh keeps its last rate',
    () async {
      final dir = Directory.systemTemp.createTempSync('p2-5-');
      final db = EncryptedDatabase.open(
        File('${dir.path}/l.db'),
        StorageKey.random(),
      );
      addTearDown(() {
        db.close();
        dir.deleteSync(recursive: true);
      });
      final now = DateTime.utc(2026, 10, 2, 4);
      MarketDataGateway gateway(String text) =>
          MarketDataGateway(transport: _Transport(text), clock: () => now);
      await SqlLedgerDataSource(
        db,
        market: gateway(board([row('USD', '31.8'), row('JPY', '0.2125')])),
      ).refreshRates();
      await SqlLedgerDataSource(
        db,
        market: gateway(board([row('USD', '31.9')])),
      ).refreshRates();
      final rates = SqlLedgerDataSource(db).market().rates;
      expect(rates['USD'], 31.9);
      // JPY was not in the second board: its last known rate stays.
      expect(rates['JPY'], 0.2125);
    },
    skip: knownDefect('PKG-02', '2.5'),
  );

  test(
    'F22: a rate board that cannot be read is written to the diagnostics log',
    () async {
      final dir = Directory.systemTemp.createTempSync('p2-5-');
      final db = EncryptedDatabase.open(
        File('${dir.path}/l.db'),
        StorageKey.random(),
      );
      addTearDown(() {
        db.close();
        dir.deleteSync(recursive: true);
      });
      final gateway = MarketDataGateway(
        transport: _Transport('<html>maintenance</html>'),
        clock: () => DateTime.utc(2026, 10, 2, 4),
      );
      final before = ErrorLog.instance.count;
      final changed = await SqlLedgerDataSource(
        db,
        market: gateway,
      ).refreshRates();
      expect(changed, isFalse);
      // The failure is on record, not silent.
      expect(ErrorLog.instance.count, greaterThan(before));
    },
    skip: knownDefect('F22', '2.5'),
  );

  test(
    'INV-02: a dividend expected later this month is in the 12-month outlook',
    () {
      final today = day(2026, 11, 21);
      final ledger = ledgerOf(
        today: today,
        accounts: const [Account('bank', '銀行', AccountKind.bank, 1000000)],
        entries: [
          entryOf(
            'b',
            day(2024, 1, 5),
            EntryType.buy,
            100000,
            'bank',
            holding: '0050',
            shares: 1000,
          ),
          // Paid 1,000 on Nov 28 last year: due again on Nov 28, a week out.
          entryOf(
            'd',
            day(2025, 11, 28),
            EntryType.dividend,
            1000,
            'bank',
            holding: '0050',
          ),
        ],
      );
      final outlook = DividendOutlook.of(
        returnsOf(ledger).expectedDividends(),
        today,
      );
      expect(outlook.total, 1000);
    },
    skip: knownDefect('INV-02', '2.5'),
  );
}
