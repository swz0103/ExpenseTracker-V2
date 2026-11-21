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
}
