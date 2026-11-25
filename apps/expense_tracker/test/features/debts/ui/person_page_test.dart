import 'package:expense_tracker/src/app/demo/seed.dart';
import 'package:expense_tracker/src/core/design_system/dialogs.dart';
import 'package:expense_tracker/src/core/design_system/keys.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:flutter/material.dart';
import 'package:expense_tracker/src/core/formatting/words.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/places.dart';

/// The page of one person paid for (代墊朋友 in the demo book): what
/// they still owe and since when, each sum named by its note or by the
/// spending it was part of, 收回 and 幫忙付 opening the composer on the
/// right accounts, and 改名 and 刪除 from its ⋯.
void main() {
  setUpAll(loadFonts);

  late Ledger ledger;

  Entry transfer(
    String id,
    DateTime date,
    int amount, {
    String from = 'bank',
    String to = 'lent',
    String note = '',
    String? group,
  }) => Entry(
    id: id,
    date: date,
    type: EntryType.transfer,
    amount: amount,
    account: from,
    category: transferCategory,
    to: to,
    note: note,
    group: group,
  );

  /// The demo book, the friend paid back the 3,200 they owed from the
  /// start, then paid for three times: a ticket a month ago, half a
  /// dinner, and 500 two days ago.
  Ledger book() {
    final book = demoLedger();
    final c = book.entryCommands;
    c.add(
      transfer(
        'back',
        DateTime.utc(2026, 8, 20),
        3200,
        from: 'lent',
        to: 'bank',
      ),
    );
    c.add(transfer('ticket', DateTime.utc(2026, 9, 4), 800, note: '電影票'));
    c.add(
      Entry(
        id: 'dinner',
        date: DateTime.utc(2026, 9, 28),
        type: EntryType.expense,
        amount: 1000,
        account: 'bank',
        category: '飲食日常',
        merchant: '鼎泰豐',
        group: 'dinner',
      ),
    );
    c.add(transfer('half', DateTime.utc(2026, 9, 28), 500, group: 'dinner'));
    c.add(transfer('lunch', DateTime.utc(2026, 10, 2), 500));
    return book;
  }

  Future<void> open(WidgetTester tester, {Ledger? start}) async {
    ledger = start ?? book();
    await show(tester, 390, 1, book: ledger);
    await go(tester, ['更多', '代墊與借貸', '代墊朋友']);
  }

  testWidgets('what they owe is listed sum by sum, named by its note or the '
      'spending it was part of, long waits in gold', (tester) async {
    await open(tester);
    expect(ledger.balanceService.balance('lent'), 1800);
    expect(find.text('還欠你'), findsOneWidget);
    expect(find.text('1,800'), findsOneWidget);
    expect(find.text('3 筆還沒收回 · 最久 30 天'), findsOneWidget);
    expect(find.text('還沒收回'), findsOneWidget);
    expect(find.text('電影票'), findsWidgets);
    expect(find.text('鼎泰豐'), findsWidgets, reason: 'half of a dinner');
    expect(find.text('代墊'), findsWidgets, reason: 'no note, no spending');
    expect(find.text('30 天'), findsOneWidget);
    expect(find.text('6 天'), findsOneWidget);
    expect(find.text('2 天'), findsOneWidget);
    // Everything with them, paid back in green with a minus.
    expect(find.text('往來紀錄'), findsOneWidget);
    expect(find.text('−3,200'), findsOneWidget);
  });

  testWidgets('a sum partly paid back shows what is left and of how much', (
    tester,
  ) async {
    final partly = book();
    partly.entryCommands.add(
      transfer(
        'some',
        DateTime.utc(2026, 10, 3),
        300,
        from: 'lent',
        to: 'bank',
      ),
    );
    await open(tester, start: partly);
    // The oldest is paid back first: 300 of the ticket's 800.
    // 800 - 300 = 500 left: partly settled, in the list still owed and
    // in the history alike.
    expect(find.text('9/4 · 部分收回 · 共 800'), findsOneWidget);
    expect(find.text('9/4 · 部分收回'), findsOneWidget);
    expect(find.text('500'), findsWidgets);
    expect(find.text('1,500'), findsOneWidget);
  });

  testWidgets('收回 opens the composer on all they owe, and saving clears '
      'the page', (tester) async {
    await open(tester);
    await go(tester, ['收回']);
    expect(find.byKey(Keys.save), findsOneWidget);
    await tester.tap(find.byKey(Keys.save));
    await tester.pumpAndSettle();
    expect(ledger.balanceService.balance('lent'), 0);
    final back = ledger.entries.all.last;
    expect((back.account, back.to, back.amount), ('lent', 'bank', 1800));
    expect(find.text('沒有待收回的'), findsOneWidget);
    expect(find.text('還沒收回'), findsNothing);
  });

  testWidgets('幫忙付 opens the composer from the main account to them, '
      'with no amount yet', (tester) async {
    await open(tester);
    await go(tester, ['幫忙付']);
    await tester.tap(find.byKey(Keys.save));
    await tester.pump();
    expect(find.text('請輸入金額'), findsOneWidget);
    await tester.tap(find.byTooltip('金額'));
    await tester.pumpAndSettle();
    for (final key in ['2', '5', '0', '完成']) {
      await tester.tap(find.byKey(Keys.calc(key)));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(Keys.save));
    await tester.pumpAndSettle();
    // Paid for them: all of it is theirs, owed, none one's own spending.
    final made = ledger.entries.all.last;
    expect(
      (made.type, made.account, made.to, made.amount),
      (EntryType.transfer, ledger.accounts.main, 'lent', 250),
    );
    expect(
      ledger.entries.all.where(
        (e) =>
            e.type == EntryType.expense &&
            e.date == made.date &&
            e.amount == 125,
      ),
      isEmpty,
    );
    expect(ledger.balanceService.balance('lent'), 2050);
    expect(find.text('4 筆還沒收回 · 最久 30 天'), findsOneWidget);
  });

  testWidgets('tapping a sum owed opens the entry it came with', (
    tester,
  ) async {
    await open(tester);
    await go(tester, ['鼎泰豐']);
    // The dinner the half was part of, not the half on its own.
    expect(find.textContaining('1,000'), findsWidgets);
    expect(find.text('鼎泰豐'), findsWidgets);
  });

  testWidgets('改名 keeps the new name, trimmed; 取消 keeps the old one', (
    tester,
  ) async {
    await open(tester);
    await go(tester, ['~更多選項', '改名']);
    expect(find.byType(DialogBlock), findsOneWidget);
    await tester.enterText(find.byType(TextField), '小明');
    await go(tester, ['取消']);
    expect(ledger.account('lent').name, '代墊朋友');

    await go(tester, ['~更多選項', '改名']);
    await tester.enterText(find.byType(TextField), '  小明 ');
    await go(tester, [Words.done]);
    expect(ledger.account('lent').name, '小明');
    expect(find.text('小明'), findsWidgets);
  });

  testWidgets('封存 someone who still owes says why and asks; 保留 keeps them '
      '(DEB-01)', (tester) async {
    await open(tester);
    await go(tester, ['~更多選項', '封存']);
    expect(find.text('還有沒結清的款項，結清後才能封存'), findsOneWidget);
    expect(find.text('要記一筆結清，再封存「代墊朋友」嗎？'), findsOneWidget);
    await tester.tap(find.byKey(Keys.confirmCancel));
    await tester.pumpAndSettle();
    expect(ledger.account('lent').archived, isFalse);
    // 800 + 500 + 500 still owed.
    expect(ledger.balanceService.balance('lent'), 1800);
    expect(find.text('還沒收回'), findsOneWidget, reason: 'still on the page');
  });

  testWidgets('review 35: 結清封存 settles what is owed into the account '
      'picked, then archives; 復原 takes both back', (tester) async {
    await open(tester);
    final bank = ledger.balanceService.balance('bank');
    final count = ledger.entries.all.length;
    await go(tester, ['~更多選項', '封存']);
    await tester.tap(find.byKey(Keys.confirm));
    await tester.pumpAndSettle();
    expect(find.text('餘額轉到哪個帳戶'), findsOneWidget);
    await go(tester, ['日常銀行']);
    expect(ledger.account('lent').archived, isTrue);
    expect(ledger.balanceService.balance('lent'), 0);
    // The 1,800 owed comes back into the bank.
    expect(ledger.balanceService.balance('bank'), bank + 1800);
    expect(ledger.entries.all.length, count + 1);
    expect(find.text('已封存「代墊朋友」'), findsOneWidget);
    await tester.tap(find.byKey(Keys.snack('復原')));
    await tester.pumpAndSettle();
    expect(ledger.account('lent').archived, isFalse);
    expect(ledger.balanceService.balance('lent'), 1800);
    expect(ledger.balanceService.balance('bank'), bank);
    expect(ledger.entries.all.length, count);
  });

  testWidgets('D121: someone lent money dated 400 days ahead is settled on '
      'that day, beyond the year ahead, and archived; another person is not '
      'offered to settle into', (tester) async {
    final today = DateTime.utc(2026, 10, 4);
    // 2026-10-04 + 400 days = 2027-11-08, beyond 2026-10-04 + 365 days =
    // 2027-10-04, as a clock set forward and corrected, or a restore, can
    // leave in the book.
    final far = DateTime.utc(2027, 11, 8);
    final start = Ledger(
      today: today,
      accounts: const [
        Account('bank', '日常銀行', AccountKind.bank, 100000),
        Account('lent', '代墊朋友', AccountKind.receivable, 0),
        Account('other', '阿安', AccountKind.receivable, 0),
      ],
      categories: const [],
      entries: [transfer('far', far, 5000)],
      holdings: const [],
      budgets: const [],
      recurring: const [],
    );
    await open(tester, start: start);
    await go(tester, ['~更多選項', '封存']);
    await tester.tap(find.byKey(Keys.confirm));
    await tester.pumpAndSettle();
    expect(find.text('餘額轉到哪個帳戶'), findsOneWidget);
    expect(find.text('阿安'), findsNothing);
    await go(tester, ['日常銀行']);
    expect(ledger.account('lent').archived, isTrue);
    final settled = ledger.balanceService.entriesOf('lent').first;
    expect(
      (settled.type, settled.date, settled.amount, settled.to),
      (EntryType.transfer, far, 5000, 'bank'),
    );
    expect(ledger.balanceService.finalBalance('lent'), 0);
    // Today's balances as they were: both entries are 預定.
    expect(ledger.balanceService.balance('bank'), 100000);
  });

  testWidgets('review 35: with no account of their currency it says so, and '
      'offers to add one or keep them', (tester) async {
    final start = book();
    for (final a in [...start.accounts.open]) {
      if (!a.kind.isDebt &&
          a.kind != AccountKind.receivable &&
          a.currency == 'TWD') {
        start.accountCommands.updateAccount(a.copyWith(archived: true));
      }
    }
    await open(tester, start: start);
    await go(tester, ['~更多選項', '封存']);
    await tester.tap(find.byKey(Keys.confirm));
    await tester.pumpAndSettle();
    expect(find.text('沒有新台幣的帳戶可以結清'), findsOneWidget);
    expect(find.text('要先新增一個同幣別的帳戶來結清，還是保留「代墊朋友」不封存？'), findsOneWidget);
    // 保留: nothing changes.
    await tester.tap(find.byKey(Keys.confirmCancel));
    await tester.pumpAndSettle();
    expect(ledger.account('lent').archived, isFalse);
    expect(ledger.balanceService.balance('lent'), 1800);

    // 新增帳戶: the account form, then the account added is picked.
    await go(tester, ['~更多選項', '封存']);
    await tester.tap(find.byKey(Keys.confirm));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Keys.confirm));
    await tester.pumpAndSettle();
    expect(find.text('新增帳戶'), findsWidgets);
    await tester.enterText(find.byType(TextField).first, '新帳戶');
    await go(tester, ['儲存']);
    expect(find.text('餘額轉到哪個帳戶'), findsOneWidget);
    await go(tester, ['新帳戶']);
    expect(ledger.account('lent').archived, isTrue);
    final added = ledger.accounts.open.singleWhere((a) => a.name == '新帳戶');
    expect(ledger.balanceService.balance(added.id), 1800);
  });

  testWidgets('封存 someone with entries, all paid back, tucks them away and '
      'keeps the entries, with 復原 (D82)', (tester) async {
    await open(tester);
    await go(tester, ['收回']);
    await tester.tap(find.byKey(Keys.save));
    await tester.pumpAndSettle();
    expect(ledger.balanceService.balance('lent'), 0);
    final count = ledger.entries.all.length;
    await go(tester, ['~更多選項', '封存']);
    expect(find.byKey(Keys.confirm), findsNothing);
    expect(ledger.account('lent').archived, isTrue);
    expect(ledger.entries.all.length, count);
    expect(find.text('還沒收回'), findsNothing, reason: 'back on the list');
    expect(find.text('已封存「代墊朋友」'), findsOneWidget);
    await tester.tap(find.byKey(Keys.snack('復原')));
    await tester.pumpAndSettle();
    expect(ledger.account('lent').archived, isFalse);
  });

  testWidgets('刪除 someone with nothing recorded removes them, with 復原', (
    tester,
  ) async {
    await open(tester, start: demoLedger());
    expect(find.text('沒有待收回的'), findsOneWidget);
    await go(tester, ['~更多選項', '刪除']);
    expect(find.byKey(Keys.confirm), findsNothing);
    expect(ledger.accounts.contains('lent'), isFalse);
    expect(find.text('已刪除「代墊朋友」'), findsOneWidget);
    await tester.tap(find.byKey(Keys.snack('復原')));
    await tester.pumpAndSettle();
    expect(ledger.accounts.contains('lent'), isTrue);
  });

  testWidgets('someone they paid for: 你欠 them, and nothing to 收回', (
    tester,
  ) async {
    final owing = demoLedger();
    owing.entryCommands.add(
      transfer(
        'paid',
        DateTime.utc(2026, 10, 1),
        5000,
        from: 'lent',
        to: 'bank',
      ),
    );
    await open(tester, start: owing);
    expect(find.text('你欠代墊朋友'), findsOneWidget);
    expect(find.text('1,800'), findsOneWidget);
    expect(find.text('收回'), findsWidgets, reason: 'the row of paid back');
    final count = ledger.entries.all.length;
    await go(tester, ['幫忙付']);
    await tester.tap(find.byKey(Keys.save));
    await tester.pump();
    expect(ledger.entries.all.length, count, reason: 'no amount given');
  });

  testWidgets('review 41: a person kept in US\$ is shown in US\$ with its '
      'cents, a sum paid in NT\$ for them in NT\$, and how much of it is '
      'back read in their currency', (tester) async {
    final start = demoLedger()
      ..accountCommands.addAccount(
        const Account(
          'amy',
          'AmyUSD',
          AccountKind.receivable,
          0,
          currency: 'USD',
        ),
      );
    // NT\$3,200 paid for her, US\$100.00 on her account; US\$60.00 of
    // it paid back into the bank, NT\$1,926 there.
    start.entryCommands
      ..add(
        Entry(
          id: 'paid',
          date: DateTime.utc(2026, 9, 1),
          type: EntryType.transfer,
          amount: 3200,
          received: 10000,
          account: 'bank',
          category: transferCategory,
          to: 'amy',
          note: '機票',
        ),
      )
      ..add(
        Entry(
          id: 'repaid',
          date: DateTime.utc(2026, 9, 10),
          type: EntryType.transfer,
          amount: 6000,
          received: 1926,
          account: 'amy',
          category: transferCategory,
          to: 'bank',
        ),
      );
    await show(tester, 390, 1, book: start);
    await go(tester, ['更多', '代墊與借貸']);
    // The square: 10,000 - 6,000 = 4,000 cents, US\$40.00, not 4,000.
    expect(
      find.bySemanticsLabel(RegExp('^AmyUSD，欠你 USD 40.00，')),
      findsOneWidget,
    );
    await go(tester, ['AmyUSD']);
    expect(find.text('USD 40.00'), findsWidgets); // the hero, the owed row
    // 4,000 of her 10,000 cents left: 部分收回 (comparing the NT\$3,200
    // paid with the 4,000 cents left once read 未收回), of US\$100.00.
    expect(find.textContaining('部分收回 · 共 USD 100.00'), findsOneWidget);
    expect(find.text('−USD 60.00'), findsOneWidget); // paid back, hers
    expect(find.text('3,200'), findsOneWidget); // paid from the bank, NT\$
    expect(find.text('4,000'), findsNothing);
    expect(find.text('10,000'), findsNothing);
  });
}
