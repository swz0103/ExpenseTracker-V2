// The journal gives the same figures as the app for the money rules of
// CORR-1: net worth by side (D59, D63), refunds that mirror their
// purchase (D62, D65) and refunds of purchases in instalments.
import 'package:expense_tracker/src/core/ledger/journal/parity.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../baseline/baseline_ledger.dart' show day, entryOf;
import 'posted_book.dart';

Future<void> expectParity(Ledger ledger) async {
  final parity = await parityOf(ledger);
  expect(
    parity,
    isA<InParity>(),
    reason: parity is OutOfParity ? '${parity.differences}' : '',
  );
}

Ledger book({
  required List<Account> accounts,
  List<Entry> entries = const [],
  List<Category> categories = const [],
  Map<String, double> rates = const {},
  Map<String, double> sellRates = const {},
  DateTime? today,
}) => Ledger(
  today: today ?? day(2026, 10, 4),
  accounts: accounts,
  categories: categories,
  entries: entries,
  holdings: const [],
  budgets: const [],
  recurring: const [],
  rates: rates,
  sellRates: sellRates,
);

void main() {
  test('a US\$ card debt at the selling rate and a card in credit: the '
      'journal\'s net worth is the app\'s', () async {
    final ledger = book(
      accounts: const [
        Account('bank', '銀行', AccountKind.bank, 1000),
        Account('usd', '美元', AccountKind.bank, 10000, currency: 'USD'),
        Account(
          'uc',
          '美元卡',
          AccountKind.card,
          -10000,
          currency: 'USD',
          closingDay: 5,
          dueDay: 20,
        ),
        Account('card', '卡', AccountKind.card, 0, closingDay: 5, dueDay: 20),
      ],
      entries: [
        entryOf(
          'pay',
          day(2026, 9, 2),
          EntryType.transfer,
          1500,
          'bank',
          category: transferCategory,
          to: 'card',
        ),
      ],
      rates: {'USD': 32},
      sellRates: {'USD': 32.5},
    );
    // bank 1000 - 1500 = -500 owed; the card's credit 1500 held; US$100
    // held x 32 = 3200; US$100 owed x 32.5 = 3250:
    // 1500 + 3200 - 500 - 3250 = 950.
    expect(ledger.balanceService.netWorthAt(ledger.today), 950);
    await expectParity(ledger);
  });
}
