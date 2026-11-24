import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:expense_tracker/src/app/ledger_session.dart';
import 'package:expense_tracker/src/core/diagnostics/error_log.dart';
import 'package:expense_tracker/src/core/diagnostics/error_steps.dart';
import 'package:expense_tracker/src/core/ledger/journal/old_shapes.dart';
import 'package:expense_tracker/src/core/ledger/journal/parity.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/ledger/persistence/journal_keeper.dart';
import 'package:expense_tracker/src/core/ledger/persistence/sql_ledger_data_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kernel/kernel.dart';
import 'package:ledger_postings/model/vocabulary.dart';
import 'package:storage/storage.dart';

import 'package:vault/backup_security.dart';
import 'package:vault/ledger_backup.dart';
import 'package:vault/ledger_vault.dart';

import '../../../baseline/baseline_ledger.dart' show entryOf;
import '../../../scenarios/ledger/journal/awkward_book.dart';

void main() {
  late Directory scratch;
  setUp(() => scratch = Directory.systemTemp.createTempSync('keeper-'));
  tearDown(() => scratch.deleteSync(recursive: true));

  /// The kept book of awkward shapes, opened with its journal.
  Future<(Ledger, SqlLedgerDataSource, EncryptedDatabase)> openWithJournal(
    EncryptedDatabase store,
  ) async {
    final source = SqlLedgerDataSource(
      store,
      clock: keptClock,
      keepsJournal: true,
    );
    final ledger = await source.load();
    await source.journal.settled;
    return (ledger, source, store);
  }

  Future<void> settle(Ledger ledger, SqlLedgerDataSource source) async {
    await ledger.settled;
    await source.journal.settled;
  }

  test('a book opened is posted, marked as the records\' own, and in '
      'parity with what the app shows', () async {
    final (_, source, store) = await openWithJournal(keptStore(scratch));
    final keeper = source.journal;
    expect(store.journal.mark, (rules: journalRules, revision: store.revision));
    expect(keeper.lastReplay!.shapes, {
      for (final shape in OldShape.values) shape: 1,
    });
    expect(keeper.lastParity, isA<InParity>());
    // fitting + old shapes, and the opening of each account with one.
    expect(store.journal.intentCount, greaterThan(40));
    expect(keeper.reader.trialBalance().values, everyElement(0));
  });

  test('opened again with its postings up to date, nothing is posted '
      'afresh; a change kept without the journal is', () async {
    final store = keptStore(scratch);
    await openWithJournal(store);
    final again = await openWithJournal(store);
    expect(again.$2.journal.lastReplay, isNull);
    expect(again.$2.journal.lastParity, isA<InParity>());
    // A change the journal did not see moves the revision past its mark.
    store.write((w) => w.drop('entry', 'pay'));
    final third = await openWithJournal(store);
    expect(third.$2.journal.lastReplay, isNotNull);
    expect(store.journal.intent(const IntentId('pay')), isNull);
    expect(third.$2.journal.lastParity, isA<InParity>());
  });

  test('D49: an older version, which knows no journal, opens the file and '
      'writes records; the next opening posts afresh, in parity', () async {
    final store = keptStore(scratch);
    await openWithJournal(store);
    final marked = store.journal.mark!;
    // The layout version an older version checks is the one it knows.
    expect(EncryptedDatabase.schema, 1);
    // As an older version writes: the records alone, through the store.
    final pay = store.row('entry', 'pay')!;
    store.write(
      (w) => w.put('entry', 'pay', pay.body.replaceFirst('52000', '51000')),
    );
    expect(store.revision, marked.revision + 1);
    final (ledger, source, _) = await openWithJournal(store);
    expect(source.journal.lastReplay, isNotNull);
    expect(store.journal.mark, (rules: journalRules, revision: store.revision));
    expect(
      [
        for (final p in store.journal.postingsOfIntent(const IntentId('pay')))
          p.amount,
      ],
      [51000, -51000],
    );
    expect(ledger.entries.byId('pay')!.amount, 51000);
    expect(source.journal.lastParity, isA<InParity>());
  });

  test('D87: a lot of a fraction of a share is kept exactly, as the '
      'holdings count it, kept and posted afresh alike', () async {
    // A new book: the kept one has an old oversold sale, which today's
    // write rules refuse any trade beside.
    final store = EncryptedDatabase.open(
      File('${scratch.path}/new.db'),
      StorageKey.random(),
    );
    addTearDown(store.close);
    final (ledger, source, _) = await openWithJournal(store);
    final bank = ledger.accounts.main;
    ledger.entryCommands.addAll([
      Entry(
        id: 'one',
        date: day(10, 1),
        type: EntryType.buy,
        amount: 100,
        account: bank,
        holding: '9999',
        shares: 1,
      ),
      Entry(
        id: 'more',
        date: day(10, 1),
        type: EntryType.buy,
        amount: 12700,
        account: bank,
        holding: '9999',
        shares: 127,
      ),
      // 1 for every 128 held: 1.0078125 and 127.9921875 shares.
      Entry(
        id: 'odd',
        date: day(10, 2),
        type: EntryType.dividend,
        amount: 0,
        account: bank,
        holding: '9999',
        shares: 1,
      ),
    ]);
    await settle(ledger, source);
    expect(source.journal.lastParity, isA<InParity>());
    final exact = [BigInt.from(1007812500000), BigInt.from(127992187500000)];
    expect([
      for (final l in source.journal.reader.bySub(holdingAccount('9999')))
        l.quantity,
    ], exact);
    // Posted afresh at the next opening: the same, nothing logged.
    store.write((w) => w.put('meta-free', 'x', '{}'));
    final before = ErrorLog.instance.count;
    final (_, again, _) = await openWithJournal(store);
    expect(again.journal.lastReplay, isNotNull);
    expect(ErrorLog.instance.count, before);
    expect(again.journal.lastParity, isA<InParity>());
    expect([
      for (final l in again.journal.reader.bySub(holdingAccount('9999')))
        l.quantity,
    ], exact);
  });

  test('each change kept is posted: an entry added, edited and taken '
      'away; an account and its card days changed', () async {
    final (ledger, source, store) = await openWithJournal(keptStore(scratch));
    final keeper = source.journal;
    final lunch = Entry(
      id: 'lunch',
      date: day(10, 3),
      type: EntryType.expense,
      amount: 180,
      account: 'card',
      category: '飲食',
      installments: 3,
    );
    ledger.entryCommands.add(lunch);
    await settle(ledger, source);
    expect(store.journal.mark!.revision, store.revision);
    // 180 in 3: 60 billed on each of the next three closes (the 20th).
    expect(
      [
        for (final p in store.journal.postingsOfIntent(const IntentId('lunch')))
          if (p.account == moneyAccount('card')) (p.amount, p.date.ymd),
      ],
      [(-60, 20261020), (-60, 20261120), (-60, 20261220)],
    );
    expect(keeper.lastParity, isA<InParity>());

    // The card closes on the 5th from now on, with no history kept: the
    // purchase of 10/3 is billed from 10/5, as the card cycle has it.
    final card = ledger.accounts.all.firstWhere((a) => a.id == 'card');
    ledger.accountCommands.updateAccount(card.copyWith(closingDay: 5));
    await settle(ledger, source);
    expect(
      [
        for (final p in store.journal.postingsOfIntent(const IntentId('lunch')))
          if (p.account == moneyAccount('card')) p.date.ymd,
      ],
      [20261005, 20261105, 20261205],
    );
    expect(keeper.lastParity, isA<InParity>(), reason: '${keeper.lastParity}');

    ledger.entryCommands.replace(
      Entry(
        id: 'lunch',
        date: day(10, 3),
        type: EntryType.expense,
        amount: 90,
        account: 'cash',
        category: '飲食',
      ),
    );
    await settle(ledger, source);
    expect(
      [
        for (final p in store.journal.postingsOfIntent(const IntentId('lunch')))
          (p.account.value, p.amount),
      ],
      // The category's account by its id (D88).
      [('acct:cash', -90), ('cat:spending:c-food', 90)],
    );
    expect(ledger.entryCommands.remove('lunch'), isNotNull);
    await settle(ledger, source);
    expect(store.journal.intent(const IntentId('lunch')), isNull);
    expect(keeper.lastParity, isA<InParity>());
    expect(store.journal.mark!.revision, store.revision);
  });

  test(
    'a difference is kept in the log, naming figures, never an amount',
    () async {
      final (ledger, source, store) = await openWithJournal(keptStore(scratch));
      // The journal loses a posting behind the keeper's back.
      store.journal.transaction(
        () => store.journal.remove(const IntentId('lend')),
      );
      final before = ErrorLog.instance.count;
      ledger.entryCommands.add(
        Entry(
          id: 'more',
          date: day(10, 3),
          type: EntryType.transfer,
          amount: 7,
          account: 'bank',
          to: 'ann',
        ),
      );
      await settle(ledger, source);
      final parity = source.journal.lastParity! as OutOfParity;
      expect(
        parity.differences.map((d) => (d.figure, d.subject)),
        contains((Figure.balance, 'ann')),
      );
      expect(ErrorLog.instance.count, greaterThan(before));
      final logged = ErrorLog.instance.entries.first.$2;
      expect(logged, contains(ErrorSteps.journalParity));
      expect(logged, contains('balance'));
      expect(logged, isNot(contains('300')));
    },
  );

  test(
    'a backup carries no postings; the book restored is posted afresh',
    () async {
      final vaultDir = Directory('${scratch.path}/vault')..createSync();
      final codec = KeyringCodec(minimumPassword: 6);
      final (open, _) = await LedgerVault(
        vaultDir,
        codec: codec,
      ).create('pass word');
      addTearDown(open.close);
      final kept = keptStore(Directory('${scratch.path}/k')..createSync());
      open.store.write((w) {
        for (final row in kept.rows()) {
          w.put(row.shelf, row.id, row.body);
        }
      });
      await openWithJournal(open.store);
      expect(open.store.journal.postingCount, greaterThan(100));
      final file = File('${scratch.path}/b.etbk');
      await LedgerBackup.write(
        store: open.store,
        keys: open.keys,
        file: file,
        backupId: 'b',
        createdAt: DateTime.utc(2026, 10, 4),
      );
      final into = EncryptedDatabase.open(
        File('${scratch.path}/restored.db'),
        StorageKey.random(),
      );
      addTearDown(into.close);
      await LedgerBackup.restore(file: file, keys: open.keys, into: into);
      expect(into.count, open.store.count);
      expect(into.journal.postingCount, 0);
      expect(into.journal.mark, isNull);
      final (_, source, _) = await openWithJournal(into);
      expect(source.journal.lastReplay, isNotNull);
      expect(into.journal.postingCount, open.store.journal.postingCount);
      expect(source.journal.lastParity, isA<InParity>());
    },
  );

  group('a backup and a posting afresh share the store, one at a time', () {
    /// A vault holding the kept book, with no journal yet.
    Future<OpenVault> vaultBook() async {
      final vaultDir = Directory('${scratch.path}/vault')..createSync();
      final (open, _) = await LedgerVault(
        vaultDir,
        codec: KeyringCodec(minimumPassword: 6),
      ).create('pass word');
      addTearDown(open.close);
      final kept = keptStore(Directory('${scratch.path}/k')..createSync());
      open.store.write((w) {
        for (final row in kept.rows()) {
          w.put(row.shelf, row.id, row.body);
        }
      });
      kept.close();
      return open;
    }

    /// A backup as the app takes one: once nothing else uses the store.
    Future<File> backUp(OpenVault open) async {
      final file = File('${scratch.path}/b.etbk');
      while (open.store.busyApart) {
        await open.store.idle;
      }
      await LedgerBackup.write(
        store: open.store,
        keys: open.keys,
        file: file,
        backupId: 'b',
        createdAt: DateTime.utc(2026, 10, 4),
      );
      return file;
    }

    /// The backup restored holds every record of [open], and the journal
    /// is the records' own, in parity.
    Future<void> bothWhole(
      OpenVault open,
      SqlLedgerDataSource source,
      File backup,
    ) async {
      expect(open.store.journal.mark, (
        rules: journalRules,
        revision: open.store.revision,
      ));
      expect(source.journal.lastParity, isA<InParity>());
      final into = EncryptedDatabase.open(
        File('${scratch.path}/restored.db'),
        StorageKey.random(),
      );
      addTearDown(into.close);
      await LedgerBackup.restore(file: backup, keys: open.keys, into: into);
      expect(into.count, open.store.count);
    }

    test('a backup asked for while the book is posted afresh waits for '
        'it; both end whole', () async {
      final open = await vaultBook();
      final source = SqlLedgerDataSource(
        open.store,
        clock: keptClock,
        keepsJournal: true,
      );
      await source.load();
      // The posting afresh is under way on a worker.
      while (!open.store.busyApart) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      final backup = await backUp(open);
      await source.journal.settled;
      await bothWhole(open, source, backup);
    });

    test('a posting afresh asked for while a backup reads waits for it; '
        'both end whole', () async {
      final open = await vaultBook();
      final backingUp = backUp(open);
      // The backup's read holds the store as the book opens.
      expect(open.store.busyApart, isTrue);
      final source = SqlLedgerDataSource(
        open.store,
        clock: keptClock,
        keepsJournal: true,
      );
      await source.load();
      final backup = await backingUp;
      await source.journal.settled;
      expect(source.journal.lastReplay, isNotNull);
      await bothWhole(open, source, backup);
    });
  });

  test('預定 entries (D25) are posted at their day and the journal stays in '
      'parity', () async {
    final (ledger, source, store) = await openWithJournal(keptStore(scratch));
    ledger.entryCommands.addAll([
      // Next week and next month: 預定 today.
      Entry(
        id: 'soon',
        date: day(10, 11),
        type: EntryType.expense,
        amount: 320,
        account: 'cash',
        category: '飲食',
      ),
      Entry(
        id: 'payday',
        date: day(11, 5),
        type: EntryType.income,
        amount: 42000,
        account: 'bank',
        category: '薪水',
      ),
    ]);
    await settle(ledger, source);
    expect(isPlanned(ledger.entries.byId('soon')!, day(10, 4)), isTrue);
    expect(source.journal.lastParity, isA<InParity>());
    final posted = store.journal.postingsOfIntent(const IntentId('soon'));
    expect(posted, isNotEmpty);
    expect(posted.every((p) => p.date == Day.stored(20261011)), isTrue);
    // Not in today's balances: read as of today the journal leaves it
    // out, as the app does.
    final today = source.journal.reader.balances(until: Day.stored(20261004));
    final before = source.journal.reader.balances(until: Day.stored(20261012));
    expect(today, isNot(before));
  });

  test('a sale refused for want of shares (D12) posts nothing; the journal '
      'stays in parity', () async {
    // A new book: the kept one has an old oversold sale, beside which
    // today's write rules refuse every trade.
    final store = EncryptedDatabase.open(
      File('${scratch.path}/new.db'),
      StorageKey.random(),
    );
    addTearDown(store.close);
    final (ledger, source, _) = await openWithJournal(store);
    final bank = ledger.accounts.main;
    ledger.entryCommands.add(
      Entry(
        id: 'ten',
        date: day(10, 1),
        type: EntryType.buy,
        amount: 1000,
        account: bank,
        holding: '9999',
        shares: 10,
      ),
    );
    await settle(ledger, source);
    final postings = store.journal.postingCount;
    final revision = store.revision;
    expect(
      () => ledger.entryCommands.add(
        Entry(
          id: 'short',
          date: day(10, 3),
          type: EntryType.sell,
          amount: 1000,
          account: bank,
          holding: '9999',
          shares: 11,
        ),
      ),
      throwsA(isA<RecordRefused>()),
    );
    await settle(ledger, source);
    expect(store.journal.intent(const IntentId('short')), isNull);
    expect(store.journal.postingCount, postings);
    expect(store.revision, revision);
    expect(source.journal.lastParity, isA<InParity>());
  });

  group('changes the journal must follow whole (review 9)', () {
    Future<(Ledger, SqlLedgerDataSource, EncryptedDatabase)> fresh(
      String name,
    ) async {
      final store = EncryptedDatabase.open(
        File('${scratch.path}/$name.db'),
        StorageKey.random(),
      );
      addTearDown(store.close);
      final opened = await openWithJournal(store);
      opened.$1.accountCommands.addAccount(
        const Account('bank', '銀行', AccountKind.bank, 100000),
      );
      await settle(opened.$1, opened.$2);
      return opened;
    }

    test('break 2: an import with a sale listed before its purchase is '
        'posted in book order', () async {
      final (ledger, source, store) = await fresh('order');
      ledger.entryCommands.addAll([
        entryOf(
          'sell',
          day(9, 2),
          EntryType.sell,
          2000,
          'bank',
          holding: 'A',
          shares: 1,
          category: 'x',
        ),
        entryOf(
          'buy',
          day(9, 1),
          EntryType.buy,
          1000,
          'bank',
          holding: 'A',
          shares: 1,
          category: 'x',
        ),
      ]);
      await settle(ledger, source);
      expect(ledger.holdings.byCode('A')?.shares ?? 0, 0);
      expect(source.journal.reader.quantity(holdingAccount('A')), BigInt.zero);
      expect(source.journal.lastParity, isA<InParity>());
    });

    test('break 9: an account whose currency changed posts its records '
        'again', () async {
      final (ledger, source, store) = await fresh('currency');
      ledger.accountCommands.addAccount(
        const Account('cash', '現金', AccountKind.cash, 0),
      );
      ledger.entryCommands
        ..add(
          entryOf(
            'x',
            day(9, 1),
            EntryType.expense,
            500,
            'bank',
            category: '飲食',
          ),
        )
        ..add(
          entryOf('t', day(9, 2), EntryType.transfer, 300, 'bank', to: 'cash'),
        );
      await settle(ledger, source);
      ledger.accountCommands.updateAccount(
        const Account('bank', '銀行', AccountKind.bank, 100000, currency: 'USD'),
      );
      await settle(ledger, source);
      expect(source.journal.lastReplay, isNotNull);
      expect(
        {
          for (final p in store.journal.postingsOfIntent(const IntentId('x')))
            if (p.account == moneyAccount('bank')) p.currency.value,
        },
        {'USD'},
      );
      expect(source.journal.lastParity, isA<InParity>());
    });

    test('break 1: a category renamed keeps its postings, under its new '
        'name (D88)', () async {
      final (ledger, source, store) = await fresh('rename');
      ledger.categoryCommands.addCategory(Category('飲食', 'food', 0xFF111111));
      ledger.entryCommands.add(
        entryOf('x', day(9, 1), EntryType.expense, 500, 'bank', category: '飲食'),
      );
      await settle(ledger, source);
      final c = ledger.categories.all.firstWhere((c) => c.name == '飲食');
      ledger.categoryCommands.updateCategory(
        '飲食',
        Category('美食', c.icon, c.color),
      );
      await settle(ledger, source);
      expect(source.journal.lastParity, isA<InParity>());
      final account = categoryAccount(c.id, income: false);
      expect([
        for (final p in store.journal.postingsOfIntent(const IntentId('x')))
          p.account,
      ], contains(account));
      expect(
        store.journal.accounts().firstWhere((a) => a.id == account).name,
        '美食',
      );
      // Opened again: nothing to post afresh, still in parity.
      final again = SqlLedgerDataSource(
        store,
        clock: keptClock,
        keepsJournal: true,
      );
      await again.load();
      await again.journal.settled;
      expect(again.journal.lastReplay, isNull);
      expect(again.journal.lastParity, isA<InParity>());
    });
  });

  test('a 600-record merchant rename written apart reaches the journal, '
      'in parity, its mark the records\' revision', () async {
    final (ledger, source, store) = await openWithJournal(keptStore(scratch));
    ledger.entryCommands.addAll([
      for (var i = 0; i < 600; i++)
        Entry(
          id: 'shop$i',
          date: day(9, 1 + i % 28),
          type: EntryType.expense,
          amount: 10 + i,
          account: 'cash',
          category: '飲食',
          merchant: '舊店',
        ),
    ]);
    await settle(ledger, source);
    final revision = store.revision;
    var apart = false;
    final watch = Timer.periodic(
      const Duration(microseconds: 200),
      (_) => apart |= store.busyApart,
    );
    // The rename touches 600 entries: kept on a worker isolate, while the
    // journal waits for it.
    ledger.entryCommands.renameMerchant('舊店', '新店');
    await settle(ledger, source);
    watch.cancel();
    expect(apart, isTrue);
    expect(store.revision, revision + 1);
    expect(store.journal.mark, (rules: journalRules, revision: store.revision));
    expect(source.journal.lastParity, isA<InParity>());
    expect(store.journal.intent(const IntentId('shop599')), isNotNull);
  });

  test(
    'confirmations from the inbox, booked on return, reach the journal',
    () async {
      final (ledger, source, store) = await openWithJournal(keptStore(scratch));
      ledger.recurringCommands.saveRecurring(
        Recurring(
          id: 'rent',
          name: 'rent',
          amount: 500,
          day: 2,
          account: 'bank',
          category: '居家',
          start: day(10, 2),
        ),
      );
      await settle(ledger, source);
      final items = [
        (
          name: 'rent-2026-10-02.json',
          plain: Uint8List.fromList(
            utf8.encode(
              '{"kind":"confirm","recurring":"rent","day":"2026-10-02"}',
            ),
          ),
        ),
      ];
      final back = await LedgerSession(
        load: () async => ledger,
        inbox: () async =>
            (read: () async => items, remove: (String name) async {}),
      ).resume(ledger);
      expect(back.inbox?.booked, 1);
      await settle(ledger, source);
      final booked = ledger.entries.all.singleWhere(
        (e) => e.recurring == 'rent',
      );
      expect(store.journal.intent(IntentId(booked.id)), isNotNull);
      expect(store.journal.mark!.revision, store.revision);
      expect(source.journal.lastParity, isA<InParity>());
    },
  );

  test('a book closed while it is posted afresh closes once the posting is '
      'whole, its mark kept: reopened, nothing is posted again', () async {
    final store = keptStore(scratch);
    final source = SqlLedgerDataSource(
      store,
      clock: keptClock,
      keepsJournal: true,
    );
    await source.load();
    // The worker that read the book posts it now; closing waits for it.
    expect(store.busyApart, isTrue);
    store.close();
    expect(store.isOpen, isFalse);
    await store.idle;
    await source.journal.settled;
    final reopened = EncryptedDatabase.open(
      File('${scratch.path}/kept.db'),
      keptKey,
    );
    addTearDown(reopened.close);
    expect(reopened.journal.mark, (
      rules: journalRules,
      revision: reopened.revision,
    ));
    final (_, again, _) = await openWithJournal(reopened);
    expect(again.journal.lastReplay, isNull);
    expect(again.journal.lastParity, isA<InParity>());
  });

  test('a posting afresh after the book opened (an old version wrote '
      'records meanwhile) is let go when the book closes: no mark, posted '
      'afresh at the next opening', () async {
    final store = keptStore(scratch);
    final (ledger, source, _) = await openWithJournal(store);
    // As an older version would: a record written without the journal.
    store.write((w) => w.put('entry', 'old-app', '{}'));
    ledger.entryCommands.add(
      Entry(
        id: 'next',
        date: day(10, 2),
        type: EntryType.expense,
        amount: 5,
        account: 'cash',
        category: '飲食',
      ),
    );
    // Closed before the keeper's queued work runs.
    store.close();
    await source.journal.settled;
    final reopened = EncryptedDatabase.open(
      File('${scratch.path}/kept.db'),
      keptKey,
    );
    addTearDown(reopened.close);
    expect(
      reopened.journal.mark,
      isNot((rules: journalRules, revision: reopened.revision)),
    );
    final (_, again, _) = await openWithJournal(reopened);
    expect(again.journal.lastReplay, isNotNull);
    expect(again.journal.lastParity, isA<InParity>());
  });

  test('a row set aside has no postings; the rest is in parity', () async {
    final store = keptStore(scratch);
    store.write((w) => w.put('entry', 'broken', 'not a record'));
    final (ledger, source, _) = await openWithJournal(store);
    expect(ledger.entries.byId('broken'), isNull);
    expect(store.journal.intent(const IntentId('broken')), isNull);
    expect(store.journal.intent(const IntentId('pay')), isNotNull);
    expect(source.journal.lastParity, isA<InParity>());
  });

  test('work left when the book is closed is let go', () async {
    final store = keptStore(scratch);
    final source = SqlLedgerDataSource(
      store,
      clock: keptClock,
      keepsJournal: true,
    );
    await source.load();
    store.close();
    await source.journal.settled;
    expect(source.journal.lastParity, isNull);
  });
}
