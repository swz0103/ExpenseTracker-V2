import 'package:expense_tracker/src/demo/seed.dart';
import 'package:expense_tracker/src/model/entry_json.dart';
import 'package:expense_tracker/src/model/ledger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a deleted entry waits in the trash and comes back as new', () {
    final ledger = demoLedger();
    final entry = ledger.entries.firstWhere(
      (e) => e.type == EntryType.expense && e.recurring == null,
    );
    final count = ledger.entries.length;
    final removed = ledger.remove(entry.id)!;
    expect(ledger.trash.single.entry, same(removed.$2));
    expect(ledger.trash.single.on, ledger.today);

    ledger.restoreTrashed(ledger.trash.single);
    expect(ledger.trash, isEmpty);
    expect(ledger.entries, hasLength(count));
    final back = ledger.entries.last;
    expect(back.id, isNot(entry.id));
    expect((back.amount, back.account, back.date), (
      entry.amount,
      entry.account,
      entry.date,
    ));
  });

  test('an undone delete leaves the trash', () {
    final ledger = demoLedger();
    final entry = ledger.entries.firstWhere(
      (e) => e.type == EntryType.expense,
    );
    final removed = ledger.remove(entry.id)!;
    ledger.restore(removed);
    expect(ledger.trash, isEmpty);
  });

  test('every field of an entry survives its JSON', () {
    final entry = Entry(
      id: 'a1',
      date: DateTime.utc(2026, 10, 3),
      type: EntryType.expense,
      amount: 1250,
      account: 'card',
      category: '飲食日常',
      note: '聚餐',
      merchant: '好市多',
      tags: const ['家用', '旅遊'],
      parts: const [('飲食日常', 1000), ('居家生活', 250)],
      fee: 3,
      installments: 3,
      home: 1250,
    );
    final back = entryFromJson(entryToJson(entry));
    expect(entryToJson(back), entryToJson(entry));
    expect(back.parts, entry.parts);
    final trade = Entry(
      id: 'b2',
      date: DateTime.utc(2026, 9, 12),
      type: EntryType.sell,
      amount: 33500,
      account: 'bank',
      to: 'x',
      holding: '0050',
      shares: -500,
      tax: 33,
      refundOf: 'r',
      average: true,
      split: true,
      received: 7,
    );
    expect(entryToJson(entryFromJson(entryToJson(trade))), entryToJson(trade));
  });
}
