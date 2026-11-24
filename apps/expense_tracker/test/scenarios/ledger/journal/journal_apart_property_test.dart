// Three ways to the same journal, on random books: posted afresh on a
// worker (the first opening), replayed here, and kept change by change.
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
import 'random_book.dart' as rt;
import 'random_book.dart' as r5;

String line(Posting p) =>
    '${p.account.value} ${p.amount} ${p.currency.value} ${p.date.ymd} q${p.quantity} ${p.sub}';

void main() {
  late Directory scratch;
  setUp(() => scratch = Directory.systemTemp.createTempSync('apart-'));
  tearDown(() => scratch.deleteSync(recursive: true));

  test('apart rebuild == in-process replay == incremental, random books', () async {
    final bad = <String>[];
    for (var seed = 1; seed <= 25; seed++) {
      final (_, log) = rt.gen(seed, 120, day(2026, 10, 4));
      final store = EncryptedDatabase.open(
        File('${scratch.path}/s$seed.db'),
        StorageKey.random(),
      );
      var source = SqlLedgerDataSource(
        store,
        clock: keptClock,
        keepsJournal: true,
      );
      var ledger = await source.load();
      await source.journal.settled;
      for (final a in rt.accts) {
        ledger.accountCommands.addAccount(a);
      }
      for (final c in r5.categories) {
        try {
          ledger.categoryCommands.addCategory(c);
        } catch (_) {}
      }
      try {
        ledger.categoryCommands.addCategory(Category('投資', 'x', 0xFF000000));
      } catch (_) {}
      try {
        ledger.entryCommands.addAll(
          [...log]..sort((a, b) => a.date.compareTo(b.date)),
        );
      } catch (e) {
        bad.add('seed $seed addAll refused $e');
        store.close();
        continue;
      }
      await ledger.settled;
      await source.journal.settled;
      final incremental = {
        for (final e in ledger.entries.all)
          e.id: [
            for (final p in store.journal.postingsOfIntent(IntentId(e.id)))
              line(p),
          ].join('|'),
      };
      final incParity = source.journal.lastParity;
      // reopen: force a rebuild apart
      store.write((w) => w.put('meta-free', 'x', '{}'));
      source = SqlLedgerDataSource(store, clock: keptClock, keepsJournal: true);
      ledger = await source.load();
      await source.journal.settled;
      final replayed = await post(ledger);
      var diffs = 0;
      String? first;
      for (final e in ledger.entries.all) {
        final a = [
          for (final p in replayed.store.postingsOfIntent(IntentId(e.id)))
            line(p),
        ].join('|');
        final b = [
          for (final p in store.journal.postingsOfIntent(IntentId(e.id)))
            line(p),
        ].join('|');
        if (a != b) {
          diffs++;
          first ??= '${e.id} ${e.type.name}\n  replay $a\n  apart  $b';
        }
        if (incremental[e.id] != b) {
          diffs++;
          first ??=
              '${e.id} incremental/apart differ\n  inc   ${incremental[e.id]}\n  apart $b';
        }
      }
      if (diffs > 0 || source.journal.lastReplay == null) {
        bad.add(
          'seed $seed diffs $diffs replay=${source.journal.lastReplay != null}: $first',
        );
      }
      if (source.journal.lastParity is OutOfParity) {
        bad.add(
          'seed $seed apart parity: ${(source.journal.lastParity as OutOfParity).differences.take(2)}',
        );
      }
      if (incParity is OutOfParity) {
        bad.add(
          'seed $seed incremental parity: ${incParity.differences.take(2)}',
        );
      }
      store.close();
    }
    expect(bad, isEmpty, reason: bad.take(6).join('\n'));
  }, timeout: const Timeout(Duration(minutes: 20)));
}
