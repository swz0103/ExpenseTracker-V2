import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/features/entries/model/entry_details.dart';
import 'package:flutter_test/flutter_test.dart';

Ledger _book() => Ledger(
  today: DateTime.utc(2026, 10, 4),
  accounts: const [
    Account('bank', '銀行', AccountKind.bank, 0),
    Account('usd', '美元', AccountKind.bank, 0, currency: 'USD'),
  ],
  categories: const [],
  entries: const [],
  holdings: const [],
  budgets: const [],
  recurring: const [],
);

Entry _entry({
  EntryType type = EntryType.expense,
  String to = '',
  int? received,
  int? home,
  String note = '',
  String merchant = '',
  List<String> tags = const [],
  int installments = 1,
}) => Entry(
  id: 'e',
  date: DateTime.utc(2026, 10, 4),
  type: type,
  amount: 1000,
  account: 'bank',
  to: to.isEmpty ? null : to,
  received: received,
  home: home,
  note: note,
  merchant: merchant,
  tags: tags,
  installments: installments,
  category: '餐飲',
);

void main() {
  test('money out is −, money in is +, a transfer has no sign', () {
    expect(entrySign(EntryType.expense), '−');
    expect(entrySign(EntryType.buy), '−');
    expect(entrySign(EntryType.income), '+');
    expect(entrySign(EntryType.dividend), '+');
    expect(entrySign(EntryType.transfer), '');
  });

  test('a transfer is called by both accounts', () {
    final l = _book();
    expect(
      entryTitle(l.accounts, _entry(type: EntryType.transfer, to: 'usd')),
      '銀行 → 美元',
    );
    // Otherwise its title: the note, or the category without one.
    expect(entryTitle(l.accounts, _entry()), '餐飲');
    expect(entryTitle(l.accounts, _entry(note: '午餐')), '午餐');
  });

  test('only what was written shows, in order', () {
    final l = _book();
    final plain = entryDetails(l.accounts, _entry(), '餐飲', today: l.today);
    expect([for (final (k, _) in plain) k], ['帳戶', '日期']);
    final full = entryDetails(
      l.accounts,
      _entry(merchant: '便當店', tags: ['家用'], installments: 3, note: '同事'),
      // The note shows apart only where something else is the title.
      '銀行 → 美元',
      today: l.today,
    );
    expect(
      [for (final (k, _) in full) k],
      ['帳戶', '日期', '商家', '標籤', '分期', '備註'],
    );
    expect(full[3].$2, '#家用');
  });

  test('a note that only repeats the title is left out', () {
    final l = _book();
    final details = entryDetails(
      l.accounts,
      _entry(note: '午餐'),
      '午餐',
      today: l.today,
    );
    expect(details.any((d) => d.$1 == '備註'), isFalse);
  });

  test('a transfer into another currency shows what arrived in it', () {
    final l = _book();
    final details = entryDetails(
      l.accounts,
      _entry(type: EntryType.transfer, to: 'usd', received: 3150, home: 1000),
      '銀行 → 美元',
      today: l.today,
    );
    expect(details.where((d) => d.$1 == '帳戶'), isEmpty);
    expect(details, contains(('轉入金額', 'USD 31.50')));
    expect(details, contains(('折合新台幣', '1,000')));
  });
}
