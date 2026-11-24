// Random books of trades alone (buys, sales, dividends, splits,
// reductions), posted and compared: lots and gains as the holdings keep
// them.
import 'dart:math';

import 'package:expense_tracker/src/core/ledger/journal/parity.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../baseline/baseline_ledger.dart';
import '../../../core/ledger/journal/posted_book.dart';

Ledger fresh() => ledgerOf(
  today: day(2026, 10, 31),
  accounts: const [Account('bank', '銀行', AccountKind.bank, 10000000)],
  categories: const [],
);

Ledger replay(List<Entry> es) {
  final l = fresh();
  for (final e in es) {
    try {
      l.entryCommands.add(e);
    } catch (_) {}
  }
  return l;
}

Future<List<Difference>> diffs(Ledger l) async {
  final b = await post(l);
  final p = await checkParity(
    today: figuresOf(l),
    reader: b.reader,
    unposted: b.report.unposted,
    shapes: b.report.shapes,
    everyDay: true,
  );
  return p is OutOfParity ? p.differences : [];
}

List<Entry> gen(int seed, int n) {
  final r = Random(seed);
  final l = fresh();
  final log = <Entry>[];
  int pick(int lo, int hi) => lo + r.nextInt(hi - lo + 1);
  for (var i = 0; i < n; i++) {
    final d = day(2026, 8, 1).add(Duration(days: i));
    final k = r.nextInt(100);
    final h = l.holdings.byCode('A')?.shares ?? 0;
    Entry? e;
    if (k < 35) {
      final sh = pick(1, 5);
      e = entryOf(
        'e$i',
        d,
        EntryType.buy,
        pick(10, 900),
        'bank',
        holding: 'A',
        shares: sh,
        fee: pick(0, 9),
        category: 'x',
      );
    } else if (k < 55 && h > 0) {
      e = entryOf(
        'e$i',
        d,
        EntryType.sell,
        pick(10, 900),
        'bank',
        holding: 'A',
        shares: pick(1, h),
        fee: pick(0, 9),
        tax: pick(0, 9),
        average: r.nextBool(),
        category: 'x',
      );
    } else if (k < 75 && h > 0) {
      e = entryOf(
        'e$i',
        d,
        EntryType.dividend,
        pick(0, 900),
        'bank',
        holding: 'A',
        shares: -pick(1, h),
        category: 'x',
      );
    } else if (k < 90 && h > 0) {
      e = entryOf(
        'e$i',
        d,
        EntryType.dividend,
        0,
        'bank',
        holding: 'A',
        shares: pick(1, 5),
        split: r.nextBool(),
        category: 'x',
      );
    } else {
      e = entryOf(
        'e$i',
        d,
        EntryType.dividend,
        pick(1, 900),
        'bank',
        holding: 'A',
        category: 'x',
      );
    }
    try {
      l.entryCommands.add(e);
      log.add(e);
    } catch (_) {}
  }
  return log;
}

String show(Entry e) =>
    '${e.date.toIso8601String().substring(5, 10)} ${e.type.name} amt${e.amount} sh${e.shares} fee${e.fee} tax${e.tax}${e.average ? ' avg' : ''}${e.split ? ' split' : ''}';

void main() {
  test('stock only', () async {
    final allMin = <String>{};
    for (var s = 1; s <= 2500; s++) {
      final log = gen(s, 12);
      final d = await diffs(replay(log));
      if (d.isEmpty) continue;
      var cur = [...log];
      var changed = true;
      while (changed) {
        changed = false;
        for (var i = 0; i < cur.length; i++) {
          final t = [...cur]..removeAt(i);
          if ((await diffs(replay(t))).isNotEmpty) {
            cur = t;
            changed = true;
            break;
          }
        }
      }
      // Cut down to a minimal counterexample, said if any is found.
      final why = (await diffs(replay(cur))).map((d) => d.figure.name);
      allMin.add('${cur.map(show).join(' | ')} => ${why.join(',')}');
    }
    final sorted = allMin.toList()
      ..sort((a, b) => a.length.compareTo(b.length));
    expect(sorted, isEmpty, reason: sorted.take(12).join('\n'));
  }, timeout: const Timeout(Duration(minutes: 20)));
}
