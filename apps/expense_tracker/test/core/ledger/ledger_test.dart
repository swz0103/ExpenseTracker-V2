import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fuzz/ledger_fuzz.dart';

void main() {
  ledgerFuzz();

  test('foreign balances count at the board rate', () {
    final ledger = Ledger(
      today: DateTime.utc(2026, 10, 4),
      accounts: const [
        Account('twd', '銀行', AccountKind.bank, 1000),
        Account('usd', '美元', AccountKind.bank, 10000, currency: 'USD'),
        Account('jpy', '日圓', AccountKind.cash, 10000, currency: 'JPY'),
      ],
      categories: [],
      entries: const [],
      holdings: const [],
      budgets: const [],
      recurring: const [],
      rates: const {'USD': 32.0, 'JPY': 0.2},
    );
    expect(ledger.marketData.toHome(10000, 'USD'), 3200);
    expect(ledger.marketData.convert(3200, 'TWD', 'USD'), 10000);
    expect(ledger.marketData.convert(10000, 'USD', 'JPY'), 16000);
    expect(ledger.balanceService.assets, 1000 + 3200 + 2000);
    expect(ledger.balanceService.unrated, isEmpty);
  });

  test('a card close moved into the next month still counts', () {
    final card = Account(
      'card',
      '卡',
      AccountKind.card,
      0,
      closingDay: 31,
      dueDay: 31,
      closes: {DateTime.utc(2026, 1, 31): DateTime.utc(2026, 2, 2)},
    );
    final ledger = Ledger(
      today: DateTime.utc(2026, 4, 5),
      accounts: [card],
      categories: [],
      entries: const [],
      holdings: const [],
      budgets: const [],
      recurring: const [],
    );
    expect(
      card.closingOn(DateTime.utc(2026, 2, 1)),
      DateTime.utc(2025, 12, 31),
    );
    expect(card.closingOn(DateTime.utc(2026, 2, 3)), DateTime.utc(2026, 2, 2));
    // Due on the 31st, kept within April.
    final (_, end, due) = ledger.statementService.statement(card);
    expect((end, due), (DateTime.utc(2026, 3, 31), DateTime.utc(2026, 4, 30)));
  });

  test('a purchase on the closing day joins that statement', () {
    final card = Account('card', '卡', AccountKind.card, 0, closingDay: 25);
    Entry charge(String id, DateTime date, {int installments = 0}) => Entry(
      id: id,
      date: date,
      type: EntryType.expense,
      amount: 3000,
      account: 'card',
      category: '購物',
      installments: installments,
    );
    final split = charge('a', DateTime.utc(2026, 3, 25), installments: 3);
    final ledger = Ledger(
      today: DateTime.utc(2026, 4, 25),
      accounts: [card],
      categories: [],
      entries: [split, charge('b', DateTime.utc(2026, 4, 25))],
      holdings: const [],
      budgets: const [],
      recurring: const [],
    );
    expect(
      ledger.statementService.billedPeriods(split, DateTime.utc(2026, 3, 24)),
      0,
    );
    expect(
      ledger.statementService.billedPeriods(split, DateTime.utc(2026, 3, 25)),
      1,
    );
    // Today's close is still open: the last statement closed on 3/25.
    final (start, end, _) = ledger.statementService.statement(card);
    expect(start, DateTime.utc(2026, 2, 26));
    expect(end, DateTime.utc(2026, 3, 25));
    expect(
      [for (final e in ledger.statementService.unbilled(card)) e.id],
      ['b'],
    );
  });

  test('past net worth counts only the shares then held', () {
    final bank = Account('bank', '銀行', AccountKind.bank, 100000);
    final buy = Entry(
      id: 'buy',
      date: DateTime.utc(2026, 4, 25),
      type: EntryType.buy,
      amount: 10000,
      account: 'bank',
      category: '投資',
      holding: '2330',
      shares: 1000,
      fee: 20,
    );
    final ledger = Ledger(
      today: DateTime.utc(2026, 4, 25),
      accounts: [bank],
      categories: [],
      entries: [buy],
      holdings: const [],
      budgets: const [],
      recurring: const [],
    );
    expect(ledger.balanceService.netWorthAt(DateTime.utc(2026, 4, 24)), 100000);
    expect(
      ledger.balanceService.netWorthAt(DateTime.utc(2026, 4, 25)),
      100000 - 20,
    );
    expect(ledger.entries.onDay(DateTime.utc(2026, 4, 25)), [buy]);
    expect(ledger.entries.onDay(DateTime.utc(2026, 4, 24)), isEmpty);
  });
}
