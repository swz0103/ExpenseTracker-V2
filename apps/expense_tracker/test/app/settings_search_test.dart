import 'package:expense_tracker/src/app/settings_search.dart';
import 'package:expense_tracker/src/core/navigation/nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/places.dart';

/// A setting four taps away, found by typing a word of it.
void main() {
  test('a setting is found by its name or another word for it', () {
    expect([for (final t in findSettings('震動')) t.name], ['震動']);
    expect(
      [for (final t in findSettings('截圖')) t.page],
      [SettingsDestination.security],
    );
    expect([for (final t in findSettings('深色')) t.name], ['外觀']);
    // The lock's own settings, each on the page that has it (F39, SEC-07).
    expect(
      [for (final t in findSettings('指紋')) (t.name, t.page)],
      [('生物辨識解鎖', SettingsDestination.security)],
    );
    expect(
      [for (final t in findSettings('上鎖')) (t.name, t.page)],
      [('自動上鎖', SettingsDestination.security)],
    );
    expect([for (final t in findSettings('離開')) t.name], ['自動上鎖']);
    expect([for (final t in findSettings('google')) t.name], ['雲端硬碟備份']);
    expect(findSettings('  '), isEmpty);
    expect(findSettings('不存在的設定'), isEmpty);
  });

  test('every page of the settings has something to find', () {
    expect({
      for (final t in settingTopics) t.page,
    }, SettingsDestination.values.toSet());
  });

  testWidgets('typing shows the settings found; one opens its page', (
    tester,
  ) async {
    await loadFonts();
    await show(tester, 360, 1);
    await go(tester, ['更多', '設定']);
    await tester.enterText(find.byType(TextField).first, '震動');
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('震動，在外觀與操作'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('震動，在外觀與操作'));
    await tester.pumpAndSettle();
    expect(find.text('外觀與操作'), findsWidgets);
    expect(find.text('標準'), findsOneWidget, reason: 'the 震動 card');

    await go(tester, []);
    await show(tester, 360, 1);
    await go(tester, ['更多', '設定']);
    await tester.enterText(find.byType(TextField).first, '沒有這個');
    await tester.pumpAndSettle();
    expect(find.text('找不到這個設定'), findsOneWidget);
  });
}
