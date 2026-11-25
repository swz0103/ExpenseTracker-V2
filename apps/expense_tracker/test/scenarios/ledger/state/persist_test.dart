// Round 6: persistence is state-neutral (real encrypted SQL data source),
// the write queue keeps the last change, trash expiry, unknown fields,
// refused writes, and two commands in quick succession.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:core/app_core.dart';
import 'package:core/foundation_values.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/ledger/persistence/ledger_data_source.dart';
import 'package:expense_tracker/src/core/ledger/persistence/sql_ledger_data_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storage/storage.dart';

import '../../../support/state_fingerprint.dart';

final key = StorageKey.random();

class Disk {
  Disk({this.writeApart = 500, this.page = 5000}) {
    dir = Directory.systemTemp.createTempSync('r6-');
    file = File('${dir.path}/ledger.db');
  }
  late Directory dir;
  late File file;
  final int writeApart, page;
  final clock = FixedClock(UtcInstant(DateTime.utc(2026, 10, 31, 4)));
  EncryptedDatabase? store;
  late SqlLedgerDataSource source;

  Future<Ledger> open() {
    store?.close();
    store = EncryptedDatabase.open(file, key);
    source = SqlLedgerDataSource(
      store!,
      clock: clock,
      writeApartFrom: writeApart,
      readPage: page,
    );
    return source.load();
  }

  void close() {
    store?.close();
    store = null;
    dir.deleteSync(recursive: true);
  }
}

/// A seeded book written through the commands into the store.
Future<Ledger> seeded(
  Disk d,
  int seed, {
  int count = 100,
  bool recurring = true,
  Book? from,
}) async {
  final b = from ?? generate(seed, count);
  final live = await d.open();
  live.entryCommands.addAll(
    const [],
    accounts: accounts,
    categories: categories,
  );
  for (final e in b.log) {
    live.entryCommands.add(e);
  }
  if (recurring) addRecurring(live);
  live.budgetCommands.setBudget('飲食', 4000);
  live.budgetCommands.setBudget('#旅遊', 900);
  await live.settled;
  return live;
}

Entry mutate(Entry e, int variant) {
  final j = Map<String, Object?>.from(jsonOf(e));
  switch (variant % 3) {
    case 0:
      j['amount'] = (j['amount']! as int) + 7;
      if (j['home'] != null) j['home'] = (j['home']! as int) + 7;
    case 1:
      j['tags'] = (j['tags'] as List?)?.isNotEmpty == true
          ? <Object?>[]
          : <Object?>['旅遊'];
    default:
      j['note'] = 'n$variant';
  }
  return fromJson(j);
}

bool attempt(void Function() op) {
  try {
    op();
    return true;
  } catch (_) {
    return false;
  }
}

/// A random user action on [l].
void act(Ledger l, Random r) {
  final es = l.entries.all;
  if (es.isEmpty) return;
  final e = es[r.nextInt(es.length)];
  switch (r.nextInt(9)) {
    case 0 || 1:
      attempt(() => l.entryCommands.replace(mutate(e, r.nextInt(99))));
    case 2:
      final x = l.entryCommands.remove(e.id);
      if (x != null && r.nextBool()) l.entryCommands.restore(x);
    case 3:
      if (l.trash.all.isNotEmpty) {
        l.entryCommands.restoreTrashed(
          l.trash.all[r.nextInt(l.trash.all.length)],
        );
      }
    case 4:
      l.entryCommands.removeAll([e.id, es[r.nextInt(es.length)].id]);
    case 5:
      l.entryCommands.renameTag('旅遊', r.nextBool() ? '日常' : '旅遊');
    case 6:
      l.entryCommands.renameMerchant('全家', r.nextBool() ? '7-11' : '全家');
    case 7:
      l.recurringCommands.bookDue();
    default:
      attempt(() => l.entryCommands.add(e.withId(l.newId())));
  }
}

void main() {
  final disks = <Disk>[];
  Disk disk({int writeApart = 500, int page = 5000}) {
    final d = Disk(writeApart: writeApart, page: page);
    disks.add(d);
    return d;
  }

  tearDown(() {
    for (final d in disks) {
      try {
        d.close();
      } catch (_) {}
    }
    disks.clear();
  });

  test('P1 save -> reopen: records, order and every statistic identical', () async {
    final bad = <String>[];
    for (final s in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]) {
      final d = disk(
        writeApart: s.isEven ? 7 : 500,
        page: s % 3 == 0 ? 11 : 5000,
      );
      final live = await seeded(d, s);
      final r = Random(s);
      for (var i = 0; i < 40; i++) {
        act(live, r);
      }
      await live.settled;
      expect(
        live.problem.value,
        anyOf(isNull, isA<RecordRefused>(), isA<RecordRefused>()),
        reason: 'seed $s',
      );
      final before = state(live, order: true);
      final back = await d.open();
      final msg = diff(
        before,
        state(back, order: true),
        an: 'memory',
        bn: 'disk',
      );
      if (msg != null) bad.add('seed $s: $msg');
      // and a second reopen
      final again = await d.open();
      final msg2 = diff(
        before,
        state(again, order: true),
        an: 'memory',
        bn: 'disk2',
      );
      if (msg2 != null) bad.add('seed $s (2nd reopen): $msg2');
    }
    // ignore: avoid_print
    print(
      '[P1 save->reopen] seeds 10 (writeApart 7/500, page 11/5000), failing ${bad.length}: ${bad.take(3)}',
    );
    expect(bad, isEmpty);
  });

  test('P2 rapid edits (no await between) then settle/close/reopen keep the last change', () async {
    final bad = <String>[];
    for (final s in [1, 2, 3, 4, 5, 6, 7, 8]) {
      final d = disk(writeApart: s.isEven ? 3 : 500);
      final live = await seeded(d, s, count: 60);
      final r = Random(s * 31);
      final target = live.entries.all[r.nextInt(live.entries.length)];
      var cur = target;
      // 150 rapid edits of one entry, a batch import in the middle (written
      // apart when small writeApart), more edits of the same entry after.
      for (var i = 0; i < 150; i++) {
        final next = mutate(cur, i);
        if (attempt(() => live.entryCommands.replace(next))) cur = next;
        if (i == 70) {
          final extra = [
            for (var k = 0; k < 20; k++)
              entryOf(
                live.newId(),
                DateTime.utc(2026, 9, 1 + k),
                EntryType.expense,
                10 + k,
                'bank',
                category: '飲食',
              ),
          ];
          live.entryCommands.addAll(extra);
        }
      }
      await live.settled;
      final memory = state(live, order: true);
      final back = await d.open();
      final msg = diff(
        memory,
        state(back, order: true),
        an: 'memory',
        bn: 'disk',
      );
      final kept = back.entries.byId(target.id);
      if (kept == null || enc(jsonOf(kept)) != enc(jsonOf(cur))) {
        bad.add(
          'seed $s: last edit lost: disk ${kept == null ? null : enc(jsonOf(kept))} vs last ${enc(jsonOf(cur))}',
        );
      }
      if (msg != null) bad.add('seed $s: $msg');
    }
    // ignore: avoid_print
    print(
      '[P2 rapid edits then reopen] seeds 8, failing ${bad.length}: ${bad.take(3)}',
    );
    expect(bad, isEmpty);
  });

  test('P3 a field this version does not know: state identical with and without it, field survives', () async {
    final bad = <String>[];
    for (final s in [1, 2, 3, 4, 5, 6]) {
      final plain = disk();
      final unknown = disk();
      final book = generate(s, 60);
      final a = await seeded(plain, s, recurring: false, from: book);
      final b = await seeded(unknown, s, recurring: false, from: book);
      // make both books hold a trashed entry too
      final victim = a.entries.all.firstWhere(
        (e) => e.type == EntryType.expense && e.refundOf == null,
      );
      a.entryCommands.remove(victim.id);
      b.entryCommands.remove(victim.id);
      await a.settled;
      await b.settled;
      // inject an unknown field into every row of b (and its trash entry)
      unknown.store!.write((w) {
        for (final row in unknown.store!.rows()) {
          final shelf = row.shelf;
          if (!{
            'entry',
            'account',
            'category',
            'budget',
            'recurring',
            'trash',
          }.contains(shelf)) {
            continue;
          }
          final body = jsonDecode(row.body) as Map<String, Object?>;
          body['zz'] = 'future';
          if (shelf == 'trash' && body['entry'] is Map) {
            (body['entry'] as Map<String, Object?>)['zz'] = 'future-inner';
          }
          w.put(shelf, row.id, jsonEncode(body));
        }
      });
      var la = await plain.open();
      var lb = await unknown.open();
      final r1 = Random(s), r2 = Random(s);
      for (var i = 0; i < 25; i++) {
        // same decisions on both (ids of the entries are the same)
        final e1 = la.entries.all[r1.nextInt(la.entries.length)];
        final e2 = lb.entries.all[r2.nextInt(lb.entries.length)];
        final k = r1.nextInt(5);
        r2.nextInt(5);
        for (final (l, e) in [(la, e1), (lb, e2)]) {
          switch (k) {
            case 0:
              attempt(() => l.entryCommands.replace(mutate(e, i)));
            case 1:
              l.entryCommands.remove(e.id);
            case 2:
              if (l.trash.all.isNotEmpty) {
                l.entryCommands.restoreTrashed(l.trash.all.first);
              }
            case 3:
              l.categoryCommands.updateCategory(
                '娛樂',
                l.category('娛樂').copyWith(archived: i.isEven),
              );
            default:
              l.entryCommands.renameMerchant('全家', i.isEven ? '7-11' : '全家');
          }
        }
      }
      await la.settled;
      await lb.settled;
      Map<String, String> cmp(Ledger l) => {
        for (final e in stable(state(l, order: true)).entries)
          if (e.key != 'rec/accounts' &&
              e.key != 'rec/categories' &&
              e.key != 'rec/order of accounts' &&
              e.key != 'rec/order of categories')
            e.key: e.value,
      };
      final msg = diff(cmp(la), cmp(lb), an: 'plain', bn: 'with-unknown');
      if (msg != null) bad.add('seed $s memory: $msg');
      la = await plain.open();
      lb = await unknown.open();
      final msg2 = diff(cmp(la), cmp(lb), an: 'plain', bn: 'with-unknown');
      if (msg2 != null) bad.add('seed $s reopened: $msg2');
      // the unknown field still on every row that still exists and was never rewritten or was rewritten
      var lost = 0, rows = 0;
      final lostShelves = <String>[];
      for (final row in unknown.store!.rows()) {
        if (!{
          'entry',
          'account',
          'category',
          'budget',
          'recurring',
          'trash',
        }.contains(row.shelf)) {
          continue;
        }
        rows++;
        final body = jsonDecode(row.body) as Map<String, Object?>;
        final inner = body['entry'] is Map
            ? (body['entry'] as Map)['zz']
            : null;
        if (body['zz'] != 'future' &&
            body['zz'] != 'future-inner' &&
            inner == null) {
          lost++;
          lostShelves.add(row.shelf);
        }
      }
      if (lost > 0) {
        bad.add(
          'seed $s: unknown field lost on $lost of $rows rows ($lostShelves)',
        );
      }
    }
    // ignore: avoid_print
    print('[P3 unknown fields] seeds 6, failing ${bad.length}: ${bad.take(3)}');
    expect(bad, isEmpty);
  });

  test('P4 a refused write: after settle memory == what the disk holds', () async {
    final bad = <String>[];
    for (final s in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]) {
      final d = disk();
      final base = await seeded(d, s, count: 60);
      final failing = <int>{3 + s, 9 + s, 10 + s, 20 + 2 * s};
      final wrapper = _Flaky(d.source, failing);
      final live = Ledger(
        today: base.today,
        clock: () => d.clock.today().asUtcMidnight,
        accounts: base.accounts.all,
        categories: base.categories.all,
        entries: base.entries.all,
        holdings: const [],
        budgets: base.budgets.all,
        recurring: base.recurring.all,
        trash: base.trash.all,
        receipts: {},
        drafts: {},
        dataSource: wrapper,
      );
      final r = Random(s);
      for (var i = 0; i < 30; i++) {
        act(live, r);
        // let the queue run between some commands: reloads race with edits
        if (r.nextInt(3) == 0) {
          await Future<void>.delayed(Duration(milliseconds: r.nextInt(4)));
        }
      }
      await live.settled;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await live.settled;
      final memory = state(live, order: true);
      final disked = await d.open();
      final msg = diff(
        memory,
        state(disked, order: true),
        an: 'memory',
        bn: 'disk',
      );
      if (msg != null) {
        bad.add('seed $s (failed keeps ${wrapper.failed}): $msg');
      }
    }
    // ignore: avoid_print
    print(
      '[P4 refused writes then reload] seeds 6, failing ${bad.length}: ${bad.take(3)}',
    );
    expect(bad, isEmpty);
  });

  test('P5 two commands in quick succession (auto-book + user edit) in either order end alike, and equal disk', () async {
    final bad = <String>[];
    for (final s in [1, 2, 3, 4, 5, 6, 7, 8]) {
      final results = <String, Map<String, String>>{};
      for (final order in ['AB', 'BA']) {
        final d = disk();
        final live = await seeded(d, s, count: 60);
        // a new day: the rent and pay items are due again
        d.clock.advance(const Duration(days: 6));
        final victim = live.entries.all.firstWhere(
          (e) =>
              e.recurring == null &&
              e.type == EntryType.expense &&
              e.refundOf == null &&
              e.installments < 2 &&
              e.parts.isEmpty,
        );
        void a() => live.recurringCommands.bookDue();
        void bb() => live.entryCommands.replace(mutate(victim, 1));
        if (order == 'AB') {
          a();
          bb();
        } else {
          bb();
          a();
        }
        await live.settled;
        final mem = stable(stats(live));
        final back = await d.open();
        final msg = diff(
          state(live, order: true),
          state(back, order: true),
          an: 'memory',
          bn: 'disk',
        );
        if (msg != null) bad.add('seed $s $order: $msg');
        results[order] = mem;
      }
      final m = diff(results['AB']!, results['BA']!, an: 'A;B', bn: 'B;A');
      if (m != null) bad.add('seed $s: orders differ: $m');
    }
    // ignore: avoid_print
    print(
      '[P5 bookDue + edit, both orders] seeds 8, failing ${bad.length}: ${bad.take(3)}',
    );
    expect(bad, isEmpty);
  });

  test('T1 trash expiry removes exactly the expired, boundary day included', () async {
    final bad = <String>[];
    for (final s in [1, 2, 3, 4, 5]) {
      final d = disk();
      final live = await seeded(d, s, count: 80, recurring: false);
      final r = Random(s);
      final deletedOn = <String, int>{};
      // delete on day offsets 0..44 after Oct 31 (advancing the clock)
      var offset = 0;
      final pool = [
        for (final e in live.entries.all)
          if (e.refundOf == null && !e.isInvestment) e.id,
      ];
      for (var i = 0; i < 12; i++) {
        final step = r.nextInt(5);
        offset += step;
        d.clock.advance(Duration(days: step));
        final id = pool[r.nextInt(pool.length)];
        if (deletedOn.containsKey(id)) continue;
        if (live.entryCommands.remove(id) != null) deletedOn[id] = offset;
      }
      await live.settled;
      // the app stays open past midnight to day `end`: the day turning
      // takes out of the trash what it no longer keeps (D77)
      final end = offset + r.nextInt(40);
      d.clock.advance(Duration(days: end - offset));
      live.checkDay();
      await live.settled;
      final expected = {
        for (final e in deletedOn.entries)
          if (end - e.value <= 30) e.key,
      };
      final inMemory = {for (final t in live.trash.all) t.entry.id};
      final back = await d.open();
      final kept = {for (final t in back.trash.all) t.entry.id};
      if (kept.toString() != expected.toString() &&
          !(kept.length == expected.length && kept.containsAll(expected))) {
        bad.add(
          'seed $s end $end: kept ${kept.length} expected ${expected.length}; wrongly dropped ${expected.difference(kept).length}, wrongly kept ${kept.difference(expected).length}',
        );
      }
      final rowsLeft = {
        for (final row in d.store!.rows(shelf: 'trash')) row.id,
      };
      if (rowsLeft.length != kept.length) {
        bad.add(
          'seed $s: ${rowsLeft.length} trash rows on disk vs ${kept.length} shown',
        );
      }
      // never touches live entries
      final entriesOk = back.entries.length == live.entries.length;
      if (!entriesOk) {
        bad.add(
          'seed $s: entries ${live.entries.length} -> ${back.entries.length}',
        );
      }
      if (inMemory.length < kept.length) {
        bad.add('seed $s: memory trash smaller');
      }
      if (!(inMemory.length == expected.length &&
          inMemory.containsAll(expected))) {
        bad.add(
          'seed $s end $end: the open app keeps ${inMemory.length} in its '
          'trash, expected ${expected.length}',
        );
      }
    }
    // ignore: avoid_print
    print('[T1 trash expiry] seeds 5, failing ${bad.length}: ${bad.take(3)}');
    expect(bad, isEmpty);
  });

  test('T2 restore after account/category/original changed meanwhile: '
      'each said and decided, never done silently (D78)', () async {
    final out = <String>[];
    final d = disk();
    final l = await seeded(d, 4, count: 80, recurring: false);
    // (a) account of a trashed entry: removeAccount refused, archive?
    final e = l.entries.all.firstWhere(
      (e) =>
          e.type == EntryType.expense &&
          e.account == 'cash' &&
          e.refundOf == null &&
          e.installments < 2 &&
          l.entryQueryService.refunded(e) == 0,
    );
    l.entryCommands.remove(e.id);
    final others = l.entries.all
        .where((x) => x.account == 'cash' || x.to == 'cash')
        .map((x) => x.id)
        .toList();
    l.entryCommands.removeAll(others);
    l.accountCommands.removeAccount('cash');
    // Only the trash names it: it is said, not refused silently.
    expect(l.accountCommands.usedOutsideTrash('cash'), isFalse);
    expect(l.accountCommands.trashedNaming('cash'), isNotEmpty);
    out.add(
      '(a) removeAccount(cash) with entries in trash: account ${l.accounts.byId('cash') == null ? 'REMOVED' : 'kept'}',
    );
    final cash = l.account('cash');
    l.accountCommands.updateAccount(cash.copyWith(archived: true));
    final trashedE = l.trash.all.firstWhere((t) => t.entry.id == e.id);
    expect(l.entryCommands.holdsOf(trashedE), [isA<ClosedAccounts>()]);
    // Not put back onto the closed account unasked.
    expect(l.entryCommands.restoreTrashed(trashedE), isFalse);
    expect(l.entries.byId(e.id), isNull);
    final okArchived = l.entryCommands.restoreTrashed(trashedE, reopen: true);
    expect(okArchived, isTrue);
    expect(l.account('cash').archived, isFalse);
    out.add(
      '(a2) restore entry onto an archived account: ${okArchived ? 'restored' : 'refused: ${l.problem.value}'}',
    );
    // (b) category merged meanwhile
    final f = l.entries.all.firstWhere(
      (x) =>
          x.type == EntryType.expense &&
          x.category == '娛樂' &&
          x.parts.isEmpty &&
          x.refundOf == null &&
          x.installments < 2 &&
          x.account != 'cash',
      orElse: () => l.entries.all.first,
    );
    l.entryCommands.remove(f.id);
    l.categoryCommands.mergeCategory('娛樂', '購物');
    final okMerged = l.entryCommands.restoreTrashed(
      l.trash.all.firstWhere((t) => t.entry.id == f.id),
    );
    out.add(
      '(b) merge 娛樂->購物 while entry trashed, restore: ${okMerged ? 'restored as ${l.entries.byId(f.id)?.category}' : 'refused ${l.problem.value}'}',
    );
    // (c) refund restored after its original was deleted
    final original = l.entries.all
        .where(
          (x) =>
              x.type == EntryType.expense &&
              !x.isRefund &&
              x.account != 'cash' &&
              l.entryQueryService.refunded(x) > 0,
        )
        .toList();
    if (original.isNotEmpty) {
      final o = original.first;
      final refund = l.entries.all.firstWhere((x) => x.refundOf == o.id);
      l.entryCommands.remove(refund.id);
      final gone = l.entryCommands.remove(o.id);
      final trashedRefund = l.trash.all.firstWhere(
        (t) => t.entry.id == refund.id,
      );
      expect(l.entryCommands.holdsOf(trashedRefund), [isA<OriginalInTrash>()]);
      expect(l.entryCommands.restoreTrashed(trashedRefund), isFalse);
      final back = l.entryCommands.restoreTrashed(
        trashedRefund,
        withOriginal: true,
      );
      expect(back, isTrue);
      expect(l.entries.byId(o.id), isNotNull, reason: 'both back');
      expect(l.integrityService.problems(), isEmpty);
      out.add(
        '(c) original deleted (${gone != null ? 'ok' : 'refused: ${l.problem.value}'}) then refund restored: ${back ? 'restored with its original' : 'refused ${l.problem.value}'}',
      );
    }
    // (d) edit form opened on X, X deleted meanwhile, form saved
    final x = l.entries.all.firstWhere(
      (x) =>
          x.type == EntryType.expense &&
          x.account == 'bank' &&
          x.refundOf == null &&
          x.installments < 2 &&
          l.entryQueryService.refunded(x) == 0,
    );
    l.entryCommands.remove(x.id);
    expect(
      () => l.entryCommands.save([mutate(x, 0)], replacing: [x.id]),
      throwsA(
        isA<RecordRefused>().having(
          (r) => r.first,
          'first',
          isA<EntryDeleted>(),
        ),
      ),
    );
    final inBook = l.entries.byId(x.id) != null;
    final inTrash = l.trash.all.any((t) => t.entry.id == x.id);
    expect((inBook, inTrash), (false, true));
    out.add(
      '(d) delete while its edit form is open, then save: in book $inBook, still in trash $inTrash',
    );
    final reopened = await (() async {
      await l.settled;
      return d.open();
    })();
    final inBook2 = reopened.entries.byId(x.id) != null;
    final inTrash2 = reopened.trash.all.any((t) => t.entry.id == x.id);
    out.add('    after reopen: in book $inBook2, trash $inTrash2');
    expect((inBook2, inTrash2), (false, true));
    // ignore: avoid_print
    print('[T2 restore into a changed book]\n  ${out.join('\n  ')}');
  });
}

/// Delegates to the real data source, refusing the keeps numbered in [failing].
class _Flaky implements LedgerDataSource {
  _Flaky(this._inner, this.failing);
  final SqlLedgerDataSource _inner;
  final Set<int> failing;
  var _n = 0;
  var failed = 0;

  @override
  Future<Ledger> load() => _inner.load();

  @override
  Future<void> keep(WriteBatch batch) async {
    _n++;
    if (failing.contains(_n)) {
      failed++;
      throw const DataSourceException('disk full (injected)');
    }
    return _inner.keep(batch);
  }
}
