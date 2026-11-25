import 'package:expense_tracker/src/core/ledger/commands/undo.dart';
import 'package:expense_tracker/src/core/ledger/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// D82: what a change did to entries, noted so that its undo puts back
/// only those still as the change left them.
void main() {
  Entry lunch(String category) => Entry(
    id: 'lunch',
    date: DateTime.utc(2026, 10, 1),
    type: EntryType.expense,
    amount: 120,
    account: 'bank',
    category: category,
  );

  test('notes each entry a change makes, and gives back the one before', () {
    final images = EntryImages();
    expect(images.isEmpty, isTrue);
    final was = lunch('飲食');
    final change = images.noting((e) => e.withCategory('外食'));
    final made = change(was)!;
    expect(images.isEmpty, isFalse);
    expect(images.back(made), same(was));
  });

  test('leaves alone an entry changed again since, or never changed', () {
    final images = EntryImages();
    final was = lunch('飲食');
    images.noting((e) => e.withCategory('外食'))(was);
    expect(images.back(lunch('外食')), isNull);
    expect(images.back(was), isNull);
  });

  test('notes nothing for an entry the change passes over', () {
    final images = EntryImages();
    expect(images.noting((_) => null)(lunch('飲食')), isNull);
    expect(images.isEmpty, isTrue);
  });
}
