import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:core/app_core.dart';
import 'package:core/foundation_values.dart';
import 'package:expense_tracker/src/core/ledger/journal/book_mapping.dart';
import 'package:expense_tracker/src/core/ledger/journal/replay.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/ledger/persistence/journal_keeper.dart';
import 'package:expense_tracker/src/core/ledger/persistence/sql_ledger_data_source.dart';
import 'package:expense_tracker/src/core/ledger/persistence/write_batch.dart';
import 'package:expense_tracker/src/core/ledger/repositories/holding_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kernel/kernel.dart';
import 'package:ledger_postings/model/vocabulary.dart';
import 'package:storage/storage.dart';

/// The journal at 100,000 entries in the encrypted file, as the app keeps
/// it: posting the whole book afresh, one save's posting, every balance
/// (from the months' sums) and a month's report. Each against its limit
/// in journal_thresholds.json (about twice what was measured, see
/// thresholds.md). Slow, so it only runs when asked:
/// `BENCH=1 flutter test test/perf/journal_bench_test.dart`.
void main() {
  final asked = Platform.environment['BENCH'] != null;
  test(
    'the journal at 100,000 entries',
    () async {
      final limits = (jsonDecode(
        File('test/perf/journal_thresholds.json').readAsStringSync(),
      ) as Map<String, Object?>).map((k, v) => MapEntry(k, v! as num));
      final dir = Directory.systemTemp.createTempSync('journal-bench-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = EncryptedDatabase.open(
        File('${dir.path}/l.db'),
        StorageKey.random(),
      );
      addTearDown(store.close);
      final today = DateTime.utc(2026, 10, 4);
      final clock = FixedClock(UtcInstant(today.add(const Duration(hours: 4))));
      final source = SqlLedgerDataSource(store, clock: clock);
      await source.keep(
        WriteBatch(
          accounts: [
            const Account('bank', '銀行', AccountKind.bank, 500000),
            const Account('cash', '現金', AccountKind.cash, 5000),
            const Account(
              'card',
              '信用卡',
              AccountKind.card,
              0,
              closingDay: 20,
              dueDay: 5,
            ),
          ],
          categories: [
            for (var c = 0; c < 12; c++) Category('分類$c', 'food', 0xFF000000),
            Category('薪水', 'salary', 0xFF000000, income: true),
          ],
        ),
      );
      final r = Random(3);
      Entry entry(int i) {
        final date = today.subtract(Duration(days: r.nextInt(3650)));
        final kind = r.nextInt(100);
        return switch (kind) {
          < 70 => Entry(
            id: 'e$i',
            date: date,
            type: EntryType.expense,
            amount: 30 + r.nextInt(3000),
            account: ['bank', 'cash', 'card'][r.nextInt(3)],
            category: '分類${r.nextInt(12)}',
            installments: kind < 2 ? 3 : 0,
          ),
          < 80 => Entry(
            id: 'e$i',
            date: date,
            type: EntryType.income,
            amount: 1000 + r.nextInt(50000),
            account: 'bank',
            category: '薪水',
          ),
          < 95 => Entry(
            id: 'e$i',
            date: date,
            type: EntryType.transfer,
            amount: 100 + r.nextInt(5000),
            account: 'bank',
            to: r.nextBool() ? 'cash' : 'card',
          ),
          _ => Entry(
            id: 'e$i',
            date: date,
            type: EntryType.buy,
            amount: 10000 + r.nextInt(90000),
            account: 'bank',
            holding: ['2330', '0050', '2317'][r.nextInt(3)],
            shares: 1 + r.nextInt(1000),
            fee: 20,
          ),
        };
      }

      for (var k = 0; k < 10; k++) {
        await source.keep(
          WriteBatch(
            entries: [
              for (var i = k * 10000; i < (k + 1) * 10000; i++) entry(i),
            ],
          ),
        );
      }
      final ledger = await source.load();

      // Posting the whole book afresh, into the file.
      final mapping = BookMapping(
        accounts: ledger.accounts.all,
        categories: ledger.categories.all,
        start: (ledger.holdings as HoldingRepository).start,
      );
      final seqs = {
        for (final row in store.rows(shelf: Collection.entry.name))
          row.id: row.seq,
      };
      final tree = AccountTree();
      final journal = Journal(
        registry: registryFor(() => mapping),
        accounts: tree,
        store: store.journal,
        source: (_) => null,
      );
      final rebuild = Stopwatch()..start();
      final report = await replayBook(
        mapping: mapping,
        journal: journal,
        store: store.journal,
        entries: [
          for (final e in ledger.entries.all) (entry: e, seq: seqs[e.id]!),
        ],
      );
      final rebuildMs = rebuild.elapsedMilliseconds;
      expect(report.unposted, isEmpty);

      // One save's posting, as the keeper posts it: the intent and the
      // mark in one transaction.
      final saves = <int>[];
      for (var k = 0; k < 15; k++) {
        final e = Entry(
          id: 'new$k',
          date: today,
          type: EntryType.expense,
          amount: 120,
          account: 'bank',
          category: '分類1',
        );
        final watch = Stopwatch()..start();
        final written = journal.putAll(
          [mapping.map(e, 1 << 40).intent],
          also: () =>
              store.journal.keepMark((rules: journalRules, revision: k)),
        );
        saves.add(watch.elapsedMicroseconds);
        expect(written, isA<Written>());
      }
      final reader = BookReader(
        store.journal,
        tree,
        Contributions(),
        homeCurrency,
      );
      int median(void Function() run) {
        final times = <int>[];
        for (var k = 0; k < 15; k++) {
          final watch = Stopwatch()..start();
          run();
          times.add(watch.elapsedMicroseconds);
        }
        times.sort();
        return times[7];
      }

      saves.sort();
      final saveUs = saves[7];
      final today_ = Day.of(BusinessDate.of(today));
      final balancesUs = median(() => reader.balances(until: today_));
      final monthUs = median(() => reader.month(today_.previous.firstOfMonth));
      final found = {
        'rebuild_100k_ms': rebuildMs,
        'save_posting_us': saveUs,
        'every_balance_us': balancesUs,
        'month_report_us': monthUs,
      };
      // ignore: avoid_print
      print(
        'journal at 100k: ${store.journal.intentCount} intents, '
        '${store.journal.postingCount} postings; $found',
      );
      for (final MapEntry(:key, :value) in found.entries) {
        expect(value, lessThanOrEqualTo(limits[key]!), reason: key);
      }
    },
    skip: !asked,
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
