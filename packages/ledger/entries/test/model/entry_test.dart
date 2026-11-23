import 'package:ledger_entries/model.dart';
import 'package:test/test.dart';

final _day = DateTime.utc(2026, 10, 4);

Entry _entry(
  EntryType type, {
  int amount = 1000,
  int fee = 0,
  int tax = 0,
  int shares = 0,
  int? home,
  String? refundOf,
  List<(String, int)> parts = const [],
}) => Entry(
  id: 'e',
  date: _day,
  type: type,
  amount: amount,
  account: 'bank',
  category: '餐飲',
  fee: fee,
  tax: tax,
  shares: shares,
  home: home,
  refundOf: refundOf,
  parts: parts,
);

void main() {
  group('spending', () {
    test('an expense counts its worth in NT\$', () {
      expect(_entry(EntryType.expense).spending, 1000);
      expect(_entry(EntryType.expense, home: 32).spending, 32);
    });
    test('a transfer counts only its fee, under 其他支出', () {
      final t = _entry(EntryType.transfer, fee: 15);
      expect(t.spending, 15);
      expect(t.spendingParts, [(feeCategory, 15)]);
    });
    test('a refund takes spending back', () {
      expect(_entry(EntryType.income, refundOf: 'x').spending, -1000);
      expect(_entry(EntryType.income, refundOf: 'x').earning, 0);
    });
    test('a split counts by its parts', () {
      final split = _entry(EntryType.expense, parts: [('食', 600), ('衣', 400)]);
      expect(split.spendingParts, [('食', 600), ('衣', 400)]);
    });
  });

  group('earning', () {
    test('a dividend earns what is left after the premium', () {
      // 1,000 − 21 = 979.
      expect(_entry(EntryType.dividend, tax: 21).earning, 979);
    });
    test('a reduction takes shares back and earns nothing', () {
      final r = _entry(EntryType.dividend, shares: -10);
      expect(r.isReduction, isTrue);
      expect(r.dividendNet, 0);
    });
  });

  group('changing', () {
    test('renaming a part merges it into one of the same name', () {
      // 600 + 400 = 1,000 under 食.
      final split = _entry(EntryType.expense, parts: [('食', 600), ('衣', 400)]);
      final merged = split.withCategory('食', from: '衣');
      expect(merged.parts, isEmpty);
      expect(merged.category, '食');
    });
    test('a group, an id and an amount of its own', () {
      final e = _entry(EntryType.expense).inGroup('g', id: 'f', amount: 1);
      expect((e.group, e.id, e.amount), ('g', 'f', 1));
      expect(e.withAccount('cash').account, 'cash');
      expect(e.withLabels(merchant: '全聯').merchant, '全聯');
      expect(e.withId('z').id, 'z');
      expect(e.title, '餐飲');
    });
  });
}
