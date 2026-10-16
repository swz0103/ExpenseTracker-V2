import 'dart:io';

import 'package:app_core/app_core.dart';
import 'package:backup_security/backup_security.dart';
import 'package:expense_tracker/src/book/looks.dart';
import 'package:expense_tracker/src/book/vault_journal.dart';
import 'package:expense_tracker/src/demo/ledger.dart';
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
      modules: [looksSchema],
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
    expect(ledger.accounts, isEmpty);
    expect(
      [for (final c in ledger.categoriesFor(income: false)) c.name],
      contains('飲食日常'),
    );
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
    final dinner = ledger
        .entriesIn(2026, 10)
        .firstWhere((e) => e.note == '晚餐');
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

  test('changes not kept yet are refused and undone', () async {
    final ledger = await create();
    ledger.setBudget('飲食日常', 5000);
    expect(ledger.budgets, hasLength(1));
    await ledger.settled;
    expect(
      ledger.problem.value,
      const AppFailure(FailureKind.rejected, 'app.not-kept'),
    );
    expect(ledger.budgets, isEmpty);
  });
}
