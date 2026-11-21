/// Checks the choices the composer opens and what it takes in from
/// outside: the day, the merchant, tags and instalments picked are the
/// ones recorded; a paper e-invoice scanned fills the form, and one
/// already recorded is said; a receipt photo left over joins the next new
/// entry, and one that cannot be taken is said.
library;

import 'dart:typed_data';

import 'package:expense_tracker/src/app/demo/seed.dart';
import 'package:expense_tracker/src/core/design_system/keys.dart';
import 'package:expense_tracker/src/core/design_system/theme.dart';
import 'package:expense_tracker/src/core/formatting/words.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/features/entries/forms/composer.dart';
import 'package:expense_tracker/src/features/entries/model/receipt_photos.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/places.dart';

/// The phone's receipt photos: [leftover] waiting from before, and the
/// camera failing when [broken].
final class _Photos implements ReceiptPhotos {
  _Photos({this.leftover, this.broken = false});

  String? leftover;
  final bool broken;

  @override
  Future<String?> take({required bool camera}) async {
    if (broken) throw Exception('no camera');
    return 'taken.etr';
  }

  @override
  Future<String?> takeLeftover() async {
    final name = leftover;
    leftover = null;
    return name;
  }

  @override
  ImageProvider image(String name) => MemoryImage(Uint8List(0));
}

/// What the scanner throws when the camera may not be used, in words for
/// the person.
final class _Refused implements Exception {
  const _Refused();

  @override
  String toString() => '相機沒有權限';
}

// AB12345678 of 113/10/25, a total of 105 (hex 69), seller 12345678.
const _head =
    'AB12345678'
    '1131025'
    '1234'
    '00000064'
    '00000069'
    '00000000'
    '12345678'
    'ABCDEFGHIJKLMNOPQRSTUVWX';

void main() {
  late Ledger ledger;
  setUp(() => ledger = demoLedger());

  Future<void> open(
    WidgetTester tester, {
    ReceiptPhotos? photos,
    Future<String?> Function()? scan,
    EntryType type = EntryType.expense,
  }) async {
    tester.view.physicalSize = const Size(420, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => openComposer(
                context,
                ledger,
                type: type,
                photos: photos,
                scan: scan,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> type(WidgetTester tester, String digits) async {
    for (final key in ['C', ...digits.split(''), Words.done]) {
      await tester.tap(find.byKey(Keys.calc(key)));
      await tester.pumpAndSettle();
    }
  }

  Future<void> amount(WidgetTester tester, String digits) async {
    await tester.tap(find.byTooltip('金額'));
    await tester.pumpAndSettle();
    await type(tester, digits);
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.byKey(Keys.save));
    await tester.pumpAndSettle();
  }

  List<Entry> added(int before) => ledger.entries.all.skip(before).toList();

  testWidgets('the day picked is the day recorded', (tester) async {
    final count = ledger.entries.length;
    await open(tester);
    await amount(tester, '35');
    await go(tester, ['日期', '昨天']);
    expect(find.bySemanticsLabel(RegExp('日期：10/3')), findsOneWidget);
    await go(tester, ['日期', '1']);
    await save(tester);
    expect(added(count).single.date, DateTime.utc(2026, 10, 1));
  });

  testWidgets('a choice opened and left with the arrow changes nothing', (
    tester,
  ) async {
    await open(tester);
    await go(tester, ['日期']);
    await tester.tap(find.byTooltip(Words.back).last);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('日期：今天 10/4'), findsOneWidget);
  });

  testWidgets('the merchant and tags picked are recorded', (tester) async {
    final count = ledger.entries.length;
    await open(tester);
    await amount(tester, '150');
    await go(tester, ['商家、標籤、備註', '＋']);
    await tester.enterText(find.byType(TextField).last, '鼎泰豐');
    await tester.pump();
    await go(tester, ['新增「鼎泰豐」', '^＋', '#日本旅遊', '#禮物', '完成']);
    expect(find.text('鼎泰豐'), findsOneWidget);
    await save(tester);
    final made = added(count).single;
    expect(made.merchant, '鼎泰豐');
    expect(made.tags, ['日本旅遊', '禮物']);
  });

  testWidgets('a merchant used before brings its category and account', (
    tester,
  ) async {
    final count = ledger.entries.length;
    final last = ledger.entryQueryService.lastAt('台灣中油')!;
    await open(tester);
    await amount(tester, '1000');
    await go(tester, ['商家、標籤、備註', '台灣中油']);
    await save(tester);
    final made = added(count).single;
    expect(made.merchant, '台灣中油');
    expect((made.category, made.account), (last.category, last.account));
  });

  testWidgets('a paper e-invoice scanned fills the form, and is not taken '
      'twice', (tester) async {
    final count = ledger.entries.length;
    final codes = ['$_head:**********:2:3:1:乾電池:1:55:口罩:2:25', '**牛奶:1:35'];
    await open(tester, scan: () async => codes.removeAt(0));
    await go(tester, ['掃發票']);
    expect(find.text('−105'), findsOneWidget);
    await save(tester);
    final made = added(count).single;
    expect((made.amount, made.date), (105, DateTime.utc(2024, 10, 25)));
    expect(made.tags, contains('發票'));
    expect(made.note, contains('AB12345678'));

    codes.add('$_head:**********:2:3:1:乾電池:1:55:口罩:2:25');
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await go(tester, ['掃發票']);
    expect(find.text('發票 AB12345678 已經記過了'), findsOneWidget);
  });

  testWidgets('a code that is not an invoice\'s left one is said so', (
    tester,
  ) async {
    await open(tester, scan: () async => '**牛奶:1:35');
    await go(tester, ['掃發票']);
    expect(find.text('這不是電子發票左邊的 QR Code，請掃左邊那個'), findsOneWidget);
  });

  testWidgets('what the scanner could not do is said in its own words', (
    tester,
  ) async {
    await open(tester, scan: () async => throw const _Refused());
    await go(tester, ['掃發票']);
    expect(find.text('相機沒有權限'), findsOneWidget);
  });

  testWidgets('a scan given up leaves the form as it was', (tester) async {
    await open(tester, scan: () async => null);
    await go(tester, ['掃發票']);
    expect(find.text('−105'), findsNothing);
  });

  testWidgets('a receipt photo left over joins the next new entry', (
    tester,
  ) async {
    final count = ledger.entries.length;
    await open(tester, photos: _Photos(leftover: 'left.etr'));
    await amount(tester, '40');
    await save(tester);
    final made = added(count).single;
    expect(ledger.receipts.of(made.id), 'left.etr');
  });

  testWidgets('a camera that will not open is said on the form', (
    tester,
  ) async {
    await open(tester, photos: _Photos(broken: true));
    await go(tester, ['商家、標籤、備註']);
    await tester.tap(find.byKey(Keys.receipt));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Keys.receiptSource(camera: true)));
    await tester.pumpAndSettle();
    expect(find.text('無法開啟相機'), findsOneWidget);
  });

  testWidgets('a card spending is spread over the instalments picked', (
    tester,
  ) async {
    final count = ledger.entries.length;
    await open(tester);
    await amount(tester, '1200');
    await go(tester, ['付款帳戶', '日常信用卡', '分期付款', '6 期']);
    expect(find.textContaining('6 期'), findsWidgets);
    await save(tester);
    final made = added(count).single;
    expect(ledger.account(made.account).kind, AccountKind.card);
    expect((made.amount, made.installments), (1200, 6));
  });
}
