import 'dart:io';
import 'dart:math';

import 'package:core/app_core.dart';
import 'package:core/foundation_values.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/ledger/table_journal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storage/storage.dart';

/// How the book behaves as it grows, on the real encrypted store. Slow, so
/// it only runs when asked for: `BENCH=1 flutter test test/core/scale_bench_test.dart`.
/// The times are printed, one line per size; nothing is asserted, so it is a
/// measure to read, not a gate.
void main() {
  final asked = Platform.environment['BENCH'] != null;
  final today = DateTime.utc(2026, 10, 4);
  const names = ['居家生活', '飲食日常', '交通通勤', '購物休閒', '訂閱服務', '其他支出'];
  const shops = ['便當店', '捷運', '房東', '電影院', '咖啡', '超市', '加油站'];

  List<Entry> make(int count) {
    final r = Random(1);
    return [
      for (var i = 0; i < count; i++)
        Entry(
          id: 'e$i',
          date: today.subtract(Duration(days: r.nextInt(365 * 5))),
          type: r.nextInt(8) == 0 ? EntryType.income : EntryType.expense,
          amount: 30 + r.nextInt(2000),
          account: 'a${r.nextInt(3)}',
          category: names[r.nextInt(names.length)],
          merchant: shops[r.nextInt(shops.length)],
          tags: [if (r.nextInt(4) == 0) '家用'],
          note: r.nextInt(5) == 0 ? '備註 $i' : '',
        ),
    ];
  }

  Future<int> time(Future<void> Function() body) async {
    final watch = Stopwatch()..start();
    await body();
    return watch.elapsedMicroseconds;
  }

  String ms(int us) => (us / 1000).toStringAsFixed(1).padLeft(8);

  for (final count in [10000, 50000, 100000]) {
    test(
      'a book of $count entries',
      () async {
        final directory = Directory.systemTemp.createTempSync('bench-');
        addTearDown(() => directory.deleteSync(recursive: true));
        final file = File('${directory.path}/ledger.db');
        final key = StorageKey.random();
        final clock = FixedClock(UtcInstant(DateTime.utc(2026, 10, 4, 4)));

        var store = RowStore.open(file, key);
        var ledger = await TableJournal(store, clock: clock).load();
        final entries = make(count);
        ledger.addAll(
          entries,
          accounts: [
            for (var i = 0; i < 3; i++)
              Account('a$i', '帳戶$i', AccountKind.bank, 100000),
          ],
        );
        final writeAll = await time(() => ledger.settled);
        store.close();

        late Ledger loaded;
        final open = await time(() async {
          store = RowStore.open(file, key);
          loaded = await TableJournal(store, clock: clock).load();
        });
        ledger = loaded;

        final firstMonth = await time(() async => ledger.entriesIn(2026, 10));
        final spendYear = await time(
          () async => ledger.spendingBetween(
            DateTime.utc(2026, 1, 1),
            DateTime.utc(2026, 12, 31),
          ),
        );
        final balance = await time(() async => ledger.balance('a0'));
        final netWorth = await time(() async => ledger.netWorthAt(today));
        final search1 = await time(() async => ledger.search('便當'));
        final search2 = await time(() async => ledger.search('便當店'));
        final stats = await time(() async => ledger.merchantStats);

        // What recording one entry costs the screen: the call itself, then the
        // first queries that follow (the caches are thrown away).
        final add = await time(() async {
          ledger.add(
            Entry(
              id: 'one',
              date: today,
              type: EntryType.expense,
              amount: 120,
              account: 'a0',
              category: '飲食日常',
              merchant: '便當店',
            ),
          );
        });
        final after = await time(() async {
          ledger.entriesIn(2026, 10);
          ledger.expense(2026, 10);
          ledger.balance('a0');
        });

        final edit = await time(() async {
          ledger.updateCategory(
            '飲食日常',
            ledger.category('飲食日常').copyWith(name: '吃飯'),
          );
        });
        final renamed = ledger.entries.where((e) => e.category == '吃飯').length;
        store.close();

        // ignore: avoid_print
        print(
          'N=${count.toString().padLeft(6)}  '
          'writeAll ${ms(writeAll)}  open ${ms(open)}  '
          'month ${ms(firstMonth)}  year ${ms(spendYear)}  '
          'balance ${ms(balance)}  netWorth ${ms(netWorth)}  '
          'search ${ms(search1)}/${ms(search2)}  merchantStats ${ms(stats)}  '
          'add ${ms(add)}  afterAdd ${ms(after)}  '
          'rename ${ms(edit)}  (ms) renamed=$renamed',
        );
      },
      skip: asked ? false : 'BENCH=1 to run',
      timeout: const Timeout(Duration(minutes: 10)),
    );
  }
}
