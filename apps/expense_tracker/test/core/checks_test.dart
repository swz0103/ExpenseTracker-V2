import 'package:expense_tracker/src/core/ledger/checks.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final day = DateTime.utc(2026, 4, 25);
  Ledger book(List<Entry> entries) => Ledger(
    today: day,
    accounts: const [
      Account('bank', '銀行', AccountKind.bank, 100000),
      Account('usd', '美元', AccountKind.bank, 0, currency: 'USD'),
      Account('card', '卡', AccountKind.card, 0, closingDay: 25),
    ],
    categories: const [],
    entries: entries,
    holdings: const [],
    budgets: const [],
    recurring: const [],
  );
  Entry entry(
    EntryType type,
    int amount, {
    String id = 'e',
    String account = 'bank',
    String? to,
    String? holding,
    int shares = 0,
    int? home,
    String? refundOf,
  }) => Entry(
    id: id,
    date: day,
    type: type,
    amount: amount,
    account: account,
    category: '其他支出',
    to: to,
    holding: holding,
    shares: shares,
    home: home,
    refundOf: refundOf,
  );

  test('the ledger says why an entry cannot be kept', () {
    final ledger = book(const []);
    expect(ledger.problemWith(entry(EntryType.expense, 0)), '請輸入金額');
    expect(ledger.problemWith(entry(EntryType.expense, 120)), isNull);
    expect(
      ledger.problemWith(entry(EntryType.transfer, 50, to: 'bank')),
      '轉出與轉入不能是同一個帳戶',
    );
    expect(
      ledger.problemWith(entry(EntryType.expense, 500, account: 'usd')),
      '還沒有匯率，請輸入折合台幣的金額',
    );
    expect(
      ledger.problemWith(
        entry(EntryType.expense, 500, account: 'usd', home: 160),
      ),
      isNull,
    );
    expect(
      ledger.problemWith(entry(EntryType.buy, 1000, holding: '2330')),
      '請輸入股數',
    );
    expect(ledger.problemWith(entry(EntryType.buy, 1000)), '請選擇投資標的');
  });

  test('a refund can give back what is left, its own amount included', () {
    final bought = entry(EntryType.expense, 900, id: 'bought');
    final back = entry(EntryType.income, 600, id: 'back', refundOf: 'bought');
    final ledger = book([bought, back]);
    final more = entry(EntryType.income, 400, id: 'more', refundOf: 'bought');
    expect(ledger.problemWith(more), '超過可退金額 300');
    final edited = entry(EntryType.income, 900, id: 'back', refundOf: 'bought');
    expect(ledger.problemWith(edited, replacing: back), isNull);
  });
}
