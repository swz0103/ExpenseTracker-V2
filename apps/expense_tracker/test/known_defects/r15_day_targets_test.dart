// Review round 15: the day cells of the week strip and of the recurring
// calendar are seven across, so on a phone narrower than about 376 dp each
// is narrower than Android's 48 dp. Whether to scroll them sideways or to
// let a seventh of the screen be the target is the owner's choice.
import 'package:flutter_test/flutter_test.dart';

import '../support/places.dart';
import 'known_defect.dart';

void main() {
  setUpAll(loadFonts);

  for (final (name, taps) in const [
    ('the week strip of 總覽', <String>[]),
    ('the recurring calendar', ['更多', '定期交易']),
  ]) {
    testWidgets('DAY-01: $name has 48 dp wide day cells at 360 dp', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await show(tester, 360, 1, height: 2600);
      await go(tester, taps);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      semantics.dispose();
    }, skip: knownDefect('DAY-01', '待決定') != null);
  }
}
