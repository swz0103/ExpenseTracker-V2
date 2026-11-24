/// Checks the choices the composer opens and what it takes in from
/// outside: the day, the merchant, tags and instalments picked are the
/// ones recorded; a paper e-invoice scanned fills the form, and one
/// already recorded is said; a receipt photo left over joins the next new
/// entry, and one that cannot be taken is said.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:expense_tracker/src/app/demo/seed.dart';
import 'package:expense_tracker/src/core/design_system/keys.dart';
import 'package:expense_tracker/src/core/design_system/theme.dart';
import 'package:expense_tracker/src/core/formatting/words.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/platform/scan.dart';
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

/// A scanner that answers [outcomes] in turn; [fetches] makes it say first
/// that it has to be fetched.
ScanQr _scanner(List<ScanOutcome> outcomes, {bool fetches = false}) =>
    ({preparing}) async {
      if (fetches) preparing?.call();
      return outcomes.removeAt(0);
    };

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
    ScanQr? scan,
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
    final codes = <ScanOutcome>[
      const ScanRead('$_head:**********:2:3:1:乾電池:1:55:口罩:2:25'),
      const ScanRead('**牛奶:1:35'),
    ];
    await open(tester, scan: _scanner(codes));
    await go(tester, ['掃發票']);
    expect(find.text('−105'), findsOneWidget);
    await save(tester);
    final made = added(count).single;
    expect((made.amount, made.date), (105, DateTime.utc(2024, 10, 25)));
    expect(made.tags, contains('發票'));
    expect(made.note, contains('AB12345678'));

    codes.add(const ScanRead('$_head:**********:2:3:1:乾電池:1:55:口罩:2:25'));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await go(tester, ['掃發票']);
    expect(find.text('發票 AB12345678 已經記過了'), findsOneWidget);
  });

  testWidgets('D30: when the right code fails, the left one fills the form '
      'and the items are said to be missing', (tester) async {
    final count = ledger.entries.length;
    final codes = <ScanOutcome>[
      const ScanRead('$_head:**********:1:3:1:乾電池:1:55'),
      const ScanFailed(ScanFailure.failed),
    ];
    await open(tester, scan: _scanner(codes));
    await go(tester, ['掃發票']);
    expect(find.text('−105'), findsOneWidget);
    expect(
      find.text('品項未讀到：已用左邊的 QR Code 填入金額、日期、賣方統編與發票號碼，可以再修改'),
      findsOneWidget,
    );
    // Still the person's to change: the amount typed over the scan.
    await amount(tester, '100');
    await save(tester);
    final made = added(count).single;
    expect((made.amount, made.date), (100, DateTime.utc(2024, 10, 25)));
    expect(made.tags, contains('發票'));
    expect(made.note, '乾電池 發票 AB12345678 · 統編 12345678 · 品項未讀到');
  });

  testWidgets('D30: a scan of the right code given up fills from the left', (
    tester,
  ) async {
    final codes = <ScanOutcome>[
      const ScanRead('$_head:**********:0:2:1'),
      const ScanClosed(),
    ];
    await open(tester, scan: _scanner(codes));
    await go(tester, ['掃發票']);
    expect(find.text('−105'), findsOneWidget);
    expect(find.textContaining('品項未讀到'), findsWidgets);
  });

  testWidgets('a code that is not an invoice\'s left one is said so', (
    tester,
  ) async {
    await open(tester, scan: _scanner([const ScanRead('**牛奶:1:35')]));
    await go(tester, ['掃發票']);
    expect(find.text('這不是電子發票左邊的 QR Code，請掃左邊那個'), findsOneWidget);
  });

  // F66: a scanner that cannot be fetched used to say one vague line and
  // leave nothing behind; each way of failing now says what to do next.
  testWidgets('a scanner that cannot be fetched says so, with what to do', (
    tester,
  ) async {
    await open(
      tester,
      scan: _scanner([const ScanFailed(ScanFailure.unavailable)]),
    );
    await go(tester, ['掃發票']);
    expect(
      find.text(
        '無法下載掃描器。請確認手機有網路、還有儲存空間，並且 Google Play 服務已開啟並更新，'
        '再按一次「掃發票」；也可以直接手動輸入這張發票。',
      ),
      findsOneWidget,
    );
    expect(find.text('−105'), findsNothing);
  });

  testWidgets('a scanner that opens and fails says to retry or type it', (
    tester,
  ) async {
    await open(tester, scan: _scanner([const ScanFailed(ScanFailure.failed)]));
    await go(tester, ['掃發票']);
    expect(find.text('沒有掃到。請再按一次「掃發票」，或直接手動輸入這張發票。'), findsOneWidget);
  });

  testWidgets('a scanner already open says so', (tester) async {
    await open(tester, scan: _scanner([const ScanFailed(ScanFailure.busy)]));
    await go(tester, ['掃發票']);
    expect(find.text('掃描器已經開著'), findsOneWidget);
  });

  testWidgets('while the scanner is being fetched the form says to wait, '
      'and stops saying it once the scanner answers', (tester) async {
    final answer = Completer<ScanOutcome>();
    await open(
      tester,
      scan: ({preparing}) {
        preparing?.call();
        return answer.future;
      },
    );
    await go(tester, ['掃發票']);
    expect(find.text('第一次使用要先下載掃描器，請稍候…'), findsOneWidget);
    answer.complete(const ScanClosed());
    await tester.pumpAndSettle();
    expect(find.text('第一次使用要先下載掃描器，請稍候…'), findsNothing);
  });

  testWidgets('a scan given up leaves the form as it was', (tester) async {
    await open(tester, scan: _scanner([const ScanClosed()]));
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
