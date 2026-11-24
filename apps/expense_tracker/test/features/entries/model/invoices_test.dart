import 'package:expense_tracker/src/app/demo/seed.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/features/entries/model/invoices.dart';
import 'package:flutter_test/flutter_test.dart';

/// A merchant's category and an invoice already kept, as an entry typed,
/// scanned or imported finds them.
void main() {
  test('a merchant takes the category the book used last, else the one '
      'its name hints at, else 其他支出', () {
    final ledger = demoLedger();
    final queries = ledger.entryQueryService;
    final known = ledger.entries.all.firstWhere((e) => e.merchant.isNotEmpty);
    expect(
      guessCategory(queries, ledger.categories, known.merchant, ''),
      ledger.category(known.category).name,
    );
    expect(guessCategory(queries, ledger.categories, '台塑石油 某某站', ''), '交通通勤');
    expect(
      guessCategory(queries, ledger.categories, '某間小店', '貼紙'),
      feeCategory,
    );
  });

  test('an invoice is in the book once its number is in a note', () {
    final ledger = demoLedger();
    final day = DateTime.utc(2026, 10, 3);
    expect(invoiceRecorded(ledger.entries, day, 'AB12345678'), isFalse);
    ledger.entryCommands.add(
      Entry(
        id: ledger.newId(),
        date: day,
        type: EntryType.expense,
        amount: 85,
        account: ledger.accounts.all.first.id,
        category: ledger.categories.forEntries(income: false).first.name,
        note: '發票 AB12345678',
      ),
    );
    expect(invoiceRecorded(ledger.entries, day, 'AB12345678'), isTrue);
    // Another month is not looked at.
    expect(
      invoiceRecorded(ledger.entries, DateTime.utc(2026, 9, 3), 'AB12345678'),
      isFalse,
    );
  });

  test('R12: an invoice number is found as a word of its own', () {
    expect(notesInvoice('鮮奶 發票 AB12', 'AB12'), isTrue);
    expect(notesInvoice('鮮奶 發票 AB12', 'AB1'), isFalse);
    expect(notesInvoice('發票 XAB1', 'AB1'), isFalse);
    expect(notesInvoice('AB1，已付', 'AB1'), isTrue);
    expect(notesInvoice('發票 AB1', ''), isFalse);
  });

  test('one pair writes and reads an invoice\'s note (r13 F6)', () {
    final note = invoiceNote(['拿鐵', '可頌'], 'AB12345678');
    expect(note, '拿鐵 等 2 項 發票 AB12345678');
    expect(invoiceNumberIn(note), 'AB12345678');
    expect(invoiceNote(const [], 'AB12345678'), '發票 AB12345678');
    expect(invoiceNumberIn('發票 AB12345678 · 賣方 1'), 'AB12345678');
    // A note that names none: edited, or never an invoice's.
    expect(invoiceNumberIn('午餐'), isNull);
    expect(invoiceNumberIn('電子發票'), isNull);
  });
}
