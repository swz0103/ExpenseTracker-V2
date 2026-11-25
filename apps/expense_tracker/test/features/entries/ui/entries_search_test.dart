import 'package:expense_tracker/src/features/entries/ui/entries_filter_sheet.dart';
import 'package:expense_tracker/src/features/entries/ui/entries_search.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The filters on, as pills under the search: one for each, and its ✕
/// takes only that one off.
void main() {
  testWidgets('a pill for each filter on; its ✕ takes that one off', (
    tester,
  ) async {
    var filter = const EntryFilter(
      kind: KindFilter.expense,
      account: 'bank',
      category: '飲食日常',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => EntriesFilterPills(
              filter: filter,
              accountName: filter.account == null ? null : '日常銀行',
              onChange: (change) => setState(() => filter = change(filter)),
            ),
          ),
        ),
      ),
    );
    expect(find.text('日常銀行'), findsOneWidget);
    expect(find.text('飲食日常'), findsOneWidget);
    expect(find.text(KindFilter.expense.label), findsOneWidget);

    // The pills come in order: kind, account, category.
    await tester.tap(find.bySemanticsLabel('清除這個篩選').at(1));
    await tester.pump();
    expect(filter.account, isNull);
    expect(filter.category, '飲食日常', reason: 'only that one is taken off');
    expect(filter.kind, KindFilter.expense);
    expect(find.text('日常銀行'), findsNothing);
  });

  testWidgets('no filter on, no pill', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EntriesFilterPills(
            filter: const EntryFilter(),
            accountName: null,
            onChange: (_) {},
          ),
        ),
      ),
    );
    expect(find.bySemanticsLabel('清除這個篩選'), findsNothing);
  });
}
