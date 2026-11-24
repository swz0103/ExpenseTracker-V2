// Merging categories (D60): the budget goes along, the subcategories
// follow, and the command itself refuses a merge no form should offer.
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../baseline/baseline_ledger.dart';

void main() {
  Ledger book({List<Budget> budgets = const []}) => ledgerOf(
    today: day(2026, 10, 4),
    categories: [
      Category('飲食', 'food', 0xFF111111),
      Category('交通', 'car', 0xFF222222),
      Category('早餐', 'food', 0xFF555555, parent: '飲食'),
      Category('薪水', 'salary', 0xFF333333, income: true),
      Category('舊分類', 'other', 0xFF444444, archived: true),
    ],
    budgets: budgets,
    entries: [
      entryOf(
        'x',
        day(2026, 10, 1),
        EntryType.expense,
        300,
        'bank',
        category: '飲食',
      ),
    ],
  );

  group('a merge', () {
    test('moves the budget when the target has none', () {
      final l = book(budgets: const [Budget('飲食', 5000)]);
      expect(l.categoryCommands.mergeCategory('飲食', '交通'), isA<Merged>());
      expect(l.budgets.forCategory('交通').limit, 5000);
      expect(l.budgets.all.any((b) => b.category == '飲食'), isFalse);
      expect(l.entries.byId('x')!.category, '交通');
    });

    test('adds the limits when both have one, the target\'s settings kept', () {
      final l = book(
        budgets: const [
          Budget('飲食', 5000),
          Budget('交通', 2000, warning: 90, carry: true),
        ],
      );
      l.categoryCommands.mergeCategory('飲食', '交通');
      final b = l.budgets.forCategory('交通');
      // 5000 + 2000 = 7000.
      expect((b.limit, b.warning, b.carry), (7000, 90, true));
    });

    test('a subcategory merged into its own parent adds no limit (D103)', () {
      final l = book(budgets: const [Budget('飲食', 5000), Budget('早餐', 1500)]);
      expect(l.categoryCommands.mergeCategory('早餐', '飲食'), isA<Merged>());
      // 飲食's 5000 already counted 早餐's spending: still 5000.
      expect(l.budgets.forCategory('飲食').limit, 5000);
      expect(l.budgets.all.any((b) => b.category == '早餐'), isFalse);
    });

    test('the merged budget starts with the earlier of the two (D103)', () {
      final l = book(
        budgets: [
          Budget('飲食', 5000, since: day(2026, 3, 1)),
          Budget('交通', 2000, since: day(2026, 7, 1)),
        ],
      );
      l.categoryCommands.mergeCategory('飲食', '交通');
      expect(l.budgets.forCategory('交通').since, day(2026, 3, 1));
      // One with no start counts from the first month: none is earlier.
      final open = book(
        budgets: [
          const Budget('飲食', 5000),
          Budget('交通', 2000, since: day(2026, 7, 1)),
        ],
      );
      open.categoryCommands.mergeCategory('飲食', '交通');
      expect(open.budgets.forCategory('交通').since, isNull);
    });

    test('puts the subcategories under the target', () {
      final l = book();
      l.categoryCommands.mergeCategory('飲食', '交通');
      expect(l.category('早餐').parent, '交通');
    });
  });

  group('the command refuses, changing nothing', () {
    for (final (into, reason) in [
      ('薪水', MergeRefusal.otherSide),
      ('不存在', MergeRefusal.missing),
      ('舊分類', MergeRefusal.archived),
      ('飲食', MergeRefusal.same),
      ('早餐', MergeRefusal.intoOwnSubcategory),
    ]) {
      test('飲食 into $into: ${reason.name}', () {
        final l = book(budgets: const [Budget('飲食', 5000)]);
        final result = l.categoryCommands.mergeCategory('飲食', into);
        expect((result as MergeRefused).reason, reason);
        expect(l.entries.byId('x')!.category, '飲食');
        expect(l.budgets.forCategory('飲食').limit, 5000);
        expect(l.categories.all.any((c) => c.name == '飲食'), isTrue);
      });
    }
  });
}
