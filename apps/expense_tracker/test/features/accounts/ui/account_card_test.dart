import 'package:expense_tracker/src/core/ledger/persistence/ledger_data_source.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/features/accounts/ui/account_card.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Batches implements LedgerDataSource {
  @override
  Future<void> keep(WriteBatch batch) async {}

  @override
  Future<Ledger> load() => throw UnimplementedError();
}

void main() {
  final day = DateTime.utc(2026, 11, 10);
  const bank = Account('bank', '銀行', AccountKind.bank, 100000);

  Entry move(String id, String to, int amount, {int fee = 0}) => Entry(
    id: id,
    date: day,
    type: EntryType.transfer,
    amount: amount,
    account: 'bank',
    category: transferCategory,
    to: to,
    fee: fee,
  );

  test('D20: 本月支出 counts spending as the reports do, not money moved', () {
    final ledger = Ledger(
      today: day,
      accounts: const [
        bank,
        Account('cash', '現金', AccountKind.cash, 0),
        Account('card', '信用卡', AccountKind.card, 0, closingDay: 5, dueDay: 20),
        Account('amy', '小美', AccountKind.receivable, 0),
      ],
      categories: [Category('飲食', 'food', 0xFF5C9A83)],
      entries: [
        Entry(
          id: 'lunch',
          date: day,
          type: EntryType.expense,
          amount: 1000,
          account: 'bank',
          category: '飲食',
        ),
        Entry(
          id: 'back',
          date: day,
          type: EntryType.income,
          amount: 200,
          account: 'bank',
          category: '飲食',
          refundOf: 'lunch',
        ),
        // A card payment, money lent and a move to cash with its fee.
        move('pay', 'card', 5000),
        move('lend', 'amy', 300),
        move('atm', 'cash', 400, fee: 15),
        // Last month's spending is not this month's.
        Entry(
          id: 'old',
          date: DateTime.utc(2026, 10, 31),
          type: EntryType.expense,
          amount: 70,
          account: 'bank',
          category: '飲食',
        ),
      ],
      holdings: const [],
      budgets: const [],
      recurring: const [],
      dataSource: _Batches(),
    );
    // 1000 spent - 200 refunded + 15 transfer fee = 815; the 5,000 paid
    // to the card, the 300 lent and the 400 moved are not spending.
    expect(spentThisMonth(ledger, bank), 815);
    expect(ledger.reportService.expense(2026, 11, account: 'cash'), 0);
    // The month's whole spending is the same sum: one account spent it.
    expect(ledger.reportService.expense(2026, 11), 815);
  });
}
