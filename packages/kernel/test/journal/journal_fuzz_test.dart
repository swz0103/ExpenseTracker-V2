// Review 9's fuzz of the journal, kept: random writes, edits and
// deletes of streamed intents against a store posted afresh after each
// (the same postings, sums and refusals), the order of a batch, and
// sums too large to balance.
import 'dart:math';

import 'package:kernel/kernel.dart';
import 'package:test/test.dart';

import '../support/book.dart';

String snap(MemoryPostingStore s, Iterable<IntentId> ids) {
  final b = StringBuffer();
  for (final id in ids) {
    final r = s.intent(id);
    b.writeln(
      '$id ${r?.date.ymd} ${r?.seq} ${r?.streams} ${[for (final p in s.postingsOfIntent(id)) p.toString()]}',
    );
  }
  b.writeln(
    'sums ${s.sums().entries.map((e) => '${e.key.$1.value}/${e.key.$2.value}=${e.value}').toList()..sort()}',
  );
  b.writeln('count ${s.intentCount} ${s.postingCount} mark ${s.mark}');
  return b.toString();
}

void main() {
  test('journal fuzz: balanced, refusal changes nothing, equals fresh, '
      'order independent', () {
    final problems = <String>[];
    final trace = <String>[];
    var refusals = 0, writes = 0;
    for (var seed = 0; seed < 300; seed++) {
      final r = Random(seed);
      final env = book();
      final all = <IntentId>{};
      int pick(int lo, int hi) => lo + r.nextInt(hi - lo + 1);
      LedgerIntent make(String id, int seq) {
        final d = day(6, pick(1, 6));
        return switch (r.nextInt(3)) {
          0 => Move(
            id,
            d,
            seq,
            from: of(r, [bank, cash]),
            to: of(r, [cash, food, bank]),
            amount: pick(1, 50),
          ),
          _ => Beans(
            id,
            d,
            seq,
            r.nextBool() ? pick(1, 5) : -pick(1, 5),
            pick(1, 90),
          ),
        };
      }

      var n = 0;
      for (var step = 0; step < 40; step++) {
        final before = snap(env.store, all);
        JournalResult res;
        String what;
        final op = r.nextInt(10);
        final keptIds = env.kept.keys.toList();
        if (op < 5 || keptIds.isEmpty) {
          final i = make('i${n++}', n);
          what = 'put new ${i.id} ${i.type.value}';
          env.kept[i.id] = i;
          res = env.journal.put(i);
          if (res is! Written) env.kept.remove(i.id);
        } else if (op < 7) {
          final id = keptIds[r.nextInt(keptIds.length)];
          final seq = env.kept[id]!.seq;
          final i = make(id.value, seq);
          what = 'edit $id';
          final was = env.kept[id]!;
          env.kept[id] = i;
          res = env.journal.put(i);
          if (res is! Written) env.kept[id] = was;
        } else if (op < 9) {
          final id = keptIds[r.nextInt(keptIds.length)];
          what = 'delete $id';
          final was = env.kept[id];
          res = env.journal.delete(id, also: () => env.kept.remove(id));
          if (res is! Written && was != null) env.kept[id] = was;
          // (also ran inside the transaction; a refusal rolls the store, not kept)
        } else {
          final a = make('i${n++}', n), b = make('i${n++}', n);
          what = 'putAll ${a.id},${b.id}';
          env.kept[a.id] = a;
          env.kept[b.id] = b;
          res = env.journal.putAll([a, b]);
          if (res is! Written) {
            env.kept.remove(a.id);
            env.kept.remove(b.id);
          }
        }
        trace.add('seed $seed step $step $what -> ${res.runtimeType}');
        all.addAll(env.kept.keys);
        if (res is! Written) {
          refusals++;
          final after = snap(env.store, all);
          if (before != after) {
            problems.add(
              'seed $seed step $step $what: refusal ($res) changed the store\n$before\n--\n$after',
            );
          }
          continue;
        }
        writes++;
        // 1. balanced per currency
        final byCur = <CurrencyCode, int>{};
        for (final id in env.kept.keys) {
          final per = <CurrencyCode, int>{};
          for (final p in env.store.postingsOfIntent(id)) {
            per[p.currency] = (per[p.currency] ?? 0) + p.amount;
          }
          for (final e in per.entries) {
            if (e.value != 0) {
              problems.add(
                'seed $seed $what: $id unbalanced ${e.key.value} ${e.value}',
              );
            }
            byCur[e.key] = (byCur[e.key] ?? 0) + e.value;
          }
        }
        // 2. equals a fresh posting of everything in book order
        final fresh = book();
        final order = env.kept.values.toList()
          ..sort((a, b) {
            final c = comparePositions(a.position, b.position);
            return c != 0 ? c : a.id.value.compareTo(b.id.value);
          });
        for (final i in order) {
          fresh.kept[i.id] = i;
        }
        var ok = true;
        for (final i in order) {
          final x = fresh.journal.put(i);
          if (x is! Written) {
            ok = false;
            problems.add(
              'seed $seed $what: fresh refused ${(x as RuleRejected).intent} ${x.code}; kept=${order.map((i) => i is Beans ? "${i.id}@${i.date.ymd}/${i.seq} beans ${i.count}" : "${i.id} move").join(', ')}\ntrace:\n${trace.where((t) => t.startsWith('seed $seed ')).join('\n')}',
            );
            break;
          }
        }
        if (ok) {
          final a = snap(
            env.store,
            env.kept.keys.toList()..sort((a, b) => a.value.compareTo(b.value)),
          );
          final b = snap(
            fresh.store,
            env.kept.keys.toList()..sort((a, b) => a.value.compareTo(b.value)),
          );
          if (a.replaceAll(RegExp(r'mark.*'), '') !=
              b.replaceAll(RegExp(r'mark.*'), '')) {
            problems.add(
              'seed $seed step $step $what: journal != fresh\n$a\n--\n$b',
            );
          }
        }
      }
    }
    expect(writes, greaterThan(1000));
    expect(refusals, greaterThan(0));
    expect(problems, isEmpty, reason: problems.take(4).join('\n====\n'));
  });

  test('putAll order: a valid book is kept whatever order it is given in', () {
    final env = book();
    final out = Beans('out', day(6, 2), 2, -2, 10);
    final into = Beans('in', day(6, 1), 1, 3, 30);
    final r = env.journal.putAll([out, into]);
    final env2 = book();
    final r2 = env2.journal.putAll([into, out]);
    // Posted in book order whatever the order given (r9 break 2).
    expect(r, isA<Written>());
    expect(r2, isA<Written>());
    expect(env.store.sums(), env2.store.sums());
  });

  test('lines whose sum wraps past 64 bits are refused, never taken as '
      'balanced', () {
    final reg = registry()
      ..register<_Raw>(
        IntentSpec(
          type: const IntentType('raw'),
          owner: owner,
          rule: _RawRule(),
        ),
      );
    final env = book(with_: reg);
    const big = 1 << 62;
    final r = env.journal.put(
      _Raw('raw', day(6, 1), 1, [
        Line(bank, big, twd),
        Line(cash, big, twd),
        Line(food, big, twd),
        Line(trading, big, twd),
      ]),
    );
    expect(r, isA<Unbalanced>());
    expect(env.store.postingCount, 0);
  });
}

T of<T>(Random r, List<T> xs) => xs[r.nextInt(xs.length)];

final class _Raw extends LedgerIntent {
  _Raw(String id, Day date, int seq, this.lines)
    : super(id: IntentId(id), date: date, seq: seq);
  final List<Line> lines;
  @override
  IntentType get type => const IntentType('raw');
}

final class _RawRule implements PostingRule<_Raw> {
  @override
  Iterable<String> streams(_Raw i) => const [];
  @override
  Posted post(_Raw i, RuleContext c) => Lines(i.lines);
}
