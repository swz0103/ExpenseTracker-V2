import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:expense_preview/preview_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';

import 'support.dart';

void main() {
  final root = Directory('.dart_tool/note-engine-tests')
    ..createSync(recursive: true);
  late Directory work;
  late MemoryVault vault;
  late PreviewEngine engine;
  late Account a;
  late Posting p;
  String? stop;
  EntryFields fields(String text, {int revision = 0}) => EntryFields(
    income: false,
    amount: '',
    date: '',
    noteOf: p.id,
    noteRevision: revision,
    noteText: text,
  );
  setUp(() async {
    work = root.createTempSync('case-');
    vault = MemoryVault();
    stop = null;
    engine = engineAt(
      work,
      vault,
      schemaVersion: 12,
      draftCheckpoint: (point) {
        if (point == stop) throw StateError('injected');
      },
    );
    await setup(engine);
    a = account(engine);
    p = income(a);
    await engine.createAccount(a, opening(a));
    await engine.post(p);
  });
  tearDown(() async {
    await engine.lock();
    deleteSynthetic(work, root);
  });
  test('encrypted raw note survives lock without posting; frozen commit reconciles exactly once', () async {
    final d = await engine.saveEntryDraft(fields('  原始\n🙂  '));
    await engine.lock();
    engine = engineAt(
      work,
      vault,
      schemaVersion: 12,
      draftCheckpoint: (point) {
        if (point == stop) throw StateError('injected');
      },
    );
    await engine.unlock(password);
    expect((await engine.entryDraft())!.encode(), d.encode());
    expect((await engine.entryNote(p.id)).revision, 0);
    await expectLater(
      engine.exportBackup(),
      throwsA(isA<DraftNeedsResolution>()),
    );
    stop = 'draft-prepared';
    await expectLater(engine.submitEntryDraft(), throwsStateError);
    expect((await engine.entryDraft())!.isPrepared, true);
    expect((await engine.entryNote(p.id)).revision, 0);
    await expectLater(
      engine.saveEntryDraft(fields('changed')),
      throwsA(isA<DraftNeedsResolution>()),
    );
    stop = 'draft-committed';
    await expectLater(engine.submitEntryDraft(), throwsStateError);
    expect(await engine.entryDraft(), null);
    expect((await engine.entryNote(p.id)).revision, 1);
    expect(
      (await engine.accounts()).single.balance,
      Money.parse(a.currency, '107'),
    );
    expect(await engine.entries(), hasLength(2));
    expect(
      (await engine.activity(p.id)).where((r) => r.noteRevision != null),
      hasLength(1),
    );
    stop = null;
    await engine.saveEntryDraft(fields('', revision: 1));
    await engine.submitEntryDraft();
    expect((await engine.entryNote(p.id)).text, '');
    expect(await engine.exportBackup(), isNotEmpty);
  });
  test('stale draft refuses overwrite; explicit refresh preserves text and clears failed freeze', () async {
    await engine.saveEntryDraft(fields('current'));
    await engine.submitEntryDraft();
    await engine.saveEntryDraft(fields('my stale text'));
    await expectLater(engine.submitEntryDraft(), throwsA(isA<NoteException>()));
    expect((await engine.entryNote(p.id)).text, 'current');
    final refreshed = await engine.refreshNoteDraft();
    expect(refreshed.isPrepared, false);
    expect(refreshed.fields.noteRevision, 1);
    expect(refreshed.fields.noteText, 'my stale text');
    await engine.submitEntryDraft();
    expect((await engine.entryNote(p.id)).revision, 2);
    await engine.saveEntryDraft(fields('my stale text', revision: 2));
    await expectLater(engine.submitEntryDraft(), throwsA(isA<NoteException>()));
    await engine.reopenEntryDraft();
    expect((await engine.entryDraft())!.isPrepared, false);
    await engine.discardEntryDraft();
  });
  test(
    'schema 11 encrypted upgrade retains prior ledger and unlocks note editing',
    () async {
      await engine.lock();
      deleteSynthetic(work, root);
      work = root.createTempSync('upgrade-');
      vault = MemoryVault();
      engine = engineAt(work, vault, schemaVersion: 11);
      await setup(engine);
      a = account(engine);
      p = income(a);
      await engine.createAccount(a, opening(a));
      await engine.post(p);
      await engine.lock();
      engine = engineAt(work, vault, schemaVersion: 12);
      await engine.upgrade(password);
      await engine.saveEntryDraft(fields('after upgrade'));
      await engine.submitEntryDraft();
      expect((await engine.entryNote(p.id)).revision, 1);
      expect(
        (await engine.accounts()).single.balance,
        Money.parse(a.currency, '107'),
      );
    },
  );
}
