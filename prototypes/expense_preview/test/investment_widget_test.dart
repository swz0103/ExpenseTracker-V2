import 'dart:io';

import 'package:expense_preview/main.dart';
import 'package:expense_preview/preview_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/ledger.dart';

import 'support.dart';
import 'widget_test.dart' show Documents, closeEngine, settle;

Future<void> _waitForKey(WidgetTester tester, String key) async {
  for (var i = 0; i < 160; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump();
    if (find.byKey(ValueKey(key)).evaluate().isNotEmpty) return;
  }
  throw StateError('$key did not appear');
}

Future<void> _waitForEnabledButton(WidgetTester tester, String key) async {
  for (var i = 0; i < 160; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump();
    final finder = find.byKey(ValueKey(key));
    if (finder.evaluate().isEmpty) continue;
    final widget = tester.widget(finder);
    if (widget is FilledButton && widget.onPressed != null ||
        widget is TextButton && widget.onPressed != null) {
      return;
    }
  }
  throw StateError('$key did not become available');
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pump();
}

Future<void> _enterKey(WidgetTester tester, String key, String value) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.enterText(finder, value);
}

Future<void> _openInvestmentScreen(
  WidgetTester tester,
  PreviewEngine engine,
) async {
  await tester.pumpWidget(
    PreviewApp(
      engine: Future.value(engine),
      documents: Documents(),
    ),
  );
  await settle(tester);
  await tester.enterText(find.byType(TextField).first, password);
  await tester.tap(find.byType(FilledButton).first);
  await settle(tester);
  await _tapKey(tester, 'open-investments');
  await _waitForKey(tester, 'investment-broker');
}

Future<void> _prepareSyntheticBuy(WidgetTester tester) async {
  for (final (key, value) in [
    ('investment-broker', '合成券商'),
    ('investment-account', '合成投資帳戶'),
    ('investment-market', 'XNAS'),
    ('investment-symbol', 'TEST'),
    ('investment-name', '合成股票'),
    ('investment-date', '2026-09-29'),
    ('investment-quantity', '2'),
    ('investment-price', '10.25'),
    ('investment-gross', '20.50'),
    ('investment-fee', '0.50'),
    ('investment-tax', '0'),
  ]) {
    await _enterKey(tester, key, value);
  }
  await _tapKey(tester, 'review-investment-buy');
  expect(find.byKey(const ValueKey('investment-cash-preview')), findsOneWidget);
  expect(find.textContaining('21.00 TWD'), findsOneWidget);
  expect(find.byKey(const ValueKey('save-investment-buy')), findsOneWidget);
}

void main() {
  testWidgets('buy needs second confirmation and hides uncommitted review', (
    tester,
  ) async {
    final root = Directory('.dart_tool/investment-widget-tests')
      ..createSync(recursive: true);
    final work = root.createTempSync('confirm-');
    final engine = engineAt(work, MemoryVault(), schemaVersion: 21);
    try {
      await tester.runAsync(() async {
        await setup(engine);
        final cash = account(engine, name: '合成現金');
        await engine.createAccount(cash, opening(cash));
        await engine.lock();
      });
      await _openInvestmentScreen(tester, engine);
      await _prepareSyntheticBuy(tester);
      expect((await tester.runAsync(engine.investmentBuys))!, isEmpty);
      expect(
        (await tester.runAsync(engine.accounts))!.single.balance.minorUnits,
        BigInt.from(10000),
      );

      // Privacy mode removes the confirmation surface and its stale preview.
      await tester.tap(find.byIcon(Icons.visibility_outlined));
      await tester.pump();
      expect(find.byKey(const ValueKey('save-investment-buy')), findsNothing);
      await tester.tap(find.byIcon(Icons.visibility_off_outlined));
      await tester.pump();
      expect(find.byKey(const ValueKey('save-investment-buy')), findsNothing);

      await _tapKey(tester, 'review-investment-buy');
      await _tapKey(tester, 'save-investment-buy');
      await _waitForEnabledButton(tester, 'review-investment-buy');
      final facts = (await tester.runAsync(engine.investmentBuys))!;
      expect(facts, hasLength(1));
      expect(facts.single.preview.lot.quantity.toString(), '2');
      expect(facts.single.preview.lot.acquisitionCashCost.majorText, '21.00');
      expect(
        (await tester.runAsync(engine.accounts))!.single.balance.minorUnits,
        BigInt.from(7900),
      );
      expect(
        (await tester.runAsync(engine.entries))!
            .where((row) => row.kind == PostingKind.investmentBuy),
        hasLength(1),
      );
      await _waitForKey(tester, 'investment-buy-${facts.single.preview.id}');
    } finally {
      await closeEngine(tester, engine);
      await tester.pumpWidget(const SizedBox());
      deleteSynthetic(work, root);
    }
  });

  testWidgets('ambiguous result exposes retry of the same investment buy', (
    tester,
  ) async {
    final root = Directory('.dart_tool/investment-widget-tests')
      ..createSync(recursive: true);
    final work = root.createTempSync('retry-');
    var interruptOnce = true;
    final engine = engineAt(
      work,
      MemoryVault(),
      schemaVersion: 21,
      draftCheckpoint: (stage) {
        if (stage == 'investment-buy-committed' && interruptOnce) {
          interruptOnce = false;
          throw StateError('synthetic interruption after commit');
        }
      },
    );
    try {
      await tester.runAsync(() async {
        await setup(engine);
        final cash = account(engine, name: '合成現金');
        await engine.createAccount(cash, opening(cash));
        await engine.lock();
      });
      await _openInvestmentScreen(tester, engine);
      await _prepareSyntheticBuy(tester);
      await _tapKey(tester, 'save-investment-buy');
      await _waitForEnabledButton(tester, 'retry-investment-buy');
      expect((await tester.runAsync(engine.hasPendingInvestmentBuy))!, isTrue);
      expect((await tester.runAsync(engine.investmentBuys))!, hasLength(1));

      await _tapKey(tester, 'retry-investment-buy');
      await _waitForEnabledButton(tester, 'review-investment-buy');
      expect((await tester.runAsync(engine.hasPendingInvestmentBuy))!, isFalse);
      expect((await tester.runAsync(engine.investmentBuys))!, hasLength(1));
      expect(
        (await tester.runAsync(engine.accounts))!.single.balance.minorUnits,
        BigInt.from(7900),
      );
    } finally {
      await closeEngine(tester, engine);
      await tester.pumpWidget(const SizedBox());
      deleteSynthetic(work, root);
    }
  });
}
