import 'dart:convert';
import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:ledger_generation_probe/ledger_store.dart';
import 'package:modular_persistence_probe/operations.dart';
import 'package:storage_generation_probe/fixture_key_slots.dart';
import 'package:storage_generation_probe/fixture_catalog_protection.dart';
import 'package:validated_restore_probe/snapshot.dart';
import 'package:test/test.dart';

import 'session_test.dart'
    show op, ws, other, currency, account, opening, income;

void main() {
  final root = Directory('.dart_tool/note-tests')..createSync(recursive: true);
  late Directory work;
  late LedgerStore store;
  late Account a;
  late Posting p;
  OperationKey operation() => OperationKey(ws, op());
  LedgerStore target(String name) {
    final keys = FixtureKeySlots(Directory('${work.path}/$name-keys'));
    return LedgerStore(
      Directory('${work.path}/$name'),
      keys,
      catalogProtection: fixtureCatalogProtection(keys),
      notesAware: true,
    );
  }

  setUp(() async {
    work = root.createTempSync('case-');
    store = target('source');
    await store.initialize(op());
    a = account();
    p = income(a);
    await store.withSession((s) async {
      await s.createAccount(a, opening(a));
      await s.post(p);
    });
  });
  tearDown(() {
    if (!work.resolveSymbolicLinksSync().startsWith(
      '${root.resolveSymbolicLinksSync()}${Platform.pathSeparator}',
    ))
      throw StateError('Unsafe cleanup');
    work.deleteSync(recursive: true);
  });
  test('note revisions replay once, stale updates fail, financial receipt remains exact', () async {
    await store.withSession((s) async {
      final key = operation(), first = NoteChange(p.id, 0, 'first');
      final results = await Future.wait(
        List.generate(10, (_) => s.reviseNote(key, first)),
      );
      expect(results.where((r) => !r.replayed), hasLength(1));
      final before = await s.snapshot();
      await expectLater(
        s.reviseNote(key, NoteChange(p.id, 0, 'different')),
        throwsA(isA<OperationConflict>()),
      );
      await expectLater(
        s.reviseNote(operation(), NoteChange(p.id, 0, 'stale')),
        throwsA(isA<NoteException>()),
      );
      await expectLater(
        s.reviseNote(operation(), NoteChange(p.id, 1, 'first')),
        throwsA(isA<NoteException>()),
      );
      await expectLater(
        s.reviseNote(OperationKey(other, op()), NoteChange(p.id, 0, 'other')),
        throwsA(isA<NoteException>()),
      );
      expect(await s.snapshot(), before);
      expect((await s.reversalSource(ws, p.id)).posting.id, p.id);
      final r = Posting.reversal(
        id: PublicId.generate(),
        operation: operation(),
        date: p.date,
        original: p,
        reason: 'test',
      );
      await s.post(r);
      await s.reviseNote(operation(), NoteChange(p.id, 1, ''));
      await s.reviseNote(operation(), NoteChange(r.id, 0, 'reversed'));
      expect((await s.reviseNote(key, first)).replayed, true);
      expect((await s.entry(ws, p.id))!.note.revision, 2);
      expect((await s.entryNote(ws, p.id)).text, '');
      expect(
        (await s.accounts(ws)).single.balance,
        Money.parse(currency, '100'),
      );
      final page1 = await s.activity(ws, r.id, limit: 2);
      final page2 = await s.activity(
        ws,
        p.id,
        before: page1.last.cursor,
        limit: 2,
      );
      final page3 = await s.activity(
        ws,
        p.id,
        before: page2.last.cursor,
        limit: 2,
      );
      final all = [...page1, ...page2, ...page3];
      expect(all, hasLength(5));
      expect(all.map((r) => r.key).toSet(), hasLength(5));
      expect(all.where((r) => r.noteRevision != null), hasLength(3));
    });
    final bytes = await store.snapshot();
    expect(validateSessionCapacity(bytes, notesAware: true), bytes);
    final restored = target('restore');
    await restored.generations.install(utf8.decode(bytes), op());
    expect(await restored.snapshot(), bytes);
  });
  test(
    'every ACID checkpoint rolls back and retry preserves maximal escaped text',
    () async {
      await store.withSession((s) async {
        final initial = await s.snapshot();
        for (final point in ['note', 'receipt', 'audit']) {
          final key = operation(),
              change = NoteChange(p.id, 0, '\u0001' * 1024);
          await expectLater(
            s.reviseNote(
              key,
              change,
              checkpoint: (p) {
                if (p == point) throw StateError('injected');
              },
            ),
            throwsStateError,
          );
          expect(await s.snapshot(), initial);
        }
        await s.reviseNote(operation(), NoteChange(p.id, 0, '\u0001' * 1024));
        await s.reviseNote(operation(), NoteChange(p.id, 1, '🙂' * 1024));
        expect((await s.entryNote(ws, p.id)).revision, 2);
      });
      final bytes = await store.snapshot();
      expect(validateSessionCapacity(bytes, notesAware: true), bytes);
      await target('restore').generations.install(utf8.decode(bytes), op());
    },
  );
  test(
    'restore rejects missing, reordered, altered or detached note history',
    () async {
      await store.withSession((s) async {
        await s.reviseNote(operation(), NoteChange(p.id, 0, 'first'));
        await s.reviseNote(operation(), NoteChange(p.id, 1, 'second'));
      });
      final bytes = await store.snapshot();
      final mutations = <void Function(Map)>[
        (t) => (t['event_note_revisions'] as List).removeAt(0),
        (t) => t['event_note_revisions'][1]['revision'] = '3',
        (t) => t['event_note_revisions'][0]['text'] = 'tampered',
        (t) => t['event_note_revisions'][0]['event_id'] =
            PublicId.generate().value,
        (t) =>
            (t['audit'] as List).removeWhere((r) => r['kind'] == 'ledger.note'),
        (t) => (t['event_note_revisions'] as List).clear(),
        (t) {
          final r = (t['receipts'] as List).last;
          final v = jsonDecode(r['input'] as String) as List;
          v[2] = 0;
          r['input'] = jsonEncode(v);
        },
      ];
      for (var i = 0; i < mutations.length; i++) {
        final value = jsonDecode(utf8.decode(bytes)) as Map;
        mutations[i](value['tables'] as Map);
        await expectLater(
          target('bad$i').generations.install(jsonEncode(value), op()),
          throwsA(anything),
        );
      }
      expect(
        () => SnapshotCodec(reversalsAware: true).canonicalize(bytes),
        throwsA(isA<InvalidSnapshot>()),
      );
    },
  );
  test('tagged merchant note restore is receipt-order independent and equal-time pages retain every activity', () async {
    final tagged = income(a),
        tag = PublicId.generate(),
        merchant = PublicId.generate();
    await store.withSession((s) async {
      await s.createTag(operation(), tag, 'tag');
      await s.createMerchant(operation(), merchant, 'merchant');
      await s.post(
        tagged,
        tags: [TagSelection(tag, 1)],
        merchant: MerchantSelection(merchant, 1),
      );
      await s.reviseNote(operation(), NoteChange(tagged.id, 0, 'first'));
      await s.reviseNote(operation(), NoteChange(tagged.id, 1, 'second'));
    });
    final value = jsonDecode(utf8.decode(await store.snapshot())) as Map;
    final tables = value['tables'] as Map;
    tables['receipts'] = (tables['receipts'] as List).reversed.toList();
    for (final row in tables['audit'] as List)
      row['recorded_at'] = '2026-09-28T00:00:00.000001Z';
    final restored = target('reordered');
    await restored.generations.install(jsonEncode(value), op());
    await restored.withSession((s) async {
      expect((await s.entryNote(ws, tagged.id)).text, 'second');
      expect((await s.tagsFor(ws, tagged.id)).single.id, tag);
      expect((await s.merchantFor(ws, tagged.id))!.id, merchant);
      final rows = <LedgerActivity>[];
      LedgerActivityCursor? cursor;
      while (true) {
        final page = await s.activity(ws, tagged.id, before: cursor, limit: 1);
        if (page.isEmpty) break;
        rows.addAll(page);
        cursor = page.last.cursor;
      }
      expect(rows, hasLength(3));
      expect(rows.map((r) => r.key).toSet(), hasLength(3));
      expect(
        rows
            .where((r) => r.noteRevision != null)
            .map((r) => r.noteRevision!.text)
            .toSet(),
        {'first', 'second'},
      );
    });
  });
}
