import 'package:expense_tracker/src/app/demo/seed.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/places.dart';

void main() {
  setUpAll(loadFonts);

  // With another month shown, 回到本月 joins the two step buttons: on a
  // narrow phone, or with large text, they go under the month rather than
  // past the edge (7.2 px over at 360 dp in review 10, 81 px at 200%).
  for (final (width, text) in [
    (320.0, 1.0),
    (360.0, 1.0),
    (360.0, 1.3),
    (360.0, 1.5),
    (360.0, 2.0),
    (412.0, 2.0),
  ]) {
    testWidgets('another month shown fits ${width.toInt()} dp at '
        '${(text * 100).round()}%', (tester) async {
      await show(tester, width, text, height: 800, book: demoLedger());
      await go(tester, ['更多', '預算管理', '~上個月']);
      expect(tester.takeException(), isNull);
      expect(find.text('回到本月'), findsOneWidget);
      // Back to this month: the button goes, the month row is one line.
      await go(tester, ['回到本月']);
      expect(tester.takeException(), isNull);
      expect(find.text('回到本月'), findsNothing);
    });
  }
}
