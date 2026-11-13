import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:flutter_test/flutter_test.dart';

/// What comes back from 最近刪除 fits the book as it is now (the code
/// review of 2026-11-13, finding 5).
void main() {
  Ledger book() => Ledger(
    today: DateTime.utc(2026, 11, 13),
    accounts: const [
      Account('bank', '銀行', AccountKind.bank, 10000),
      Account('cash', '現金', AccountKind.cash, 500),
    ],
    categories: const [
      Category('飲食', 'food', Color(0xFFD08B5B)),
      Category('外食', 'food', Color(0xFFD08B5B)),
    ],
    entries: [
      Entry(
        id: 'lunch',
        date: DateTime.utc(2026, 11, 12),
        type: EntryType.expense,
        amount: 120,
        account: 'cash',
        category: '外食',
        merchant: '巷口',
        tags: const ['出差'],
      ),
    ],
    holdings: const [],
    budgets: const [],
    recurring: const [],
  );

  test('a merged category, tag or merchant reaches the trash too', () {
    final ledger = book();
    ledger.remove('lunch');
    ledger.mergeCategory('外食', '飲食');
    ledger.renameTag('出差', '台中出差');
    ledger.renameMerchant('巷口', '巷口麵店');
    expect(ledger.restoreTrashed(ledger.trash.single), isTrue);
    final back = ledger.byId('lunch')!;
    expect(back.category, '飲食');
    expect(back.tags, ['台中出差']);
    expect(back.merchant, '巷口麵店');
    expect(ledger.categories.map((c) => c.name), isNot(contains('外食')));
  });

  test('an account its deleted entries name stays, so they can come back', () {
    final ledger = book();
    ledger.remove('lunch');
    expect(ledger.isUsed('cash'), isTrue, reason: 'the trash names it');
    ledger.removeAccount('cash');
    expect(ledger.hasAccount('cash'), isTrue);
    expect(ledger.restoreTrashed(ledger.trash.single), isTrue);
    expect(ledger.balance('cash'), 380);
  });
}
