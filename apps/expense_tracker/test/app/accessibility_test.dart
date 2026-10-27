import 'dart:io';

import 'package:expense_tracker/src/app/demo/seed.dart';
import 'package:expense_tracker/src/core/look/theme.dart';
import 'package:expense_tracker/src/app/shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every place a person reaches, checked against Android's accessibility
/// guidelines: each tap target at least 48 dp and named for a screen
/// reader; and every page still laid out with the phone's text at 150%.
void main() {
  setUpAll(() async {
    for (final (family, files) in const [
      ('Nunito', ['Nunito-Regular', 'Nunito-SemiBold', 'Nunito-Bold']),
      ('Huninn', ['Huninn-Regular']),
    ]) {
      final loader = FontLoader(family);
      for (final file in files) {
        final bytes = File('fonts/$file.ttf').readAsBytesSync();
        loader.addFont(Future.value(ByteData.sublistView(bytes)));
      }
      await loader.load();
    }
  });

  Future<void> show(WidgetTester tester, {double text = 1}) async {
    tester.view.physicalSize = const Size(400, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(text)),
          child: child!,
        ),
        home: AppShell(ledger: demoLedger()),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The places, each reached from the overview: a name and the taps.
  final places = <(String, List<String>)>[
    ('總覽', []),
    ('紀錄', ['紀錄']),
    ('帳戶', ['帳戶']),
    ('更多', ['更多']),
    ('財務報表', ['更多', '財務報表']),
    ('投資與股息', ['更多', '投資與股息']),
    ('預算管理', ['更多', '預算管理']),
    ('定期交易', ['更多', '定期交易']),
    ('分類管理', ['更多', '分類管理']),
    ('標籤與商家', ['更多', '標籤與商家']),
    ('設定與資料', ['更多', '設定與資料']),
  ];

  Future<void> go(WidgetTester tester, List<String> taps) async {
    for (final words in taps) {
      await tester.tap(find.text(words).first);
      await tester.pumpAndSettle();
    }
  }

  testWidgets('tap targets are 48 dp and named on every page', (tester) async {
    final semantics = tester.ensureSemantics();
    final faults = <String>[];
    Future<void> check(String where) async {
      for (final guideline in [
        androidTapTargetGuideline,
        labeledTapTargetGuideline,
      ]) {
        final result = await guideline.evaluate(tester);
        if (!result.passed) faults.add('$where: ${result.reason}');
      }
    }

    for (final (name, taps) in places) {
      await show(tester);
      await go(tester, taps);
      await check(name);
    }
    await show(tester);
    await tester.tap(find.byTooltip('記一筆'));
    await tester.pumpAndSettle();
    await check('記一筆');
    semantics.dispose();
    expect(faults, isEmpty, reason: faults.join('\n'));
  });

  // One test per place, so a page that overflows is named.
  for (final (name, taps) in places) {
    testWidgets('$name holds with the text at 150%', (tester) async {
      await show(tester, text: 1.5);
      await go(tester, taps);
    });
  }
  testWidgets('記一筆 holds with the text at 150%', (tester) async {
    await show(tester, text: 1.5);
    await tester.tap(find.byTooltip('記一筆'));
    await tester.pumpAndSettle();
  });
}
