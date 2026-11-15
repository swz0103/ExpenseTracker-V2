import 'package:expense_tracker/src/core/look/keys.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../app/places.dart';

void main() {
  setUpAll(loadFonts);

  testWidgets('opening and closing a split or the fold leaves no room '
      'under the form, there or the next times it opens', (tester) async {
    await show(tester, 360, 1, height: 900);
    Future<void> settle() async {
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
    }

    Finder split() =>
        find.text('拆分').evaluate().isEmpty ? find.text('拆分中') : find.text('拆分');
    // From the category strip down to the button at the sheet's foot.
    double foot() =>
        tester.getTopLeft(find.text('記下支出').last).dy -
        tester.getTopLeft(split()).dy;

    await go(tester, ['~記一筆']);
    await settle();
    final before = foot();
    for (var round = 0; round < 3; round++) {
      await tester.tap(split());
      await settle();
      await tester.tap(split());
      await settle();
      await tester.tap(find.byKey(Keys.extras));
      await settle();
      await tester.tap(find.byKey(Keys.extras));
      await settle();
      expect(foot(), closeTo(before, 1), reason: 'round $round');
      // Closed and opened again.
      await tester.tapAt(const Offset(180, 20));
      await settle();
      await go(tester, ['~記一筆']);
      await settle();
      expect(foot(), closeTo(before, 1), reason: 'reopened $round');
    }
  });
}
