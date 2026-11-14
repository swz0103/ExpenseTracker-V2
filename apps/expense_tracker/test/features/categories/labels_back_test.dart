import 'package:flutter_test/flutter_test.dart';

import '../../app/places.dart';

void main() {
  setUpAll(loadFonts);

  testWidgets('back from a merchant returns to 商家, not 標籤', (tester) async {
    await show(tester, 390, 1);
    await go(tester, ['更多', '標籤與商家']);
    expect(find.textContaining('星巴克'), findsNothing, reason: 'on 標籤');
    await go(tester, ['商家', '星巴克']);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('標籤與商家'), findsOneWidget);
    expect(find.textContaining('星巴克'), findsWidgets);
    // From 更多 again it opens on 標籤.
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    await go(tester, ['標籤與商家']);
    expect(find.textContaining('星巴克'), findsNothing);
  });
}
