import 'package:expense_tracker/src/app/platform_services.dart';
import 'package:expense_tracker/src/app/settings_search.dart';
import 'package:expense_tracker/src/core/design_system/findable.dart';
import 'package:shell/setting_topic.dart';
import 'package:expense_tracker/src/core/navigation/nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/places.dart';

/// A setting four taps away, found by typing a word of it.
void main() {
  test('a setting is found by its name or another word for it', () {
    expect([for (final t in findSettings('震動')) t.topic.name], ['震動']);
    expect(
      [for (final t in findSettings('截圖')) t.page],
      [SettingsDestination.security],
    );
    expect([for (final t in findSettings('深色')) t.topic.name], ['外觀']);
    // The lock's own settings, each on the page that has it (F39, SEC-07).
    expect(
      [for (final t in findSettings('指紋')) (t.topic.name, t.page)],
      [('生物辨識解鎖', SettingsDestination.security)],
    );
    expect(
      [for (final t in findSettings('上鎖')) (t.topic.name, t.page)],
      [('自動上鎖', SettingsDestination.security)],
    );
    expect([for (final t in findSettings('離開')) t.topic.name], ['自動上鎖']);
    expect([for (final t in findSettings('google')) t.topic.name], ['雲端硬碟備份']);
    expect(findSettings('  '), isEmpty);
    expect(findSettings('不存在的設定'), isEmpty);
  });

  test('券商手續費折扣 is found by 手續費, 折扣, 券商 and 股票, on 外觀與操作 '
      '(review 16: settings search keywords)', () {
    for (final word in ['手續費', '折扣', '券商', '股票']) {
      expect(
        [for (final t in findSettings(word)) (t.topic.name, t.page)],
        contains(('券商手續費折扣', SettingsDestination.appearance)),
        reason: word,
      );
    }
  });

  test('search offers only what this phone and build show: no updates '
      'outside the sideload build, no sample reset outside the preview, no '
      'fingerprint, lock or screen hiding without them (review 39 #4)', () {
    final offered = offeredTopics(const PlatformServices());
    for (final word in ['自動檢查', '範例', '指紋', '上鎖', '現在鎖上', '截圖', '日曆', '每日']) {
      expect(findSettings(word, among: offered), isEmpty, reason: word);
    }
    // 版本, 匯入 CSV and 最近刪除 are on every phone.
    expect(
      [for (final t in findSettings('版本', among: offered)) t.topic.name],
      ['版本與更新'],
    );
    expect([
      for (final t in findSettings('csv', among: offered)) t.topic.name,
    ], contains('匯入 CSV'));
    expect(
      [for (final t in findSettings('刪除', among: offered)) t.topic.name],
      ['最近刪除'],
    );
  });

  testWidgets('a build that cannot update itself does not offer '
      '自動檢查新版本 (review 39 #4)', (tester) async {
    await loadFonts();
    await show(tester, 360, 1);
    await go(tester, ['更多', '設定']);
    await tester.enterText(find.byType(TextField).first, '自動檢查');
    await tester.pumpAndSettle();
    expect(find.text('找不到這個設定'), findsOneWidget);
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

  test('search folds 臺 and 台, full and half width, case and spaces (N8)', () {
    const topic = SettingTopic('新台幣帳戶', words: ['Wi-Fi 上傳']);
    for (final typed in ['新臺幣', '新 台 幣', 'wi-fi', 'ＷＩ－ＦＩ', 'Wi-Fi上傳', '　帳戶']) {
      expect(topic.matches(typed), isTrue, reason: typed);
    }
    expect(topic.matches('臺北'), isFalse);
    expect(topic.matches('　'), isFalse);
    expect([for (final t in findSettings('ＧＯＯＧＬＥ')) t.topic.name], ['雲端硬碟備份']);
    expect([for (final t in findSettings('匯入csv')) t.topic.name], ['匯入 CSV']);
    expect([for (final t in findSettings('最近 刪除')) t.topic.name], ['最近刪除']);
    // Pasted from the web with a zero-width space in it (review 39 #6).
    expect(
      [for (final t in findSettings('最近\u200B刪除')) t.topic.name],
      ['最近刪除'],
    );
  });

  /// What the screen reader is told to say, as it is told.
  List<String> listen(WidgetTester tester) {
    final said = <String>[];
    tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<Object?>(
      SystemChannels.accessibility,
      (message) async {
        final data = (message! as Map)['data'] as Map;
        if (data['message'] case final String words) said.add(words);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockDecodedMessageHandler<Object?>(
            SystemChannels.accessibility,
            null,
          ),
    );
    return said;
  }

  /// The accent frame drawn over [name]'s card, or null.
  Decoration? frameOn(WidgetTester tester, String name) {
    final findable = find.byWidgetPredicate(
      (w) => w is Findable && w.topic.name == name,
    );
    final framed = find.descendant(
      of: findable,
      matching: find.byWidgetPredicate(
        (w) => w is Container && w.foregroundDecoration != null,
      ),
    );
    return framed.evaluate().isEmpty
        ? null
        : tester.widget<Container>(framed.first).foregroundDecoration;
  }

  testWidgets('a setting found opens its page on it: scrolled into view, '
      'framed for a moment and said (N8)', (tester) async {
    await loadFonts();
    final said = listen(tester);
    // Short and with large text, so 券商手續費折扣, the last card of
    // 外觀與操作, starts below the screen.
    await show(tester, 360, 2, height: 640);
    await go(tester, ['更多', '設定']);
    await tester.enterText(find.byType(TextField).first, '券商');
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('券商手續費折扣，在外觀與操作'));
    await tester.pump();
    await tester.pump();
    final card = find.byWidgetPredicate(
      (w) => w is Findable && w.topic.name == '券商手續費折扣',
    );
    expect(frameOn(tester, '券商手續費折扣'), isNotNull);
    expect(frameOn(tester, '外觀'), isNull, reason: 'only the one found');
    expect(said, ['已找到「券商手續費折扣」']);
    await tester.pump(const Duration(milliseconds: 400));
    final rect = tester.getRect(card);
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(640));
    // The frame fades once its moment is over; nothing is said again.
    await tester.pumpAndSettle();
    expect(frameOn(tester, '券商手續費折扣'), isNull);
    expect(said, hasLength(1));
  });

  testWidgets('with less motion asked for, the frame stays and does not '
      'fade (N8)', (tester) async {
    await loadFonts();
    listen(tester);
    await show(tester, 360, 1, still: true);
    await go(tester, ['更多', '設定']);
    await tester.enterText(find.byType(TextField).first, '觸感');
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('震動，在外觀與操作'));
    await tester.pumpAndSettle();
    expect(frameOn(tester, '震動'), isNotNull);
    await tester.pump(const Duration(seconds: 5));
    expect(frameOn(tester, '震動'), isNotNull);
  });

  testWidgets('a page opened from its card marks nothing', (tester) async {
    await loadFonts();
    final said = listen(tester);
    await show(tester, 360, 1);
    await go(tester, ['更多', '設定', '外觀與操作']);
    for (final name in ['外觀', '震動', '券商手續費折扣']) {
      expect(frameOn(tester, name), isNull, reason: name);
    }
    expect(said, isEmpty);
  });
}
