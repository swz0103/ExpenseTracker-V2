import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:credit_cards/credit_cards.dart';
import 'package:expense_preview/main.dart';
import 'package:expense_preview/preview_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:ledger_generation_probe/ledger_store.dart';

import 'support.dart';
import 'widget_test.dart' show Documents, closeEngine, input, settle, tap;

Future<void> _tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pump();
  await settle(tester);
}

Future<void> _enterKey(WidgetTester tester, String key, String value) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.enterText(finder, value);
}

Future<void> _waitForButton(WidgetTester tester, String key) async {
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump();
    final finder = find.byKey(ValueKey(key));
    if (finder.evaluate().isNotEmpty &&
        tester.widget<FilledButton>(finder).onPressed != null) {
      return;
    }
  }
  throw StateError('$key did not finish');
}

Future<void> _waitForKey(WidgetTester tester, String key) async {
  for (var i = 0; i < 200; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump();
    if (find.byKey(ValueKey(key)).evaluate().isNotEmpty) return;
  }
  throw StateError('$key did not appear');
}

void main() {
  testWidgets('authorization is visible but does not post until confirmed', (
    tester,
  ) async {
    final root = Directory('.dart_tool/card-authorization-widget-tests')
      ..createSync(recursive: true);
    final work = root.createTempSync('case-');
    final engine = engineAt(work, MemoryVault(), schemaVersion: 19);
    late final Account card;
    try {
      await tester.runAsync(() async {
        await setup(engine);
        card = Account.open(
          id: PublicId.generate(),
          workspace: engine.workspace,
          name: '測試信用卡',
          kind: AccountKind.creditCard,
          currency: Currency('TWD', 2),
          openedOn: BusinessDate(2026, 9, 1),
        );
        await engine.createAccount(
          card,
          Posting.opening(
            id: PublicId.generate(),
            operation: OperationKey(
              engine.workspace,
              OperationId(PublicId.generate()),
            ),
            date: card.openedOn,
            account: ref(card),
            amount: Money(card.currency, BigInt.zero),
          ),
          cardTerms: CreditCardTerms(
            workspace: engine.workspace,
            cardId: card.id,
            currency: card.currency,
            closingDay: 28,
            dueDay: 12,
          ),
        );
        await engine.lock();
      });
      await tester.pumpWidget(
        PreviewApp(engine: Future.value(engine), documents: Documents()),
      );
      await settle(tester);
      await input(tester, '密碼', password);
      await tap(tester, '解鎖');
      await _tapKey(tester, 'open-card-authorizations');
      if (find.byIcon(Icons.visibility_off_outlined).evaluate().isNotEmpty) {
        await tester.tap(find.byIcon(Icons.visibility_off_outlined));
        await tester.pump();
      }
      await _enterKey(tester, 'authorization-date', '2026-09-29');
      await _enterKey(tester, 'authorization-amount', '100');
      await _tapKey(tester, 'create-authorization');
      await _waitForButton(tester, 'create-authorization');
      expect(
        (await tester.runAsync(() => engine.accounts()))!
            .singleWhere((row) => row.account.id == card.id)
            .balance
            .minorUnits,
        BigInt.zero,
      );
      await _enterKey(tester, 'authorization-posted-date', '2026-09-30');
      await _enterKey(tester, 'authorization-settled-amount', '95');
      await _tapKey(tester, 'post-authorization');
      await _waitForKey(tester, 'open-card-authorizations');
      expect(
        (await tester.runAsync(() => engine.accounts()))!
            .singleWhere((row) => row.account.id == card.id)
            .balance
            .minorUnits,
        BigInt.from(-9500),
      );
      await _tapKey(tester, 'open-card-authorizations');
      expect(find.byKey(const ValueKey('post-authorization')), findsNothing);
      await _enterKey(tester, 'authorization-date', '2026-09-30');
      await _enterKey(tester, 'authorization-amount', '5');
      await _tapKey(tester, 'create-authorization');
      await _waitForButton(tester, 'create-authorization');
      await _tapKey(tester, 'cancel-authorization');
      await _waitForButton(tester, 'create-authorization');
      final facts = (await tester.runAsync(
        () => engine.savedCardAuthorizations(),
      ))!;
      expect(
        facts.map((fact) => fact.state),
        contains(CardAuthorizationState.cancelled),
      );
      expect(
        (await tester.runAsync(() => engine.accounts()))!
            .singleWhere((row) => row.account.id == card.id)
            .balance
            .minorUnits,
        BigInt.from(-9500),
      );
    } finally {
      await closeEngine(tester, engine);
      await tester.pumpWidget(const SizedBox());
      deleteSynthetic(work, root);
    }
  });

  testWidgets(
    'disabled card blocks new authorization but can post prior pending',
    (tester) async {
      final root = Directory('.dart_tool/card-authorization-disabled-tests')
        ..createSync(recursive: true);
      final work = root.createTempSync('case-');
      final engine = engineAt(work, MemoryVault(), schemaVersion: 19);
      late final Account card;
      try {
        await tester.runAsync(() async {
          await setup(engine);
          final currency = Currency('TWD', 2);
          card = Account.open(
            id: PublicId.generate(),
            workspace: engine.workspace,
            name: '已停用測試卡',
            kind: AccountKind.creditCard,
            currency: currency,
            openedOn: BusinessDate(2026, 9, 1),
          );
          final terms = CreditCardTerms(
            workspace: engine.workspace,
            cardId: card.id,
            currency: currency,
            closingDay: 28,
            dueDay: 12,
          );
          await engine.createAccount(
            card,
            Posting.opening(
              id: PublicId.generate(),
              operation: OperationKey(
                engine.workspace,
                OperationId(PublicId.generate()),
              ),
              date: card.openedOn,
              account: ref(card),
              amount: Money(currency, BigInt.zero),
            ),
            cardTerms: terms,
          );
          await engine.submitCardAuthorization(
            cardId: card.id,
            authorizedOn: BusinessDate(2026, 9, 29),
            authorizedAmount: Money.parse(currency, '100'),
          );
          await engine.reviseCreditCard(
            CreditCardTerms(
              workspace: terms.workspace,
              cardId: terms.cardId,
              currency: terms.currency,
              closingDay: terms.closingDay,
              dueDay: terms.dueDay,
              version: 2,
            ),
            OperationId(PublicId.generate()),
            disabled: true,
          );
          await engine.lock();
        });
        await tester.pumpWidget(
          PreviewApp(engine: Future.value(engine), documents: Documents()),
        );
        await settle(tester);
        await input(tester, '密碼', password);
        await tap(tester, '解鎖');
        await _tapKey(tester, 'open-card-authorizations');
        if (find.byIcon(Icons.visibility_off_outlined).evaluate().isNotEmpty) {
          await tester.tap(find.byIcon(Icons.visibility_off_outlined));
          await tester.pump();
        }
        expect(find.textContaining('此卡已停用'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('create-authorization')),
              )
              .onPressed,
          isNull,
        );
        expect(
          find.byKey(const ValueKey('post-authorization')),
          findsOneWidget,
        );
        await _enterKey(tester, 'authorization-posted-date', '2026-09-30');
        await _enterKey(tester, 'authorization-settled-amount', '95');
        await _tapKey(tester, 'post-authorization');
        await _waitForKey(tester, 'open-card-authorizations');
        expect(
          (await tester.runAsync(() => engine.accounts()))!
              .singleWhere((row) => row.account.id == card.id)
              .balance,
          Money.parse(card.currency, '-95'),
        );
      } finally {
        await closeEngine(tester, engine);
        await tester.pumpWidget(const SizedBox());
        deleteSynthetic(work, root);
      }
    },
  );
}
