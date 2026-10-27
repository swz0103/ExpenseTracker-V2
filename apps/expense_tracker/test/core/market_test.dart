import 'dart:io';

import 'package:core/app_core.dart';
import 'package:core/foundation_values.dart';
import 'package:expense_tracker/src/core/ledger/table_journal.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market/market_data.dart';
import 'package:vault/backup_security.dart';
import 'package:vault/ledger_vault.dart';

const _twse = '''[
  {"Date":"1150929","Code":"2330","Name":"台積電","ClosingPrice":"1,234.50"}
]''';

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
    var journal = TableJournal(open.store, clock: clock, market: market);
    var ledger = await journal.load();
    final bank = Account(ledger.newId(), '證券戶', AccountKind.bank, 500000);
    final usd = Account(
      ledger.newId(),
      '美元',
      AccountKind.bank,
      10000,
      currency: 'USD',
    );
    ledger
      ..addAccount(bank)
      ..addAccount(usd)
      ..add(
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

    expect(await journal.refreshQuotes(['2330']), isTrue);
    expect(await journal.refreshRates(), isTrue);
    // Nothing changed since.
    expect(await journal.refreshQuotes(['2330']), isFalse);
    expect(await journal.refreshRates(), isFalse);
    ledger = await journal.load();
    expect(ledger.holding('2330')!.price, 1234.5);
    expect(ledger.holding('2330')!.value, 123450);
    expect(ledger.rates['USD'], closeTo(31.835, 1e-9));
    // US$100 at the spot buying rate.
    expect(ledger.worthOf(ledger.account(usd.id)), 3184);

    // Opened again without a connection, the last board still values
    // the dollars.
    open.close();
    open = await vault.unlockWithPassword('market password');
    journal = TableJournal(open.store, clock: clock);
    ledger = await journal.load();
    expect(ledger.worthOf(ledger.account(usd.id)), 3184);
    open.close();
  });
}
