import 'dart:io';

import 'package:core/app_core.dart';
import 'package:core/foundation_values.dart';
import 'package:expense_tracker/src/book/vault_journal.dart';
import 'package:expense_tracker/src/model/exchange.dart';
import 'package:expense_tracker/src/model/journal.dart';
import 'package:expense_tracker/src/model/ledger.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:vault/backup_security.dart';
import 'package:vault/ledger_vault.dart';

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

  test('a CSV of every kind of entry is kept, with its new accounts', () async {
    final ledger = await create();
    const text =
        '日期,類型,金額,帳戶,轉入帳戶,分類,商家,標籤,備註,代號,股數,手續費,稅,分期\n'
        '2026-09-01,收入,52000,銀行帳戶,,薪資收入,,,薪水\n'
        '2026-09-02,支出,300,玉山信用卡,,餐飲=200;居家生活=100,好市多\n'
        '2026-09-03,轉帳,1000,銀行帳戶,零錢現金,,,,提款,,,15\n'
        '2026-09-04,買進,60000,銀行帳戶,,,,,,0050,1000,85\n'
        '2026-09-05,賣出,30000,銀行帳戶,,,,,,0050,500,42,90\n'
        '2026-09-06,股息,1200,銀行帳戶,,,,,,0050,,,25\n'
        '2026-09-07,退款,100,玉山信用卡,,,好市多,,退貨\n'
        '2026-10-02,轉帳,200,銀行帳戶,玉山信用卡,,,,繳卡費\n';
    final bank = ledger.accounts.firstWhere((a) => a.name == '銀行帳戶');
    final found = importCsv(ledger, text, fallback: bank.id);
    expect(found.problems, isEmpty);
    expect(found.entries, hasLength(8));
    addImport(ledger, found);
    final again = await reopen(ledger);
    expect(again.accounts.map((a) => a.name), containsAll(['玉山信用卡', '零錢現金']));
    expect(again.categories.map((c) => c.name), contains('餐飲'));
    expect(again.entries, hasLength(8));
    expect(VaultJournal(open!, clock: clock).mismatches(again), isEmpty);
    expect(shown(again, '0050').$1, 500);
    final card = again.accounts.firstWhere((a) => a.name == '玉山信用卡');
    expect(again.balance(card.id), -300 + 100 + 200);
    expect(
      importCsv(again, toCsv(again, again.entries), fallback: bank.id).entries,
      isEmpty,
    );
  });

  test('a deleted entry stays in the trash until restored', () async {
    var ledger = await create();
    final cash = Account(ledger.newId(), '錢包', AccountKind.cash, 1000);
    ledger.addAccount(cash);
    ledger.add(spend(ledger, cash.id, 120, note: '早餐'));
    await ledger.settled;
    final entry = ledger.entriesIn(2026, 10).single;
    ledger.remove(entry.id);
    ledger = await reopen(ledger);
    expect(ledger.entriesIn(2026, 10), isEmpty);
    final trashed = ledger.trash.single;
    expect((trashed.entry.amount, trashed.entry.note), (120, '早餐'));
    expect(trashed.on, DateTime.utc(2026, 10, 3));
    expect(VaultJournal(open!, clock: clock).mismatches(ledger), isEmpty);

    ledger.restoreTrashed(trashed);
    ledger = await reopen(ledger);
    expect(ledger.trash, isEmpty);
    expect(ledger.entriesIn(2026, 10).single.note, '早餐');
    expect(ledger.balance(cash.id), 880);
  });

  test('a receipt photo stays with its entry through an edit', () async {
    var ledger = await create();
    final cash = Account(ledger.newId(), '錢包', AccountKind.cash, 1000);
    ledger.addAccount(cash);
    ledger.add(spend(ledger, cash.id, 120, note: '午餐'));
    await ledger.settled;
    var entry = ledger.entriesIn(2026, 10).single;
    ledger.setReceipt(entry.id, 'lunch.jpg');
    ledger = await reopen(ledger);
    entry = ledger.entriesIn(2026, 10).single;
    expect(ledger.receiptOf(entry.id), 'lunch.jpg');

    // A changed amount is a correction with a new id.
    ledger.replace(
      Entry(
        id: entry.id,
        date: day,
        type: EntryType.expense,
        amount: 150,
        account: cash.id,
        category: '飲食日常',
        note: '午餐',
      ),
    );
    ledger = await reopen(ledger);
    entry = ledger.entriesIn(2026, 10).single;
    expect(entry.amount, 150);
    expect(ledger.receiptOf(entry.id), 'lunch.jpg');

    ledger.setReceipt(entry.id, null);
    ledger = await reopen(ledger);
    expect(ledger.receiptOf(ledger.entriesIn(2026, 10).single.id), isNull);
  });

  test('on its closing day a statement is still open', () async {
    // The ledger and the screens agree that today's close has not
    // happened yet.
    final closing = FixedClock(UtcInstant(DateTime.utc(2026, 9, 25, 4)));
    final (vaultOpen, _) = await vault.create(password);
    open = vaultOpen;
    var ledger = await VaultJournal(vaultOpen, clock: closing).load();
    final card = Account(
      ledger.newId(),
      '信用卡',
      AccountKind.card,
      0,
      closingDay: 25,
      dueDay: 10,
    );
    ledger.addAccount(card);
    await ledger.settled;
    for (final (amount, date) in [
      (1000, DateTime.utc(2026, 8, 20)),
      (300, DateTime.utc(2026, 9, 25)),
    ]) {
      ledger.add(
        Entry(
          id: ledger.newId(),
          date: date,
          type: EntryType.expense,
          amount: amount,
          account: card.id,
          category: '購物休閒',
        ),
      );
    }
    await ledger.settled;
    open?.close();
    final again = await vault.unlockWithPassword(password);
    open = again;
    ledger = await VaultJournal(again, clock: closing).load();
    final kept = ledger.account(card.id);
    expect(ledger.statement(kept).$2, DateTime.utc(2026, 8, 25));
    expect(ledger.dueFromEntries(kept), 1000);
    expect(ledger.statementDue(kept), ledger.dueFromEntries(kept));
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

    // The bank closes October's statement two days early.
    ledger.moveClose(
      card.id,
      DateTime.utc(2026, 10, 25),
      DateTime.utc(2026, 10, 23),
    );
    ledger = await reopen(ledger);
    final moved = ledger.account(card.id);
    expect(moved.closes, {
      DateTime.utc(2026, 10, 25): DateTime.utc(2026, 10, 23),
    });
    expect(
      moved.closingOn(DateTime.utc(2026, 10, 24)),
      DateTime.utc(2026, 10, 23),
    );
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
      ..setBudget('飲食日常', 6000, warning: 90, carry: true)
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
    expect(ledger.budgetFor('飲食日常').carry, isTrue);
    expect(ledger.budgetFor(Ledger.allSpending).carry, isFalse);
    expect(ledger.budgetFor('飲食日常').since, DateTime.utc(2026, 10));
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
    // Deleted, not just stopped; its bookings stay.
    expect(ledger.recurring, isEmpty);
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

  test('a year of entries loads quickly', () async {
    final ledger = await create();
    final cash = ledger.accounts.firstWhere((a) => a.name == '現金');
    final journal = VaultJournal(open!, clock: clock);
    final entries = [
      for (var i = 0; i < 1200; i++)
        Entry(
          id: ledger.newId(),
          date: DateTime.utc(2025, 10, 3).add(Duration(days: i * 365 ~/ 1200)),
          type: EntryType.expense,
          amount: 50 + i % 400,
          account: cash.id,
          category: '飲食日常',
          note: i.isEven ? '午餐' : '',
          tags: i % 7 == 0 ? const ['家用'] : const [],
        ),
    ];
    final writing = Stopwatch()..start();
    await journal.addEntries(entries);
    writing.stop();
    final loading = Stopwatch()..start();
    final loaded = await journal.load();
    loading.stop();
    // Printed so a slow-down shows in the CI log before it fails.
    print(
      'Wrote 1200 entries in ${writing.elapsedMilliseconds} ms, '
      'loaded them in ${loading.elapsedMilliseconds} ms',
    );
    expect(loaded.balance(cash.id), -entries.fold(0, (s, e) => s + e.amount));
    // About 40 ms on CI (2026-10); a phone may take several times that.
    expect(loading.elapsed, lessThan(const Duration(seconds: 1)));
  });

  test('what the review found stays fixed after reopening', () async {
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
    ledger
      ..add(spend(ledger, card.id, 30000, installments: 3, note: '手機'))
      ..add(
        Entry(
          id: ledger.newId(),
          date: day,
          type: EntryType.income,
          amount: 800,
          account: bank.id,
          category: '其他收入',
          merchant: '舊衣回收',
        ),
      )
      ..add(
        Entry(
          id: ledger.newId(),
          date: day,
          type: EntryType.buy,
          amount: 10000,
          account: bank.id,
          category: '投資',
          holding: '2330',
          shares: 10,
          fee: 20,
          note: '定期定額',
        ),
      )
      ..saveRecurring(
        Recurring(
          id: ledger.newId(),
          name: '串流',
          amount: 390,
          day: 2,
          account: card.id,
          category: '購物休閒',
          start: DateTime.utc(2026, 9, 2),
        ),
      )
      ..saveRecurring(
        Recurring(
          id: ledger.newId(),
          name: '健身房',
          amount: 1200,
          day: 20,
          account: bank.id,
          category: '購物休閒',
          start: DateTime.utc(2026, 9, 20),
        ),
      );

    ledger = await reopen(ledger);
    final entries = ledger.entriesIn(2026, 10);
    Entry of(EntryType type) => entries.firstWhere((e) => e.type == type);
    expect(of(EntryType.income).merchant, '舊衣回收');
    expect(of(EntryType.buy).note, '定期定額');
    final stream = ledger.recurring.firstWhere((r) => r.name == '串流');
    final gym = ledger.recurring.firstWhere((r) => r.name == '健身房');
    ledger
      ..confirm(stream)
      ..removeRecurring(gym.id)
      ..remove(entries.firstWhere((e) => e.installments == 3).id);

    ledger = await reopen(ledger);
    // A card booking counts as booked, so it is not offered again.
    expect(ledger.pendingDate(ledger.recurring.single), isNull);
    expect([for (final r in ledger.recurring) r.name], ['串流']);
    // A purchase in instalments can be deleted.
    final left = ledger.entriesIn(2026, 10);
    expect(left.where((e) => e.installments == 3), isEmpty);
    expect(left.where((e) => e.recurring != null), hasLength(1));
  });

  test('a card charge edited later stays on the card', () async {
    var ledger = await create();
    final card = Account(
      ledger.newId(),
      '信用卡',
      AccountKind.card,
      0,
      closingDay: 25,
      dueDay: 10,
    );
    ledger.addAccount(card);
    await ledger.settled;
    Entry charge(String id, int amount) => Entry(
      id: id,
      date: DateTime.utc(2026, 9, 20),
      type: EntryType.expense,
      amount: amount,
      account: card.id,
      category: '購物休閒',
    );
    ledger.add(charge(ledger.newId(), 1500));
    ledger = await reopen(ledger);
    final kept = ledger.entriesIn(2026, 9).single;
    ledger.replace(charge(kept.id, 1800));

    ledger = await reopen(ledger);
    expect(ledger.entriesIn(2026, 9).single.amount, 1800);
    expect(ledger.balance(card.id), -1800);
    final account = ledger.account(card.id);
    expect(ledger.statementDue(account), ledger.dueFromEntries(account));
  });

  test('a refused change leaves the book as it was', () async {
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
    // Paying a card with a fee is refused by the ledger.
    ledger.add(
      Entry(
        id: ledger.newId(),
        date: day,
        type: EntryType.transfer,
        amount: 1000,
        account: bank.id,
        to: card.id,
        category: '轉帳',
        fee: 15,
      ),
    );
    await ledger.settled;
    expect(ledger.problem.value, isNotNull);
    ledger.problem.value = null;
    expect(ledger.entriesIn(day.year, day.month), isEmpty);
    expect(ledger.balance(bank.id), 50000);

    ledger = await reopen(ledger);
    expect(ledger.entriesIn(day.year, day.month), isEmpty);
  });

  test('a sale at average cost matches the ledger', () async {
    var ledger = await create();
    final bank = Account(ledger.newId(), '證券戶', AccountKind.bank, 500000);
    ledger.addAccount(bank);
    await ledger.settled;
    Entry trade(EntryType type, int amount, int shares, DateTime on) => Entry(
      id: ledger.newId(),
      date: on,
      type: type,
      amount: amount,
      account: bank.id,
      category: '投資',
      holding: '0050',
      shares: shares,
      fee: 20,
      average: type == EntryType.sell,
    );
    ledger
      ..add(trade(EntryType.buy, 58200, 1000, DateTime.utc(2026, 9, 1)))
      ..add(trade(EntryType.buy, 30000, 500, DateTime.utc(2026, 9, 15)))
      ..add(trade(EntryType.sell, 35000, 500, day));

    ledger = await reopen(ledger);
    expect(ledger.holding('0050')!.shares, 1000);
    expect(held('0050'), shown(ledger, '0050'));
  });

  test("a card's new closing day is kept", () async {
    var ledger = await create();
    final card = Account(
      ledger.newId(),
      '信用卡',
      AccountKind.card,
      0,
      closingDay: 25,
      dueDay: 10,
    );
    ledger.addAccount(card);
    await ledger.settled;
    ledger.updateAccount(card.copyWith(closingDay: 5, dueDay: 20));

    ledger = await reopen(ledger);
    final kept = ledger.account(card.id);
    expect((kept.closingDay, kept.dueDay), (5, 20));
    expect(ledger.statementDue(kept), ledger.dueFromEntries(kept));
  });
}
