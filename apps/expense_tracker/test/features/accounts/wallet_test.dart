import 'package:flutter_test/flutter_test.dart';

import '../../app/places.dart';

void main() {
  setUpAll(loadFonts);

  testWidgets('held and moved up, the cards turn through the front, and '
      'the one in front when let go stays', (tester) async {
    await show(tester, 360, 1, height: 1400);
    await go(tester, ['帳戶']);
    final before = tester.getTopLeft(find.text('日常信用卡')).dy;
    final start = tester.getCenter(find.text('日常信用卡'));
    final hold = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 700));
    for (var i = 0; i < 6; i++) {
      await hold.moveBy(const Offset(0, -15));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await hold.up();
    await tester.pumpAndSettle();
    // The card that was in front has moved up into the stack.
    expect(tester.getTopLeft(find.text('日常信用卡')).dy, lessThan(before));
  });
}
