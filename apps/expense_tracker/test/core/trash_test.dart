import 'package:expense_tracker/src/app/demo/seed.dart';
import 'package:expense_tracker/src/core/ledger/persistence/codec/record_json.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a deleted entry waits in the trash and comes back as it was', () {
    final ledger = demoLedger();
    final entry = ledger.entries.all.firstWhere(
      (e) => e.type == EntryType.expense && e.recurring == null,
    );
    final count = ledger.entries.length;
    final removed = ledger.entryCommands.remove(entry.id)!;
    expect(ledger.trash.all.single.entry, same(removed.$2));
    expect(ledger.trash.all.single.on, ledger.today);

    ledger.entryCommands.restoreTrashed(ledger.trash.all.single);
    expect(ledger.trash.all, isEmpty);
    expect(ledger.entries.all, hasLength(count));
    final back = ledger.entries.all.last;
    expect(back.id, entry.id);
    expect(
      (back.amount, back.account, back.date),
      (entry.amount, entry.account, entry.date),
    );
  });

  test('an undone delete leaves the trash', () {
    final ledger = demoLedger();
    final entry = ledger.entries.all.firstWhere(
      (e) => e.type == EntryType.expense,
    );
    final removed = ledger.entryCommands.remove(entry.id)!;
    ledger.entryCommands.restore(removed);
    expect(ledger.trash.all, isEmpty);
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
      recurring: 'rent',
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
