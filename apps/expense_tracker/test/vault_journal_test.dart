import 'dart:io';

import 'package:app_core/app_core.dart';
import 'package:backup_security/backup_security.dart';
import 'package:expense_tracker/src/book/journal.dart';
import 'package:expense_tracker/src/book/vault_journal.dart';
import 'package:expense_tracker/src/model/ledger.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger_vault/ledger_vault.dart';

/// The screens' ledger on the real encrypted store: every change is kept
/// as ledger commands and comes back after closing and reopening.
void main() {
  const password = 'correct horse battery';
  final clock = FixedClock(UtcInstant(DateTime.utc(2026, 10, 3, 4)));
  final day = DateTime.utc(2026, 10, 2);
  late Directory directory;
  late LedgerVault vault;
  OpenVault? open;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('journal-');
    vault = LedgerVault(
      directory,
      codec: KeyringCodec(kdf: PasswordKdf.insecureForTests),
    );
  });

  tearDown(() {
    open?.close();
    open = null;
    directory.deleteSync(recursive: true);
  });

  Future<Ledger> create() async {
    final (vaultOpen, _) = await vault.create(password);
    open = vaultOpen;
    return VaultJournal(vaultOpen, clock: clock).load();
  }

  /// Closes the ledger and opens it again from the file.
  Future<Ledger> reopen(Ledger ledger) async {
    await ledger.settled;
    expect(ledger.problem.value, isNull);
    open?.close();
    final again = await vault.unlockWithPassword(password);
    open = again;
    return VaultJournal(again, clock: clock).load();
  }

  /// The ledger's own shares and cost of [code], to hold the screens'
  /// replay of the same trades to.
  (int, int)? held(String code) =>
      VaultJournal(open!, clock: clock).positions()[code];

  /// The shares and cost of [code] as the screens replay them.
  (int, int) shown(Ledger ledger, String code) {
    final holding = ledger.holding(code)!;
    return (holding.shares, holding.cost);
  }

  Entry spend(
    Ledger ledger,
    String account,
    int amount, {
    String category = '飲食日常',
    String note = '',
    String merchant = '',
    List<String> tags = const [],
    int installments = 0,
  }) => Entry(
    id: ledger.newId(),
    date: day,
    type: EntryType.expense,
    amount: amount,
    account: account,
    category: category,
    note: note,
    merchant: merchant,
    tags: tags,
    installments: installments,
  );

  test('accounts and entries survive reopening', () async {
    var ledger = await create();
    expect([for (final a in ledger.accounts) a.name], ['現金', '銀行帳戶']);
    expect([
      for (final c in ledger.categoriesFor(income: false)) c.name,
    ], contains('飲食日常'));
    final cash = Account(ledger.newId(), '錢包', AccountKind.cash, 1000);
    final bank = Account(
      ledger.newId(),
      '薪轉',
      AccountKind.bank,
      50000,
      icon: 'safe',
    );
    ledger
      ..addAccount(cash)
      ..addAccount(bank);
    await ledger.settled;
    ledger
      ..add(
        spend(
          ledger,
          cash.id,
          120,
          note: '早餐',
          merchant: '早餐店',
          tags: const ['家用'],
        ),
      )
      ..add(
        Entry(
          id: ledger.newId(),
          date: day,
          type: EntryType.transfer,
          amount: 3000,
          account: bank.id,
          to: cash.id,
          category: '轉帳',
          fee: 15,
        ),
      )
      ..add(
        Entry(
          id: ledger.newId(),
          date: day,
          type: EntryType.income,
          amount: 52000,
          account: bank.id,
          category: '薪資收入',
        ),
      );

    ledger = await reopen(ledger);
    expect(ledger.balance(cash.id), 1000 - 120 + 3000);
    expect(ledger.balance(bank.id), 50000 - 3015 + 52000);
    expect(ledger.account(bank.id).icon, 'safe');
    expect(ledger.expense(2026, 10), 135);
    expect(ledger.income(2026, 10), 52000);
    final breakfast = ledger
        .entriesIn(2026, 10)
        .firstWhere((e) => e.note == '早餐');
    expect(breakfast.merchant, '早餐店');
    expect(breakfast.tags, ['家用']);

    ledger.replace(
      Entry(
        id: breakfast.id,
        date: day,
        type: EntryType.expense,
        amount: 150,
        account: cash.id,
        category: '飲食日常',
        note: '早餐和咖啡',
        merchant: '早餐店',
        tags: const ['家用'],
      ),
    );
    final transfer = ledger
        .entriesIn(2026, 10)
        .firstWhere((e) => e.type == EntryType.transfer);
    ledger.remove(transfer.id);
    ledger.setBalance(cash.id, 2000);

    ledger = await reopen(ledger);
    expect(ledger.entriesIn(2026, 10), hasLength(2));
    expect(ledger.expense(2026, 10), 150);
    expect(ledger.balance(cash.id), 2000);
    expect(ledger.balance(bank.id), 50000 + 52000);
    final edited = ledger
        .entriesIn(2026, 10)
        .firstWhere((e) => e.type == EntryType.expense);
    expect(edited.note, '早餐和咖啡');

    ledger.updateAccount(ledger.account(cash.id).copyWith(archived: true));
    ledger = await reopen(ledger);
    expect(ledger.account(cash.id).archived, isTrue);
  });

  test('quick edits and a delete of one entry are kept in order', () async {
    var ledger = await create();
    final cash = Account(ledger.newId(), '錢包', AccountKind.cash, 1000);
    ledger.addAccount(cash);
    await ledger.settled;
    ledger.add(spend(ledger, cash.id, 100));

    ledger = await reopen(ledger);
    final kept = ledger.entriesIn(2026, 10).single;
    Entry edited(String id, int amount) => Entry(
      id: id,
      date: day,
      type: EntryType.expense,
      amount: amount,
      account: cash.id,
      category: '飲食日常',
    );
    ledger
      ..replace(edited(kept.id, 150))
      ..replace(edited(kept.id, 170));

    ledger = await reopen(ledger);
    final twice = ledger.entriesIn(2026, 10).single;
    expect(twice.amount, 170);
    ledger
      ..replace(edited(twice.id, 200))
      ..remove(twice.id);

    ledger = await reopen(ledger);
    expect(ledger.entriesIn(2026, 10), isEmpty);
    expect(ledger.balance(cash.id), 1000);
  });

  test('a foreign account keeps its currency and its NT\$ worth', () async {
    var ledger = await create();
    final bank = Account(ledger.newId(), '薪轉', AccountKind.bank, 50000);
    final usd = Account(
      ledger.newId(),
      '美元帳戶',
      AccountKind.bank,
      10000,
      currency: 'USD',
    );
    ledger
      ..addAccount(bank)
      ..addAccount(usd);
    await ledger.settled;
    ledger
      ..add(
        Entry(
          id: ledger.newId(),
          date: day,
          type: EntryType.expense,
          amount: 1250,
          account: usd.id,
          category: '飲食日常',
          home: 401,
        ),
      )
      ..add(
        Entry(
          id: ledger.newId(),
          date: day,
          type: EntryType.transfer,
          amount: 3210,
          account: bank.id,
          to: usd.id,
          category: '轉帳',
          received: 10000,
        ),
      );

    ledger = await reopen(ledger);
    final kept = ledger.account(usd.id);
    expect(kept.currency, 'USD');
    expect(ledger.balance(usd.id), 10000 - 1250 + 10000);
    expect(ledger.balance(bank.id), 50000 - 3210);
    expect(ledger.expense(2026, 10), 401);
    final entries = ledger.entriesIn(2026, 10);
    final spent = entries.firstWhere((e) => e.type == EntryType.expense);
    expect((spent.amount, spent.home), (1250, 401));
    final moved = entries.firstWhere((e) => e.type == EntryType.transfer);
    expect((moved.amount, moved.received), (3210, 10000));

    // Without a rate the foreign balance stays out of the totals.
    expect(ledger.unrated, [kept]);
    expect(ledger.assets, 50000 - 3210);
  });

  test('cards keep their terms, charges, instalments and payments', () async {
    var ledger = await create();
    final bank = Account(ledger.newId(), '薪轉', AccountKind.bank, 50000);
    final card = Account(
      ledger.newId(),
      '信用卡',
      AccountKind.card,
      0,
      closingDay: 25,
      dueDay: 10,
      limit: 80000,
    );
    ledger
      ..addAccount(bank)
      ..addAccount(card);
    await ledger.settled;
    ledger
      ..add(spend(ledger, card.id, 30000, category: '購物休閒', installments: 3))
      ..add(spend(ledger, card.id, 800, note: '晚餐'))
      ..add(
        Entry(
          id: ledger.newId(),
          date: day,
          type: EntryType.transfer,
          amount: 800,
          account: bank.id,
          to: card.id,
          category: '轉帳',
        ),
      );

    ledger = await reopen(ledger);
    final kept = ledger.account(card.id);
    expect((kept.closingDay, kept.dueDay, kept.limit), (25, 10, 80000));
    final purchase = ledger
        .entriesIn(2026, 10)
        .firstWhere((e) => e.amount == 30000);
    expect(purchase.installments, 3);
    final dinner = ledger.entriesIn(2026, 10).firstWhere((e) => e.note == '晚餐');
    expect(ledger.balance(bank.id), 50000 - 800);

    ledger.add(
      Entry(
        id: ledger.newId(),
        date: day,
        type: EntryType.income,
        amount: 300,
        account: card.id,
        category: '飲食日常',
        refundOf: dinner.id,
      ),
    );
    ledger = await reopen(ledger);
    expect(ledger.expense(2026, 10), 30000 + 800 - 300);
    final refund = ledger
        .entriesIn(2026, 10)
        .firstWhere((e) => e.refundOf != null);
    ledger.remove(refund.id);
    ledger = await reopen(ledger);
    expect(ledger.expense(2026, 10), 30000 + 800);
  });

  test('an import refused part way keeps what came before', () async {
    final ledger = await create();
    final cash = Account(ledger.newId(), '錢包', AccountKind.cash, 1000);
    ledger.addAccount(cash);
    await ledger.settled;
    ledger.addAll([
      spend(ledger, cash.id, 100),
      spend(ledger, 'no-such-account', 200),
      spend(ledger, cash.id, 300),
    ]);
    await ledger.settled;
    final partly = ledger.problem.value! as PartlyKept;
    expect((partly.kept, partly.total), (1, 3));
    expect([for (final e in ledger.entriesIn(2026, 10)) e.amount], [100]);
  });

  test("a card's statement due matches the ledger's billing", () async {
    var ledger = await create();
    final bank = Account(ledger.newId(), '薪轉', AccountKind.bank, 50000);
    final card = Account(
      ledger.newId(),
      '信用卡',
      AccountKind.card,
      0,
      closingDay: 25,
      dueDay: 10,
    );
    ledger
      ..addAccount(bank)
      ..addAccount(card);
    await ledger.settled;
    Entry charge(int amount, DateTime date, {int installments = 0}) => Entry(
      id: ledger.newId(),
      date: date,
      type: EntryType.expense,
      amount: amount,
      account: card.id,
      category: '購物休閒',
      installments: installments,
    );
    ledger
      ..add(charge(1200, DateTime.utc(2026, 9, 10)))
      ..add(charge(30001, DateTime.utc(2026, 9, 12), installments: 3))
      ..add(charge(700, DateTime.utc(2026, 10, 1)))
      ..add(
        Entry(
          id: ledger.newId(),
          date: day,
          type: EntryType.transfer,
          amount: 500,
          account: bank.id,
          to: card.id,
          category: '轉帳',
        ),
      );

    ledger = await reopen(ledger);
    final kept = ledger.account(card.id);
    // 1,200 and the first instalment, 10,001 with the remainder, less the
    // 500 paid since the statement closed on 9/25.
    expect(ledger.dueFromEntries(kept), 1200 + 10001 - 500);
    expect(ledger.statementDue(kept), ledger.dueFromEntries(kept));
  });

  test('categories, tags and merchants are kept by name', () async {
    var ledger = await create();
    final cash = Account(ledger.newId(), '錢包', AccountKind.cash, 5000);
    ledger
      ..addAccount(cash)
      ..addCategory(const Category('寵物', 'pet', Color(0xFF123456)));
    await ledger.settled;
    ledger.add(spend(ledger, cash.id, 400, category: '寵物', tags: const ['家用']));

    ledger = await reopen(ledger);
    final pet = ledger.category('寵物');
    expect(pet.icon, 'pet');
    expect(pet.color, const Color(0xFF123456));
    ledger
      ..updateCategory('寵物', pet.copyWith(name: '毛孩'))
      ..renameTag('家用', '家庭');

    ledger = await reopen(ledger);
    expect(ledger.entriesIn(2026, 10).single.category, '毛孩');
    expect(ledger.entriesIn(2026, 10).single.tags, ['家庭']);
    ledger.mergeCategory('毛孩', '居家生活');

    ledger = await reopen(ledger);
    expect(ledger.entriesIn(2026, 10).single.category, '居家生活');
    expect([for (final c in ledger.categories) c.name], isNot(contains('毛孩')));
  });

  test('a recurring item in a foreign account keeps its NT\$ worth', () async {
    var ledger = await create();
    final usd = Account(
      ledger.newId(),
      '美元帳戶',
      AccountKind.bank,
      100000,
      currency: 'USD',
    );
    ledger.addAccount(usd);
    await ledger.settled;
    ledger.saveRecurring(
      Recurring(
        id: ledger.newId(),
        name: '訂閱',
        amount: 999,
        day: 2,
        account: usd.id,
        category: '購物休閒',
        start: DateTime.utc(2026, 9, 2),
      ),
    );

    ledger = await reopen(ledger);
    final item = ledger.recurring.single;
    expect(item.amount, 999);
    final booking = ledger.booking(item);
    ledger.add(
      Entry(
        id: ledger.newId(),
        date: booking.date,
        type: booking.type,
        amount: booking.amount,
        account: booking.account,
        category: booking.category,
        note: booking.note,
        recurring: booking.recurring,
        home: 321,
      ),
    );

    ledger = await reopen(ledger);
    final booked = ledger.entriesIn(2026, 10).single;
    expect((booked.recurring, booked.home), (item.id, 321));
    expect(ledger.balance(usd.id), 100000 - 999);
    expect(ledger.expense(2026, 10), 321);
  });

  test('budgets and recurring items are kept', () async {
    var ledger = await create();
    final bank = Account(ledger.newId(), '薪轉', AccountKind.bank, 50000);
    ledger.addAccount(bank);
    await ledger.settled;
    ledger
      ..setBudget('飲食日常', 6000, warning: 90)
      ..setBudget(Ledger.allSpending, 30000)
      ..setBudget('#旅遊', 5000)
      ..add(spend(ledger, bank.id, 1200, tags: ['旅遊']))
      ..saveRecurring(
        Recurring(
          id: ledger.newId(),
          name: '房租',
          amount: 12000,
          day: 5,
          account: bank.id,
          category: '居家生活',
          start: DateTime.utc(2026, 9, 5),
        ),
      );

    ledger = await reopen(ledger);
    expect(ledger.budgetFor('飲食日常').limit, 6000);
    expect(ledger.budgetFor('飲食日常').warning, 90);
    expect(ledger.budgetFor(Ledger.allSpending).limit, 30000);
    expect(ledger.budgetFor('#旅遊').limit, 5000);
    expect(ledger.spentOnTag('旅遊', 2026, 10), 1200);
    ledger.removeBudget('#旅遊');
    ledger = await reopen(ledger);
    expect(ledger.budgetFor('#旅遊').limit, 0);
    expect(ledger.budgetFor('飲食日常').limit, 6000);
    final rent = ledger.recurring.single;
    expect((rent.name, rent.amount, rent.day), ('房租', 12000, 5));
    ledger.confirm(rent);

    ledger = await reopen(ledger);
    List<Entry> rentEntries() => [
      for (final month in const [9, 10])
        for (final e in ledger.entriesIn(2026, month))
          if (e.recurring != null) e,
    ];
    final booked = rentEntries().single;
    expect(booked.recurring, rent.id);
    expect(booked.category, '居家生活');
    expect(ledger.balance(bank.id), 50000 - 1200 - 12000);
    ledger.replace(
      Entry(
        id: booked.id,
        date: booked.date,
        type: booked.type,
        amount: 12500,
        account: booked.account,
        category: booked.category,
        note: booked.note,
        recurring: booked.recurring,
      ),
    );

    ledger = await reopen(ledger);
    expect(rentEntries().single.amount, 12500);
    expect(rentEntries().single.recurring, rent.id);
    ledger
      ..removeBudget('飲食日常')
      ..removeRecurring(rent.id);

    ledger = await reopen(ledger);
    expect([for (final b in ledger.budgets) b.category], [Ledger.allSpending]);
    expect(ledger.recurring.single.active, isFalse);
    expect(rentEntries(), hasLength(1));
  });

  test('a dividend keeps the premium withheld from it', () async {
    var ledger = await create();
    final bank = Account(ledger.newId(), '證券戶', AccountKind.bank, 500000);
    ledger.addAccount(bank);
    await ledger.settled;
    Entry stock(EntryType type, int amount, {int shares = 0, int tax = 0}) =>
        Entry(
          id: ledger.newId(),
          date: day,
          type: type,
          amount: amount,
          account: bank.id,
          category: type == EntryType.dividend ? '股息收入' : '投資',
          holding: '2330',
          shares: shares,
          tax: tax,
        );
    ledger
      ..add(stock(EntryType.buy, 100000, shares: 1000))
      ..add(stock(EntryType.dividend, 30000, tax: 633));

    ledger = await reopen(ledger);
    final paid = ledger
        .entriesIn(2026, 10)
        .firstWhere((e) => e.type == EntryType.dividend);
    expect((paid.amount, paid.tax, paid.dividendNet), (30000, 633, 29367));
    expect(ledger.balance(bank.id), 500000 - 100000 + 29367);
    expect(ledger.dividends(2026, 10), 29367);

    // A capital reduction of 40%: 400 shares and NT$4,000 back.
    ledger.add(stock(EntryType.dividend, 4000, shares: -400));
    ledger = await reopen(ledger);
    expect(shown(ledger, '2330'), (600, 100000 - 4000));
    expect(held('2330'), shown(ledger, '2330'));
    expect(ledger.balance(bank.id), 500000 - 100000 + 29367 + 4000);
    expect(ledger.dividends(2026, 10), 29367);
  });

  test('trades, dividends and splits are kept', () async {
    var ledger = await create();
    final bank = Account(ledger.newId(), '證券戶', AccountKind.bank, 500000);
    ledger.addAccount(bank);
    await ledger.settled;
    Entry trade(
      EntryType type,
      int amount, {
      int shares = 0,
      int fee = 0,
      int tax = 0,
      bool split = false,
      DateTime? date,
    }) => Entry(
      id: ledger.newId(),
      date: date ?? day,
      type: type,
      amount: amount,
      account: bank.id,
      category: type == EntryType.dividend ? '股息收入' : '投資',
      holding: '0050',
      shares: shares,
      fee: fee,
      tax: tax,
      split: split,
    );
    ledger
      ..add(
        trade(
          EntryType.buy,
          58200,
          shares: 1000,
          fee: 50,
          date: DateTime.utc(2026, 9, 1),
        ),
      )
      ..add(
        trade(
          EntryType.buy,
          30000,
          shares: 500,
          fee: 25,
          date: DateTime.utc(2026, 9, 15),
        ),
      );

    ledger = await reopen(ledger);
    expect(ledger.holding('0050')!.shares, 1500);
    expect(ledger.holding('0050')!.cost, 58250 + 30025);
    expect(held('0050'), shown(ledger, '0050'));
    expect(ledger.balance(bank.id), 500000 - 58250 - 30025);
    ledger
      ..add(trade(EntryType.sell, 35000, shares: 500, fee: 30, tax: 105))
      ..add(trade(EntryType.dividend, 1200));

    ledger = await reopen(ledger);
    expect(ledger.holding('0050')!.shares, 1000);
    expect(held('0050'), shown(ledger, '0050'));
    expect(
      ledger.balance(bank.id),
      500000 - 58250 - 30025 + 35000 - 135 + 1200,
    );
    ledger.add(trade(EntryType.dividend, 0, shares: 3000, split: true));

    ledger = await reopen(ledger);
    expect(ledger.holding('0050')!.shares, 4000);
    expect(held('0050'), shown(ledger, '0050'));
    final dividend = ledger
        .entriesIn(2026, 10)
        .firstWhere((e) => e.type == EntryType.dividend && e.amount == 1200);
    ledger.remove(dividend.id);

    ledger = await reopen(ledger);
    expect(ledger.balance(bank.id), 500000 - 58250 - 30025 + 35000 - 135);
    expect(ledger.holding('0050')!.shares, 4000);
  });
}
