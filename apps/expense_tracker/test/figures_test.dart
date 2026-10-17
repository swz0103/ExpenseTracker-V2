import 'package:expense_tracker/src/look/figures.dart';
import 'package:expense_tracker/src/model/ledger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('amounts are written in their own currency', () {
    expect(amountIn(1234567, 'TWD'), '1,234,567');
    expect(amountIn(123450, 'USD'), 'USD 1,234.50');
    expect(amountIn(-5, 'USD'), 'USD -0.05');
    expect(amountIn(5000, 'JPY'), 'JPY 5,000');
    expect(plainIn(123450, 'USD'), '1234.50');
    expect(plainIn(300, 'TWD'), '300');
  });

  test('typed amounts are read in the smallest unit', () {
    expect(minorOf('12.5', 'USD'), 1250);
    expect(minorOf('1,200', 'USD'), 120000);
    expect(minorOf('-300', 'TWD'), -300);
    expect(minorOf('12.345', 'USD'), isNull);
    expect(minorOf('1.5', 'TWD'), isNull);
    expect(minorOf('abc', 'TWD'), isNull);
  });

  test('foreign balances count at the board rate', () {
    final ledger = Ledger(
      today: DateTime.utc(2026, 10, 4),
      accounts: const [
        Account('twd', '銀行', AccountKind.bank, 1000),
        Account('usd', '美元', AccountKind.bank, 10000, currency: 'USD'),
        Account('jpy', '日圓', AccountKind.cash, 10000, currency: 'JPY'),
      ],
      categories: const [],
      entries: const [],
      holdings: const [],
      budgets: const [],
      recurring: const [],
      rates: const {'USD': 32.0, 'JPY': 0.2},
    );
    expect(ledger.toHome(10000, 'USD'), 3200);
    expect(ledger.convert(3200, 'TWD', 'USD'), 10000);
    expect(ledger.convert(10000, 'USD', 'JPY'), 16000);
    expect(ledger.assets, 1000 + 3200 + 2000);
    expect(ledger.unrated, isEmpty);
  });
}
