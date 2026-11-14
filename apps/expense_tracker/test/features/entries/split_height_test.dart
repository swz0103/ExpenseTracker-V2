import 'package:flutter_test/flutter_test.dart';

import '../../app/places.dart';

void main() {
  setUpAll(loadFonts);

  testWidgets('splitting and closing it again leaves no room under the '
      'form, there or the next time it opens', (tester) async {
    await show(tester, 360, 1, height: 900);
    await go(tester, ['~記一筆']);
    // From the top of the sheet, at the amount, to the button at its
    // foot.
    double foot() =>
        tester.getTopLeft(find.text('記下支出').last).dy -
        tester
            .getTopLeft(
              find.text('拆分').evaluate().isEmpty
                  ? find.text('拆分中')
                  : find.text('拆分'),
            )
            .dy;
    final before = foot();
    await tester.tap(find.text('拆分'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('拆分中'));
    await tester.pumpAndSettle();
    expect(foot(), closeTo(before, 1));
    // Closed and opened again.
    await tester.tapAt(const Offset(180, 20));
    await tester.pumpAndSettle();
    await go(tester, ['~記一筆']);
    expect(foot(), closeTo(before, 1));
  });
}
