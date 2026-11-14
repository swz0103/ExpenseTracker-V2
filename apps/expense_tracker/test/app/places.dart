import 'dart:io';

import 'package:expense_tracker/src/app/demo/preview_services.dart';
import 'package:expense_tracker/src/app/demo/seed.dart';
import 'package:expense_tracker/src/app/shell.dart';
import 'package:expense_tracker/src/core/look/theme.dart';
import 'package:expense_tracker/src/core/preferences.dart';
import 'package:expense_tracker/src/features/settings/model/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every page of the app and how to reach it, for the layout check
/// (layout_test.dart) and the screenshots (tool/screenshots).

/// The app's own fonts, so words take the room they take on a phone.
Future<void> loadFonts() async {
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
}

/// The places and how to reach them; `~` taps a button by its tooltip.
const places = <(String, List<String>)>[
  ('總覽', []),
  ('紀錄', ['紀錄']),
  ('篩選', ['紀錄', '~篩選']),
  ('帳戶', ['帳戶']),
  ('新增帳戶', ['帳戶', '新增']),
  ('排序帳戶', ['帳戶', '排序']),
  ('更多', ['更多']),
  ('報表 收支', ['更多', '財務報表']),
  ('報表 分類', ['更多', '財務報表', '分類']),
  ('報表 比較', ['更多', '財務報表', '比較']),
  ('報表 習慣', ['更多', '財務報表', '習慣']),
  ('投資 持股', ['更多', '投資與股息']),
  ('投資 股息', ['更多', '投資與股息', '股息']),
  ('一檔持股', ['更多', '投資與股息', '台積電']),
  ('代墊與借貸', ['更多', '代墊與借貸']),
  ('貸款', ['更多', '代墊與借貸', '車貸']),
  ('新增貸款', ['更多', '代墊與借貸', '~新增貸款']),
  ('編輯貸款', ['更多', '代墊與借貸', '車貸', '~更多選項', '編輯']),
  ('預算管理', ['更多', '預算管理']),
  ('定期交易', ['更多', '定期交易']),
  ('管理固定項目', ['更多', '定期交易', '~管理']),
  ('訂閱與固定支出', ['更多', '定期交易', '固定支出/年 ›']),
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

/// The demo ledger's app, [width] wide and [height] high, with the text
/// at [text]; [key] wraps it, such as to take a picture of it.
Future<void> show(
  WidgetTester tester,
  double width,
  double text, {
  double height = 2800,
  Key? key,
}) async {
  final preferences = Preferences();
  final ledger = demoLedger();
  final stand = previewServices(preferences, ledger: () => ledger);
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    RepaintBoundary(
      key: key,
      child: MaterialApp(
        // A new app each time: nothing left open from the last place.
        key: UniqueKey(),
        debugShowCheckedModeBanner: false,
        theme: appTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(text)),
          child: child!,
        ),
        // As in the web preview, with its stand-ins for notifications
        // and screen hiding, so those pages and panels are checked too.
        home: AppShell(
          ledger: ledger,
          services: Services(
            preferences: preferences,
            notifier: stand.notifier,
            privacy: stand.privacy,
            market: stand.market,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Taps [taps] in turn: words on the screen, or a button's tooltip after
/// `~`.
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
