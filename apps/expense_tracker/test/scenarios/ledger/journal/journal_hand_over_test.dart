// Changes made while the book opens (the journal is posted afresh
// on the worker beside the screens' copy of the book) reach the journal, and
// the journal the next opening trusts (its mark) is the records' own.
import 'dart:io';

import 'package:expense_tracker/src/core/ledger/journal/parity.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/ledger/persistence/sql_ledger_data_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kernel/kernel.dart';
import 'package:storage/storage.dart';

import '../../../baseline/baseline_ledger.dart';
import '../../../core/ledger/journal/posted_book.dart';
import 'awkward_book.dart' show keptClock;

String line(Posting p) =>
    '${p.account.value} ${p.amount} ${p.currency.value} ${p.date.ymd} q${p.quantity} ${p.sub}';

void main() {
  late Directory scratch;
  setUp(() => scratch = Directory.systemTemp.createTempSync('r14h-'));
  tearDown(() => scratch.deleteSync(recursive: true));

  Future<String?> compare(Ledger ledger, EncryptedDatabase store) async {
    final fresh = await post(ledger);
    final ids = {
      for (final e in ledger.entries.all) e.id,
      for (final a in ledger.accounts.all) 'opening:${a.id}',
    };
    for (final id in ids) {
      final a = [
        for (final p in fresh.store.postingsOfIntent(IntentId(id))) line(p),
      ];
      final b = [
        for (final p in store.journal.postingsOfIntent(IntentId(id))) line(p),
      ];
      if (a.join('|') != b.join('|'))
        return 'intent $id\n fresh: $a\n kept:  $b';
    }
    if (fresh.store.intentCount != store.journal.intentCount) {
      return 'intent count ${fresh.store.intentCount} vs ${store.journal.intentCount}';
    }
    final fs = fresh.store.sums(), ks = store.journal.sums();
    String show(AccountSums m) =>
        '${m.entries.map((e) => '${e.key.$1.value}/${e.key.$2.value}=${e.value.amount}/${e.value.quantity}').toList()..sort()}';
    if (show(fs) != show(ks))
      return 'sums differ\n fresh ${show(fs)}\n kept  ${show(ks)}';
    return null;
  }

  Future<File> seedBook({int entries = 300}) async {
    final file = File('${scratch.path}/book.db');
    final store = EncryptedDatabase.open(file, kKey);
    final source = SqlLedgerDataSource(store, clock: keptClock); // no journal
    final ledger = await source.load();
    ledger.accountCommands
      ..addAccount(const Account('bank', '銀行', AccountKind.bank, 100000))
      ..addAccount(
        const Account(
          'card',
          '卡',
          AccountKind.card,
          0,
          closingDay: 5,
          dueDay: 20,
        ),
      );
    ledger.entryCommands.addAll([
      for (var i = 0; i < entries; i++)
        entryOf(
          'e$i',
          day(2026, 1 + i % 8, 1 + i % 27),
          EntryType.expense,
          10 + i,
          i % 3 == 0 ? 'card' : 'bank',
          category: '飲食',
          installments: i % 9 == 0 && i % 3 == 0 ? 3 : 0,
        ),
    ]);
    await ledger.settled;
    store.close();
    return file;
  }

  final ops = <String, void Function(Ledger)>{
    'an entry added, replaced and removed': (l) {
      l.entryCommands
        ..add(
          entryOf(
            'x1',
            day(2026, 5, 3),
            EntryType.expense,
            777,
            'card',
            category: '飲食',
            installments: 6,
          ),
        )
        ..replace(
          entryOf(
            'e5',
            day(2026, 5, 4),
            EntryType.expense,
            55,
            'bank',
            category: '飲食',
          ),
        )
        ..remove('e7');
    },
    'an entry, then an opening balance (two writes)': (l) {
      l.entryCommands.add(
        entryOf(
          'x1',
          day(2026, 5, 3),
          EntryType.expense,
          777,
          'bank',
          category: '飲食',
        ),
      );
      l.accountCommands.updateAccount(
        const Account('bank', '銀行', AccountKind.bank, 123456),
      );
    },
    'an opening balance, then an entry (two writes)': (l) {
      l.accountCommands.updateAccount(
        const Account('bank', '銀行', AccountKind.bank, 123456),
      );
      l.entryCommands.add(
        entryOf(
          'x1',
          day(2026, 5, 3),
          EntryType.expense,
          777,
          'bank',
          category: '飲食',
        ),
      );
    },
    'entries added, replaced, removed, then an opening balance': (l) {
      l.entryCommands
        ..add(
          entryOf(
            'x1',
            day(2026, 5, 3),
            EntryType.expense,
            777,
            'card',
            category: '飲食',
            installments: 6,
          ),
        )
        ..replace(
          entryOf(
            'e5',
            day(2026, 5, 4),
            EntryType.expense,
            55,
            'bank',
            category: '飲食',
          ),
        )
        ..remove('e7');
      l.accountCommands.updateAccount(
        const Account('bank', '銀行', AccountKind.bank, 123456),
      );
    },
    'an opening balance changed': (l) => l.accountCommands.updateAccount(
      const Account('bank', '銀行', AccountKind.bank, 123456),
    ),
    'a card closing day changed': (l) => l.accountCommands.updateAccount(
      const Account(
        'card',
        '卡',
        AccountKind.card,
        0,
        closingDay: 11,
        dueDay: 25,
      ),
    ),
    'a card made a bank (kind changed)': (l) => l.accountCommands.updateAccount(
      const Account('card', '卡', AccountKind.bank, 0),
    ),
    'an account\'s currency changed': (l) => l.accountCommands.updateAccount(
      const Account('bank', '銀行', AccountKind.bank, 100000, currency: 'USD'),
    ),
    'a category renamed': (l) {
      final c = l.categories.all.firstWhere((c) => c.name == '飲食');
      l.categoryCommands.updateCategory(
        '飲食',
        Category('美食', c.icon, c.color, id: c.id),
      );
    },
    'an account removed': (l) => l.accountCommands.removeAccount('card'),
  };
  for (final MapEntry(key: what, value: op) in ops.entries) {
    test('while the book opens, the journal is posted apart: $what', () async {
      final file = await seedBook();
      var store = EncryptedDatabase.open(file, kKey);
      var source = SqlLedgerDataSource(
        store,
        clock: keptClock,
        keepsJournal: true,
      );
      final ledger = await source.load();
      // At once: the journal is still being posted apart.
      try {
        op(ledger);
      } catch (_) {
        markTestSkipped('refused: $what');
        store.close();
        return;
      }
      await ledger.settled;
      await source.journal.settled;
      expect(await compare(ledger, store), isNull, reason: 'same session');
      store.close();

      // The next opening trusts the mark: nothing posted afresh.
      store = EncryptedDatabase.open(file, kKey);
      source = SqlLedgerDataSource(store, clock: keptClock, keepsJournal: true);
      final again = await source.load();
      await source.journal.settled;
      expect(await compare(again, store), isNull, reason: 'after reopening');
      store.close();
    });
  }
}

final kKey = StorageKey.random();
