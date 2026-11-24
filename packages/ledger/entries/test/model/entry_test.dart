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
      expect(split.amountParts, [('食', 600), ('衣', 400)]);
    });
    test('by category in its own currency: a foreign split goes whole', () {
      final split = _entry(
        EntryType.expense,
        home: 320,
        parts: [('食', 600), ('衣', 400)],
      );
      // The 1,000 cents go whole under the category, worth NT$320.
      expect(split.amountParts, [(split.category, 1000)]);
      expect(split.spendingParts, [(split.category, 320)]);
      expect(_entry(EntryType.expense).amountParts, [
        (_entry(EntryType.expense).category, 1000),
      ]);
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

  test('a mark is kept through a copy (D52)', () {
    final e = Entry(
      id: 'r',
      date: _day,
      type: EntryType.income,
      amount: 40,
      account: 'card',
      mark: EntryMark.reward,
    );
    expect(e.withId('s').mark, EntryMark.reward);
    expect(e.withLabels(tags: const ['獎勵']).mark, EntryMark.reward);
    expect(e.inGroup('g').mark, EntryMark.reward);
  });

  test('what arrived is what was received, else the amount '
      '(mutation review 11)', () {
    Entry transfer({int? received}) => Entry(
      id: 't',
      date: DateTime.utc(2026, 10, 4),
      type: EntryType.transfer,
      amount: 3200,
      account: 'bank',
      to: 'usd',
      received: received,
    );
    expect(transfer(received: 100).arrived, 100);
    expect(transfer().arrived, 3200);
  });

  test('a capital reduction settles its whole amount, a dividend less the '
      'premium (mutation review 11)', () {
    Entry dividend(int shares) => Entry(
      id: 'd',
      date: DateTime.utc(2026, 10, 4),
      type: EntryType.dividend,
      amount: 5000,
      tax: 100,
      account: 'bank',
      holding: '2330',
      shares: shares,
    );
    // 5,000 back on a reduction; 5,000 - 100 on a dividend.
    expect(dividend(-1000).settlement, 5000);
    expect(dividend(0).settlement, 4900);
  });
}
