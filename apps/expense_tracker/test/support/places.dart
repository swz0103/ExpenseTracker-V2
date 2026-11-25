import 'dart:io';

import 'package:expense_tracker/src/app/demo/preview_services.dart';
import 'package:expense_tracker/src/app/demo/seed.dart';
import 'package:expense_tracker/src/app/shell.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/design_system/theme.dart';
import 'package:expense_tracker/src/core/platform/preferences.dart';
import 'package:expense_tracker/src/features/backup/model/backup_manager.dart';
import 'package:expense_tracker/src/features/reminders/model/calendar_sync.dart';
import 'package:expense_tracker/src/app/platform_services.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'built_places.dart';
import 'fake_calendar.dart';
import 'place.dart';
import 'review_book.dart';

export 'place.dart';

/// Every page of the app and how to reach it, for the layout check
/// (layout_*_test.dart) and the screenshots (tool/screenshots).

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

/// The places and how to reach them, each step what a screen reader calls
/// the thing to press ([go]); a card that also holds a switch named as it
/// is is reached by its own words, so the switch is not pressed instead.
const places = <(String, List<String>)>[
  ('總覽', []),
  ('紀錄', ['紀錄']),
  ('檢視紀錄', ['紀錄', '週末點心']),
  ('篩選', ['紀錄', '~篩選']),
  ('選日期區間', ['紀錄', '~篩選', '自訂']),
  ('帳戶', ['帳戶']),
  ('信用卡', ['帳戶', '日常信用卡']),
  ('新增帳戶', ['帳戶', '新增']),
  ('帳戶 卡片顏色', ['帳戶', '新增', '@卡片顏色']),
  ('帳戶 更多圖示', ['帳戶', '新增', '@更多圖示']),
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
  ('代墊對象', ['更多', '代墊與借貸', '代墊朋友']),
  ('新增貸款', ['更多', '代墊與借貸', '~新增貸款']),
  ('編輯貸款', ['更多', '代墊與借貸', '車貸', '~更多選項', '編輯']),
  ('預算管理', ['更多', '預算管理']),
  ('預算 選月份', ['更多', '預算管理', '10 月']),
  ('預算 編輯', ['更多', '預算管理', '居家生活']),
  ('定期交易', ['更多', '定期交易']),
  ('管理固定項目', ['更多', '定期交易', '~管理']),
  ('編輯定期交易', ['更多', '定期交易', '~管理', 'Netflix']),
  ('定期交易 重複', ['更多', '定期交易', '~管理', 'Netflix', '^每月 5 日']),
  ('定期交易 其他設定', ['更多', '定期交易', '~管理', 'Netflix', '其他設定']),
  ('訂閱與固定支出', ['更多', '定期交易', '固定支出/年 ›']),
  ('分類', ['更多', '分類']),
  ('編輯分類', ['更多', '分類', '居家生活']),
  ('新增分類', ['更多', '分類', '新增']),
  ('分類 換圖示', ['更多', '分類', '居家生活', '@換圖示']),
  ('新增子分類', ['更多', '分類', '居家生活', '^子分類']),
  ('標籤', ['更多', '標籤與商家']),
  ('商家', ['更多', '標籤與商家', '商家']),
  ('一個商家', ['更多', '標籤與商家', '商家', '星巴克']),
  ('商家改名', ['更多', '標籤與商家', '商家', '星巴克', '~更多選項', '改名']),
  ('設定', ['更多', '設定']),
  ('匯入與匯出', ['更多', '設定', '匯入與匯出']),
  ('匯入 CSV', ['更多', '設定', '匯入與匯出', 'CSV 檔案']),
  ('關於', ['更多', '設定', '關於']),
  ('通知與提醒', ['更多', '設定', '通知與提醒']),
  ('到期提醒', ['更多', '設定', '通知與提醒', '信用卡、定期交易']),
  ('預算提醒', ['更多', '設定', '通知與提醒', '用到幾成時']),
  ('每日記帳', ['更多', '設定', '通知與提醒', '每天 21:00']),
  ('選提醒時間', ['更多', '設定', '通知與提醒', '每天 21:00', '@提醒時間']),
  ('安全', ['更多', '設定', '安全']),
  ('外觀與操作', ['更多', '設定', '外觀與操作']),
  ('外觀', ['更多', '設定', '外觀與操作', '外觀']),
  ('桌面小工具', ['更多', '設定', '外觀與操作', '桌面小工具']),
  ('總覽區塊', ['更多', '設定', '外觀與操作', '總覽區塊']),
  ('最近刪除', ['更多', '設定', '最近刪除']),
  ('備份與還原', ['更多', '設定', '沒有自動備份']),
  ('記一筆', ['~記一筆']),
  ('記一筆 收入', ['~記一筆', '收入']),
  ('記一筆 轉帳', ['~記一筆', '轉帳']),
  ('記一筆 投資', ['~記一筆', '^投資']),
  ('記一筆 全部標的', ['~記一筆', '^投資', '@全部標的']),
  ('記一筆 展開', ['~記一筆', '商家、標籤、備註']),
  ('記一筆 代墊', ['~記一筆', '代墊']),
  ('記一筆 選帳戶', ['~記一筆', '日常銀行']),
  ('記一筆 選日期', ['~記一筆', '今天']),
  ('記一筆 全部分類', ['~記一筆', '全部']),
  ('記一筆 計算機', ['~記一筆', '~金額']),
];

/// More places, reached on [reviewLedger] with a password, a fingerprint,
/// a phone with a calendar to link: what the demo ledger has none of.
const reviewPaths = <(String, List<String>)>[
  ('紀錄 預定與退款', ['紀錄']),
  ('檢視預定', ['紀錄', '朋友聚餐訂位']),
  ('檢視退款', ['紀錄', '退款']),
  ('預算 預估', ['更多', '預算管理']),
  ('信用卡 順延', ['帳戶', '國慶信用卡']),
  ('券商帳戶', ['帳戶', '永豐證券']),
  ('編輯券商帳戶', ['帳戶', '永豐證券', '編輯']),
  ('記一筆 買進', ['~記一筆', '^投資']),
  ('設定 通知與提醒', ['更多', '設定', '通知與提醒']),
  ('設定 安全', ['更多', '設定', '安全']),
];

/// [reviewPaths] on [reviewLedger], with its keys and calendar.
final reviewPlaces = <Place>[
  for (final (name, taps) in reviewPaths)
    Place('review: $name', (tester, look) async {
      final dir = Directory.systemTemp.createTempSync('places-');
      addTearDown(() => dir.deleteSync(recursive: true));
      await show(
        tester,
        look.width,
        look.text,
        height: look.height,
        still: look.still,
        scaler: look.scaler,
        book: reviewLedger(),
        keys: ReviewKeys(),
        calendar: CalendarSync(FakeCalendars(), dir),
      );
      await go(tester, taps);
    }),
];

/// Every place, to check: the paths of [places] on the demo ledger, the
/// paths of [reviewPaths] on [reviewLedger], and what is built where it
/// stands ([builtPlaces]).
final allPlaces = <Place>[
  for (final (name, taps) in places)
    Place(name, (tester, look) async {
      await show(
        tester,
        look.width,
        look.text,
        height: look.height,
        still: look.still,
        scaler: look.scaler,
      );
      await go(tester, taps);
    }),
  ...reviewPlaces,
  ...builtPlaces,
];

/// The demo ledger's app, [width] wide and [height] high, with the text
/// at [text], and motion turned off when [still]; [key] wraps it, such as
/// to take a picture of it.
Future<void> show(
  WidgetTester tester,
  double width,
  double text, {
  double height = 2800,
  Key? key,
  Ledger? book,
  bool still = false,
  TextScaler? scaler,
  BackupManager? keys,
  CalendarSync? calendar,
}) async {
  final preferences = Preferences();
  final ledger = book ?? demoLedger();
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
          data: MediaQuery.of(context).copyWith(
            textScaler: scaler ?? TextScaler.linear(text),
            disableAnimations: still,
          ),
          child: child!,
        ),
        // As in the web preview, with its stand-ins for notifications
        // and screen hiding, so those pages and panels are checked too.
        home: AppShell(
          ledger: ledger,
          services: PlatformServices(
            preferences: preferences,
            notifier: stand.notifier,
            privacy: stand.privacy,
            market: stand.market,
            backupManager: keys ?? stand.backupManager,
            calendar: calendar,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Goes through [taps] as a screen reader user would: each step is what
/// a screen reader calls the thing to press, and pressing it is the
/// screen reader's own tap, so a place a screen reader cannot reach
/// fails here. `@` before the words is the same, kept for paths written
/// so; `~` presses a button by its tooltip instead; `^` takes the last
/// one found, as a sheet over a page that holds the same words.
Future<void> go(WidgetTester tester, List<String> taps) async {
  final semantics = tester.ensureSemantics();
  try {
    await _go(tester, taps);
  } finally {
    semantics.dispose();
  }
}

/// The node a screen reader calls [words] and can press: named so
/// exactly, or with a name that starts with them (a card read out with
/// its figures), or failing both one that holds them (a row read out
/// with what it is about first). Words that only head a group cannot be
/// pressed, and so are passed over.
SemanticsNode? _named(String words, {required bool last}) {
  final quoted = RegExp.escape(words);
  for (final name in [
    RegExp('^$quoted\$'),
    RegExp('^$quoted'),
    RegExp(quoted),
  ]) {
    final found = find.semantics
        .byPredicate(
          (node) =>
              !node.isMergedIntoParent &&
              name.hasMatch(node.label) &&
              node.getSemanticsData().hasAction(SemanticsAction.tap),
        )
        .evaluate()
        .toList();
    if (found.isNotEmpty) return last ? found.last : found.first;
  }
  return null;
}

Future<void> _go(WidgetTester tester, List<String> taps) async {
  for (final step in taps) {
    final last = step.startsWith('^');
    final words = last ? step.substring(1) : step;
    if (words.startsWith('~')) {
      final button = find.byTooltip(words.substring(1));
      expect(button, findsWidgets, reason: 'no button 「$words」');
      await tester.ensureVisible(button.first);
      await tester.pumpAndSettle();
      await tester.tap(button.first, warnIfMissed: false);
    } else {
      final read = words.startsWith('@') ? words.substring(1) : words;
      final node = _named(read, last: last);
      expect(node, isNotNull, reason: 'no 「$read」 a screen reader can press');
      tester.semantics.tap(find.semantics.byPredicate((n) => n == node));
    }
    await tester.pumpAndSettle();
  }
}
