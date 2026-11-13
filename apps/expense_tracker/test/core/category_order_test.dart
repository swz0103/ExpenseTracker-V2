import 'package:expense_tracker/src/app/demo/seed.dart';
import 'package:flutter_test/flutter_test.dart';

/// 分類's long press and drag: the order kept is the order offered to
/// the composer, and an edit keeps the category where it was put.
void main() {
  test('categories keep the order they were dragged to', () {
    final ledger = demoLedger();
    final names = [for (final c in ledger.categoriesFor(income: false)) c.name];
    final reversed = names.reversed.toList();
    ledger.placeCategories(reversed);
    expect([
      for (final c in ledger.categoriesFor(income: false)) c.name,
    ], reversed);

    final last = ledger.category(reversed.first);
    ledger.updateCategory(last.name, last.copyWith(name: '${last.name}２'));
    expect(ledger.categoriesFor(income: false).first.name, '${last.name}２');
  });
}
