import 'package:expense_tracker/src/core/design_system/keys.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/places.dart';
import '../../../support/seeded_book.dart' show emptyBook;

/// D117: the recurring editor asks 要捨棄修改嗎？ only when a value differs
/// from the one it opened with, not because something was opened or
/// chosen and taken back.
void main() {
  // Today 2026-10-31: 健身房 falls due on the 2nd of every month.
  Ledger gym() => emptyBook(
    recurring: [
      const Recurring(
        id: 'gym',
        name: '健身房',
        amount: 800,
        day: 2,
        account: 'bank',
        category: '娛樂',
      ),
    ],
  );

  bool asked() => find.text('要捨棄修改嗎？').evaluate().isNotEmpty;

  Finder nameField() => find.byWidgetPredicate(
    (w) => w is EditableText && w.controller.text.startsWith('健身房'),
  );

  testWidgets('the 重複 sheet opened and closed as it was leaves on 取消 '
      'without asking', (tester) async {
    await show(tester, 360, 1, book: gym());
    await go(tester, ['更多', '定期交易', '~管理', '健身房', '^每月 2 日']);
    // Back closes the 重複 sheet, nothing chosen.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(nameField(), findsOneWidget);
    await tester.tap(find.byKey(Keys.cancelEdit));
    await tester.pumpAndSettle();
    expect(asked(), isFalse);
    expect(nameField(), findsNothing);
  });

  testWidgets('a name typed and typed back is no change; one left changed '
      'asks', (tester) async {
    await show(tester, 360, 1, book: gym());
    await go(tester, ['更多', '定期交易', '~管理', '健身房']);
    await tester.enterText(nameField(), '健身房月費');
    await tester.pumpAndSettle();
    await tester.enterText(nameField(), '健身房');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Keys.cancelEdit));
    await tester.pumpAndSettle();
    expect(asked(), isFalse);

    await go(tester, ['健身房']);
    await tester.enterText(nameField(), '健身房月費');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Keys.cancelEdit));
    await tester.pumpAndSettle();
    expect(asked(), isTrue);
  });
}
