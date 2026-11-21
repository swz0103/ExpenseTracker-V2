/// Checks the account form: a new account is kept with the kind, mark,
/// colour, currency and days chosen; an account in use is archived once
/// what is left in it is moved, and brought back; one never used is
/// deleted once agreed.
library;

import 'package:expense_tracker/src/app/demo/seed.dart';
import 'package:expense_tracker/src/core/design_system/design_system.dart';
import 'package:expense_tracker/src/core/design_system/theme.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/widgets/icons.dart';
import 'package:expense_tracker/src/features/accounts/forms/account_editor.dart';
import 'package:expense_tracker/src/features/accounts/model/account_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/places.dart';

void main() {
  late Ledger ledger;
  late List<bool> gone;
  setUp(() {
    ledger = demoLedger();
    gone = [];
  });

  /// Opens the account form, for [account] when given.
  Future<void> open(WidgetTester tester, {Account? account}) async {
    tester.view.physicalSize = const Size(420, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => gone.add(
                await editAccount(context, ledger, account: account),
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

  Account added(int before) => ledger.accounts.all.skip(before).single;

  testWidgets('a card is kept with its days, limit, mark and colour', (
    tester,
  ) async {
    final count = ledger.accounts.all.length;
    await open(tester);
    await tester.enterText(find.byType(TextField).first, '旅遊卡');
    await go(tester, ['信用卡', '圖示：鑽石', '結帳日', '20', '繳款日', '^5']);
    await tester.enterText(find.byType(TextField).last, '80000');
    await go(tester, ['卡片顏色']);
    // The first colour after 預設.
    await tester.tap(find.byType(SwatchButton).at(1));
    await tester.pumpAndSettle();
    await go(tester, ['計入資產與淨資產', '儲存']);
    final card = added(count);
    expect(
      (card.name, card.kind, card.icon, card.closingDay, card.dueDay),
      ('旅遊卡', AccountKind.card, 'diamond', 20, 5),
    );
    expect(card.limit, 80000);
    expect(card.color, isNotNull);
    expect(card.inNetWorth, isFalse);
    expect(gone, [false]);
  });

  testWidgets('a foreign account is kept in its currency, from the whole '
      'list', (tester) async {
    final count = ledger.accounts.all.length;
    await open(tester);
    await tester.enterText(find.byType(TextField).first, '英鎊戶');
    await go(tester, ['更多', 'GBP']);
    expect(find.text('GBP'), findsOneWidget);
    await go(tester, ['儲存']);
    expect(added(count).currency, 'GBP');
  });

  testWidgets('a mark from the whole set is kept, the default colour back', (
    tester,
  ) async {
    final count = ledger.accounts.all.length;
    await open(tester);
    await tester.enterText(find.byType(TextField).first, '撲滿');
    await go(tester, ['現金', '更多圖示', '寶箱']);
    // The mark picked from the set takes the last place in the row.
    expect(find.bySemanticsLabel('圖示：寶箱'), findsOneWidget);
    await go(tester, ['卡片顏色', '預設', '儲存']);
    final kept = added(count);
    expect((kept.kind, accountIconName(kept.icon!)), (AccountKind.cash, '寶箱'));
    expect(kept.color, isNull);
  });

  testWidgets('an account with money left is settled into another, then '
      'archived', (tester) async {
    final bank = ledger.account('bank');
    final left = ledger.balanceService.balance('bank');
    final cash = ledger.balanceService.balance('cash');
    await open(tester, account: bank);
    expect(find.text('編輯帳戶'), findsOneWidget);
    await go(tester, ['結清封存']);
    expect(find.text('餘額轉到哪個帳戶'), findsOneWidget);
    await go(tester, ['隨身現金']);
    expect(ledger.account('bank').archived, isTrue);
    expect(ledger.balanceService.balance('bank'), 0);
    expect(ledger.balanceService.balance('cash'), cash + left);
    expect(gone, [true]);
  });

  testWidgets('choosing nowhere to move the money leaves the account open', (
    tester,
  ) async {
    await open(tester, account: ledger.account('bank'));
    await go(tester, ['結清封存']);
    // The phone's back, from the list of accounts.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(ledger.account('bank').archived, isFalse);
  });

  testWidgets('an archived account is brought back', (tester) async {
    final bank = ledger.account('bank');
    ledger.entryCommands.add(AccountForm.settlement(ledger, bank, 'cash'));
    ledger.accountCommands.updateAccount(
      ledger.account('bank').copyWith(archived: true),
    );
    await open(tester, account: ledger.account('bank'));
    await go(tester, ['恢復']);
    expect(ledger.account('bank').archived, isFalse);
    expect(gone, [false]);
  });

  testWidgets('an account never used is deleted once agreed', (tester) async {
    const spare = Account('spare', '備用金', AccountKind.cash, 0);
    ledger.accountCommands.addAccount(spare);
    await open(tester, account: spare);
    await go(tester, ['刪除']);
    expect(find.text('刪除「備用金」？'), findsOneWidget);
    await tester.tap(find.byKey(Keys.confirm));
    await tester.pumpAndSettle();
    expect(ledger.accounts.contains('spare'), isFalse);
    expect(gone, [true]);
  });

  testWidgets('a balance typed on an account is kept', (tester) async {
    await open(tester, account: ledger.account('cash'));
    await tester.enterText(find.byType(TextField).at(1), '2500');
    await go(tester, ['儲存']);
    expect(ledger.balanceService.balance('cash'), 2500);
  });
}
