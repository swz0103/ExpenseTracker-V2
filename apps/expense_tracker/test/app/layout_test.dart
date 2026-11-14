import 'dart:io';

import 'package:expense_tracker/src/app/demo/seed.dart';
import 'package:expense_tracker/src/app/shell.dart';
import 'package:expense_tracker/src/core/look/theme.dart';
import 'package:expense_tracker/src/core/preferences.dart';
import 'package:expense_tracker/src/core/screen_privacy.dart';
import 'package:expense_tracker/src/features/reminders/model/notifications.dart';
import 'package:expense_tracker/src/features/settings/model/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every page and tab, the panels in the middle of the screen and each
/// page of 記一筆, on a small phone (320 dp), a common one (360 dp) and a
/// large one (412 dp), with the text at 100%, 130% and 150%, and in dark
/// at 360 dp: nothing overflows, no words are drawn over other words, and
/// none are shrunk to fit below six tenths of their size. Words
/// running into each other, or a block too small for what it holds, is
/// how a page breaks on a real phone though it looked right at one size.
void main() {
  setUpAll(() async {
    for (final (family, files) in const [
      ('Nunito', ['Nunito-Regular', 'Nunito-SemiBold', 'Nunito-Bold']),
      ('NotoSansTC', ['NotoSansTC-Regular', 'NotoSansTC-Bold']),
    ]) {
      final loader = FontLoader(family);
      for (final file in files) {
        final bytes = File('fonts/$file.ttf').readAsBytesSync();
        loader.addFont(Future.value(ByteData.sublistView(bytes)));
      }
      await loader.load();
    }
  });

  /// The places and how to reach them; `~` taps a button by its tooltip.
  const places = <(String, List<String>)>[
    ('總覽', []),
    ('紀錄', ['紀錄']),
    ('帳戶', ['帳戶']),
    ('更多', ['更多']),
    ('報表 收支', ['更多', '財務報表']),
    ('報表 分類', ['更多', '財務報表', '分類']),
    ('報表 比較', ['更多', '財務報表', '比較']),
    ('報表 習慣', ['更多', '財務報表', '習慣']),
    ('投資 持股', ['更多', '投資與股息']),
    ('投資 股息', ['更多', '投資與股息', '股息']),
    ('一檔持股', ['更多', '投資與股息', '長榮']),
    ('代墊與借貸', ['更多', '代墊與借貸']),
    ('貸款', ['更多', '代墊與借貸', '車貸']),
    ('預算管理', ['更多', '預算管理']),
    ('定期交易', ['更多', '定期交易']),
    ('管理固定項目', ['更多', '定期交易', '~管理']),
    ('訂閱與固定支出', ['更多', '定期交易', '訂閱與固定支出 ›']),
    ('分類', ['更多', '分類']),
    ('標籤', ['更多', '標籤與商家']),
    ('商家', ['更多', '標籤與商家', '商家']),
    ('一個商家', ['更多', '標籤與商家', '商家', '星巴克']),
    ('設定', ['更多', '設定']),
    ('匯入與匯出', ['更多', '設定', '匯入與匯出']),
    ('關於', ['更多', '設定', '關於']),
    ('通知與提醒', ['更多', '設定', '通知與提醒']),
    ('到期提醒', ['更多', '設定', '通知與提醒', '到期提醒']),
    ('預算提醒', ['更多', '設定', '通知與提醒', '預算提醒']),
    ('每日記帳', ['更多', '設定', '通知與提醒', '每日記帳']),
    ('安全', ['更多', '設定', '安全']),
    ('外觀與操作', ['更多', '設定', '外觀與操作']),
    ('外觀', ['更多', '設定', '外觀與操作', '外觀']),
    ('桌面小工具', ['更多', '設定', '外觀與操作', '桌面小工具']),
    ('總覽區塊', ['更多', '設定', '外觀與操作', '總覽區塊']),
    ('最近刪除', ['更多', '設定', '最近刪除']),
    ('記一筆', ['~記一筆']),
    ('記一筆 收入', ['~記一筆', '收入']),
    ('記一筆 轉帳', ['~記一筆', '轉帳']),
    ('記一筆 投資', ['~記一筆', '投資']),
    ('記一筆 展開', ['~記一筆', '商家、標籤、備註']),
    ('記一筆 代墊', ['~記一筆', '代墊']),
    ('記一筆 選帳戶', ['~記一筆', '日常銀行']),
    ('記一筆 選日期', ['~記一筆', '今天']),
    ('記一筆 全部分類', ['~記一筆', '全部']),
    ('記一筆 計算機', ['~記一筆', '~金額']),
  ];

  Future<void> show(WidgetTester tester, double width, double text) async {
    final preferences = Preferences();
    final hidden = Directory.systemTemp.createTempSync('layout-');
    addTearDown(() => hidden.deleteSync(recursive: true));
    tester.view.physicalSize = Size(width, 2800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        // A new app each time: nothing left open from the last place.
        key: UniqueKey(),
        theme: appTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(text)),
          child: child!,
        ),
        // The settings the preview leaves out, so their pages and
        // panels are checked too.
        home: AppShell(
          ledger: demoLedger(),
          services: Services(
            preferences: preferences,
            notifier: Notifier(_Port(), preferences),
            privacy: ScreenPrivacy(hidden, (_) async {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> go(WidgetTester tester, List<String> taps) async {
    for (final step in taps) {
      var finder = step.startsWith('~')
          ? find.byTooltip(step.substring(1))
          : find.text(step);
      if (finder.evaluate().isEmpty) finder = find.textContaining(step);
      expect(finder, findsWidgets, reason: 'no 「$step」 to tap');
      await tester.tap(finder.first, warnIfMissed: false);
      await tester.pumpAndSettle();
    }
  }

  for (final (width, text, dark) in [
    for (final width in const [320.0, 360.0, 412.0])
      for (final text in const [1.0, 1.3, 1.5]) (width, text, false),
    (360.0, 1.0, true),
    (360.0, 1.5, true),
  ]) {
    {
      testWidgets('${width.toInt()} dp, text ${(text * 100).round()}%'
          '${dark ? ', dark' : ''}: '
          'nothing overflows and no words overlap', (tester) async {
        Shade.dark = dark;
        addTearDown(() => Shade.dark = false);
        final faults = <String>[];
        for (final (name, taps) in places) {
          await show(tester, width, text);
          await go(tester, taps);
          final error = tester.takeException();
          if (error != null) faults.add('$name: $error');
          final shrunk = <String>[];
          for (final (a, b) in overlapping(tester, shrunk)) {
            faults.add('$name: 「$a」 overlaps 「$b」');
          }
          for (final words in shrunk) {
            faults.add('$name: 「$words」 shrunk too small to read');
          }
        }
        expect(faults, isEmpty, reason: faults.join('\n'));
      });
    }
  }
}

/// Notifications that go nowhere, with the phone's settings all right.
final class _Port implements NotifyPort {
  @override
  Future<bool> access() async => true;

  @override
  Future<void> schedule(
    List<Alert> alerts, {
    bool exact = false,
    Set<String>? wanted,
  }) async {}

  @override
  Future<void> test({bool exact = false}) async {}

  @override
  Future<void> post(Alert alert, int id) async {}

  @override
  Future<ReminderStatus> status() async =>
      (notifications: true, exact: true, battery: true);

  @override
  Future<void> openExactSettings() async {}

  @override
  Future<void> openBatterySettings() async {}
}

/// Pairs of words drawn over each other on screen: each run of words is
/// measured by the boxes its glyphs take, not the box laid out for it,
/// so words that only sit near each other do not count.
List<(String, String)> overlapping(
  WidgetTester tester, [
  List<String>? shrunk,
]) {
  final small = shrunk ?? <String>[];
  final bottom = tester.view.physicalSize.height / tester.view.devicePixelRatio;
  final runs = <(String, Rect)>[];
  for (final element in find.byType(RichText).evaluate()) {
    // Only the page or sheet on top: what lies under a sheet is covered.
    final route = ModalRoute.of(element);
    if (route != null && !route.isCurrent) continue;
    final box = element.renderObject;
    if (box is! RenderParagraph || !box.hasSize || !box.attached) continue;
    final words = box.text.toPlainText().trim();
    if (words.isEmpty) continue;
    final boxes = box.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: box.text.toPlainText().length),
    );
    if (boxes.isEmpty) continue;
    var rect = boxes.first.toRect();
    for (final b in boxes.skip(1)) {
      rect = rect.expandToInclude(b.toRect());
    }
    // Words cut off by their own box, such as an ellipsis, only count
    // where they are drawn.
    rect = rect.intersect(Offset.zero & box.size);
    if (rect.isEmpty) continue;
    // Through every transform above it, such as a FittedBox scaling the
    // words down: what is drawn, not what was laid out.
    final drawn = MatrixUtils.transformRect(box.getTransformTo(null), rect);
    // Shrunk to fit below six tenths of its size, words cannot be read.
    if (drawn.height < rect.height * 0.6) {
      small.add(words);
    }
    // Only what is seen: cut by every clip above it, such as a row that
    // slides sideways, and not under the tab bar along the bottom.
    var seen = drawn;
    RenderObject child = box;
    var parent = box.parent;
    while (parent != null && !seen.isEmpty) {
      final clip = parent.describeApproximatePaintClip(child);
      if (clip != null) {
        seen = seen.intersect(
          MatrixUtils.transformRect(parent.getTransformTo(null), clip),
        );
      }
      child = parent;
      parent = parent.parent;
    }
    if (seen.isEmpty || seen.width <= 0 || seen.height <= 0) continue;
    if (seen.top > bottom - 110) continue;
    runs.add((words, seen));
  }
  final found = <(String, String)>[];
  for (var i = 0; i < runs.length; i++) {
    for (var j = i + 1; j < runs.length; j++) {
      final both = runs[i].$2.intersect(runs[j].$2);
      // A pixel of touching ascenders is not two words on each other.
      if (both.width > 2 && both.height > 2) {
        found.add((runs[i].$1, runs[j].$1));
      }
    }
  }
  return found;
}
