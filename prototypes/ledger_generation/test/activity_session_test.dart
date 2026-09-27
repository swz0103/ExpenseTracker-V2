import 'dart:convert';
import 'dart:io';

import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:ledger_generation_probe/ledger_store.dart';
import 'package:storage_generation_probe/fixture_key_slots.dart';
import 'package:storage_generation_probe/fixture_catalog_protection.dart';
import 'package:test/test.dart';

import 'session_test.dart'
    show ws, other, op, account, opening, income, ref, currency;

void main() {
  final root = Directory('.dart_tool/activity-tests')
    ..createSync(recursive: true);
  late Directory work;
  setUp(() => work = root.createTempSync('case-'));
  tearDown(() {
    if (!work.resolveSymbolicLinksSync().startsWith(
      '${root.resolveSymbolicLinksSync()}${Platform.pathSeparator}',
    )) {
      throw StateError('Unsafe cleanup');
    }
    work.deleteSync(recursive: true);
  });
  LedgerStore store(String name, {bool refunds = false}) {
    final keys = FixtureKeySlots(Directory('${work.path}/$name-keys'));
    return LedgerStore(
      Directory('${work.path}/$name'),
      keys,
      catalogProtection: fixtureCatalogProtection(keys),
      refundsAware: refunds,
    );
  }

  test('legacy activity is workspace scoped, read only and revoked with its session', () async {
    final db = store('old');
    await db.initialize(op());
    final a = account(), first = opening(account());
    // Opening must refer to the same account as the command.
    final initial = opening(a), p = income(a);
    late LedgerSession closed;
    await db.withSession((s) async {
      closed = s;
      await s.createAccount(a, initial);
      await s.post(p);
      final before = await s.snapshot();
      final rows = await s.activity(ws, initial.id);
      expect(rows.single.entry.id, initial.id);
      expect(rows.single.entry.kind, PostingKind.opening);
      expect(
        await s.activity(ws, initial.id, before: rows.single.cursor),
        isEmpty,
      );
      expect((await s.activity(ws, p.id)).single.entry.amount, p.reportIncome);
      await expectLater(s.activity(other, p.id), throwsStateError);
      await expectLater(s.activity(ws, first.id), throwsStateError);
      await expectLater(
        s.activity(ws, p.id, before: rows.single.cursor),
        throwsArgumentError,
      );
      for (final limit in [0, 101]) {
        await expectLater(
          s.activity(ws, p.id, limit: limit),
          throwsArgumentError,
        );
      }
      expect(await s.snapshot(), before);
    });
    await expectLater(closed.activity(ws, p.id), throwsA(isA<SessionClosed>()));
  });

  test('refund family pages have exact instant ordering, stable ties, no replay duplicates and restore identically', () async {
    final db = store('current', refunds: true);
    await db.initialize(op());
    final a = account();
    final p = Posting.expense(
      id: PublicId.generate(),
      operation: OperationKey(ws, op()),
      date: BusinessDate(2026, 9, 1),
      account: ref(a),
      amount: Money.parse(currency, '100'),
    );
    final refunds = <Posting>[];
    await db.withSession((s) async {
      await s.createAccount(a, opening(a));
      await s.post(p);
      await s.post(
        income(a, amount: '1'),
      ); // unrelated, must never leak into family.
      for (var i = 0; i < 64; i++) {
        final r = Posting.refund(
          id: PublicId.generate(),
          operation: OperationKey(ws, op()),
          date: BusinessDate(2026, 9, 2 + i % 20),
          account: ref(a),
          originalId: p.id,
          amount: Money.parse(currency, '1'),
        );
        refunds.add(r);
        await s.post(r);
        await s.post(r);
      }
    });
    final parsed = jsonDecode(utf8.decode(await db.snapshot())) as Map;
    final family = {p.id.value, ...refunds.map((p) => p.id.value)};
    final instants = <String, String>{};
    const times = [
      '2026-09-28T01:02:03Z',
      '2026-09-28T01:02:03.1Z',
      '2026-09-28T01:02:03.10Z',
      '2026-09-28T01:02:03.100001Z',
      '2026-09-28T01:02:03.999999Z',
    ];
    var i = 0;
    for (final row in parsed['tables']['audit'] as List) {
      final id = row['entity_id'] as String;
      if (family.contains(id)) {
        row['recorded_at'] = times[i++ % times.length];
        instants[id] = row['recorded_at'];
      }
    }
    await db.generations.install(jsonEncode(parsed), op());
    final before = await db.snapshot();
    final expected = family.toList()
      ..sort((a, b) {
        final order = UtcInstant.parse(instants[b]!)
            .compareTo(UtcInstant.parse(instants[a]!));
        return order != 0 ? order : b.compareTo(a);
      });
    Future<List<String>> scan(LedgerStore target, PublicId selected) =>
        target.withSession((s) async {
          final result = <String>[];
          LedgerActivityCursor? cursor;
          for (;;) {
            final page = await s.activity(
              ws,
              selected,
              before: cursor,
              limit: 7,
            );
            if (page.isEmpty) break;
            result.addAll(page.map((r) => r.entry.id.value));
            cursor = page.last.cursor;
          }
          return result;
        });
    expect(await scan(db, p.id), expected);
    expect(await scan(db, refunds.last.id), expected);
    expect(await db.snapshot(), before);
    final restored = store('restored', refunds: true);
    await restored.generations.install(utf8.decode(before), op());
    expect(await scan(restored, p.id), expected);
    expect(await restored.snapshot(), before);
  });
}
