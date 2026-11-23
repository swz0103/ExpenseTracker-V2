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
      [('acct:cash', -90), ('cat:spending:飲食', 90)],
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
      (_) => apart |= store.writingApart,
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

  test('a rebuild cut short by the book closing leaves no mark, and is '
      'posted afresh at the next opening', () async {
    final store = keptStore(scratch);
    final source = SqlLedgerDataSource(
      store,
      clock: keptClock,
      keepsJournal: true,
    );
    await source.load();
    // Closed before the keeper's queued rebuild runs.
    store.close();
    await source.journal.settled;
    final reopened = EncryptedDatabase.open(
      File('${scratch.path}/kept.db'),
      keptKey,
    );
    addTearDown(reopened.close);
    expect(reopened.journal.mark, isNull);
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
