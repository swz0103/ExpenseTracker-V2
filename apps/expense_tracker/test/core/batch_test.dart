import 'package:expense_tracker/src/app/demo/seed.dart';
import 'package:expense_tracker/src/core/ledger/batch.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a batch recategorises only plain entries of the same kind', () {
    final ledger = demoLedger();
    final month = ledger.entriesIn(ledger.today.year, ledger.today.month);
    final picked = month.take(8).toList();
    final fits = [
      for (final e in picked)
        if (e.type == EntryType.expense &&
            !e.isRefund &&
            e.parts.isEmpty &&
            e.category != '居家生活')
          e,
    ];
    final before = ledger.expense(ledger.today.year, ledger.today.month);
    expect(ledger.recategorize(picked, '居家生活'), fits.length);
    expect(ledger.expense(ledger.today.year, ledger.today.month), before);
    for (final e in fits) {
      final now = ledger.entries.firstWhere(
        (x) => x.date == e.date && x.amount == e.amount && x.note == e.note,
      );
      expect(now.category, '居家生活');
    }
  });

  test('a batch moves spending between accounts of one currency', () {
    final ledger = demoLedger();
    final spent = [
      for (final e in ledger.entriesIn(ledger.today.year, ledger.today.month))
        if (e.type == EntryType.expense &&
            e.account == 'bank' &&
            e.installments == 0 &&
            !e.isRefund &&
            ledger.refundable(e) == e.amount)
          e,
    ];
    expect(spent, isNotEmpty);
    final bank = ledger.balance('bank');
    final cash = ledger.balance('cash');
    final total = spent.fold(0, (sum, e) => sum + e.amount);
    expect(ledger.moveToAccount(spent, 'cash'), spent.length);
    expect(ledger.balance('bank'), bank + total);
    expect(ledger.balance('cash'), cash - total);
  });
}
