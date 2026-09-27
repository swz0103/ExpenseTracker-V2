import 'dart:async';
import 'dart:io';

import 'package:expense_preview/preview_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_values/foundation_values.dart';

import 'support.dart';

void main() {
  late Directory work;
  late MemoryVault vault;
  late PreviewEngine engine;
  String? stop;
  EntryFields fields(
    PublicId account, {
    String amount = '7',
    bool income = true,
  }) => EntryFields(
    income: income,
    amount: amount,
    date: '2026-09-27',
    accountId: account,
  );
  setUp(() async {
    final root = Directory('.dart_tool/draft-engine-tests')
      ..createSync(recursive: true);
    work = root.createTempSync('app-');
    vault = MemoryVault();
    stop = null;
    engine = engineAt(
      work,
      vault,
      schemaVersion: 7,
      draftCheckpoint: (p) {
        if (p == stop) throw StateError('injected-$p');
      },
    );
    await setup(engine);
    final a = account(engine);
    await engine.createAccount(a, opening(a));
  });
  tearDown(() async {
    await engine.lock();
    deleteSynthetic(work, Directory('.dart_tool/draft-engine-tests'));
  });
  test('incomplete draft survives reopen without financial effects; invalid submit remains editable', () async {
    final a = (await engine.accounts()).single.account;
    final original = await engine.saveEntryDraft(fields(a.id, amount: '12.'));
    expect((await engine.entries()).length, 1);
    expect(
      (await engine.accounts()).single.balance.minorUnits,
      BigInt.from(10000),
    );
    await engine.lock();
    engine = engineAt(work, vault, schemaVersion: 7);
    await engine.unlock(password);
    expect((await engine.entryDraft())!.encode(), original.encode());
    await engine.saveEntryDraft(fields(a.id, amount: ''));
    await expectLater(engine.submitEntryDraft(), throwsA(anything));
    expect((await engine.entryDraft())!.submission, null);
    await engine.saveEntryDraft(fields(a.id));
    await engine.submitEntryDraft();
    expect(await engine.entryDraft(), null);
    expect((await engine.entries()).length, 2);
    expect(
      (await engine.accounts()).single.balance.minorUnits,
      BigInt.from(10700),
    );
    await expectLater(
      engine.submitEntryDraft(),
      throwsA(isA<PreviewInvalid>()),
    );
    expect((await engine.entries()).length, 2);
  });
  test(
    'prepared interruption does not post; frozen identity retries exactly once',
    () async {
      final a = (await engine.accounts()).single.account;
      final d = await engine.saveEntryDraft(fields(a.id));
      stop = 'draft-prepared';
      await expectLater(engine.submitEntryDraft(), throwsStateError);
      expect((await engine.entries()).length, 1);
      await expectLater(
        engine.saveEntryDraft(fields(a.id, amount: '8')),
        throwsA(isA<DraftNeedsResolution>()),
      );
      await engine.lock();
      engine = engineAt(work, vault, schemaVersion: 7);
      await engine.unlock(password);
      expect((await engine.entryDraft())!.submission, isNotNull);
      await engine.submitEntryDraft();
      expect((await engine.entries()).first.id, d.id);
      expect((await engine.entries()).length, 2);
      expect(await engine.entryDraft(), null);
    },
  );
  test(
    'commit without draft cleanup reconciles across restart without duplicate',
    () async {
      final a = (await engine.accounts()).single.account;
      final d = await engine.saveEntryDraft(fields(a.id));
      stop = 'draft-committed';
      await expectLater(engine.submitEntryDraft(), throwsStateError);
      expect((await engine.entries()).length, 2);
      await engine.lock();
      engine = engineAt(work, vault, schemaVersion: 7);
      await engine.unlock(password);
      expect(await engine.entryDraft(), null);
      expect((await engine.entries()).first.id, d.id);
      expect(
        (await engine.accounts()).single.balance.minorUnits,
        BigInt.from(10700),
      );
    },
  );
  test('metadata preserved, archive blocks new submission, committed replay survives rename', () async {
    final a = (await engine.accounts()).single.account;
    final merchantId = PublicId.generate(), tagId = PublicId.generate();
    OperationKey op() =>
        OperationKey(engine.workspace, OperationId(PublicId.generate()));
    await engine.createMerchant(op(), merchantId, 'Shop');
    await engine.createTag(op(), tagId, 'Travel');
    await engine.saveEntryDraft(
      EntryFields(
        income: false,
        amount: '7',
        date: '2026-09-27',
        accountId: a.id,
        merchantId: merchantId,
        tags: [tagId],
      ),
    );
    final tag = (await engine.tags()).get(tagId);
    await engine.archiveTag(op(), tag, archived: true);
    await expectLater(
      engine.submitEntryDraft(),
      throwsA(isA<PreviewInvalid>()),
    );
    expect((await engine.entries()).length, 1);
    await engine.archiveTag(
      op(),
      (await engine.tags()).get(tagId),
      archived: false,
    );
    stop = 'draft-committed';
    await expectLater(engine.submitEntryDraft(), throwsStateError);
    await engine.renameMerchant(
      op(),
      (await engine.merchants()).get(merchantId),
      'Renamed',
    );
    stop = null;
    expect(await engine.entryDraft(), null);
    final event = (await engine.entries()).first;
    expect((await engine.merchantFor(event.id))!.id, merchantId);
    expect((await engine.tagsFor(event.id)).single.id, tagId);
  });
  test('backup and restore require resolving local staging; restored generation accepts new draft', () async {
    final backup = await engine.exportBackup();
    final a = (await engine.accounts()).single.account;
    await engine.saveEntryDraft(fields(a.id));
    await expectLater(
      engine.exportBackup(),
      throwsA(isA<DraftNeedsResolution>()),
    );
    await expectLater(
      engine.importBackup(backup, password, recovery: false),
      throwsA(isA<DraftNeedsResolution>()),
    );
    await engine.discardEntryDraft();
    await engine.importBackup(backup, password, recovery: false);
    expect((await engine.entries()).length, 1);
    await engine.saveEntryDraft(fields(a.id));
    await engine.submitEntryDraft();
    final newer = await engine.exportBackup();
    await engine.importBackup(newer, password, recovery: false);
    expect((await engine.entries()).length, 2);
    expect(await engine.entryDraft(), null);
  });
  test('lock during accepted write drains it, invalidates caller, and preserves recovery', () async {
    final a = (await engine.accounts()).single.account;
    await engine.saveEntryDraft(fields(a.id));
    final entered = Completer<void>(), release = Completer<void>();
    vault.beforeRead = (name) async {
      if (name.startsWith('manual_draft_key_') && !entered.isCompleted) {
        entered.complete();
        await release.future;
      }
    };
    final save = engine.saveEntryDraft(fields(a.id, amount: '9'));
    final expected = expectLater(save, throwsA(isA<PreviewLocked>()));
    await entered.future;
    final closing = engine.lock();
    release.complete();
    await expected;
    await closing;
    vault.beforeRead = null;
    await engine.unlock(password);
    // Lock before acceptance of the replacement keeps prior acknowledged input.
    expect((await engine.entryDraft())!.fields.amount, '7');
  });
  test('uncommitted prepared form explicitly returns to editing; discard never deletes ledger', () async {
    final a = (await engine.accounts()).single.account;
    await engine.saveEntryDraft(fields(a.id));
    stop = 'draft-prepared';
    await expectLater(engine.submitEntryDraft(), throwsStateError);
    stop = null;
    await engine.reopenEntryDraft();
    await engine.saveEntryDraft(fields(a.id, amount: '8'));
    stop = 'draft-committed';
    await expectLater(engine.submitEntryDraft(), throwsStateError);
    await expectLater(
      engine.reopenEntryDraft(),
      throwsA(isA<DraftNeedsResolution>()),
    );
    await engine.discardEntryDraft();
    expect((await engine.entries()).length, 2);
    expect(
      (await engine.accounts()).single.balance.minorUnits,
      BigInt.from(10800),
    );
  });
  for (final point in ['draft-staged', 'draft-prepared', 'draft-committed']) {
    test(
      'lock at $point drains accepted work and resolves durable state',
      () async {
        await engine.lock();
        Future<void>? closing;
        var enabled = false;
        engine = engineAt(
          work,
          vault,
          schemaVersion: 7,
          draftCheckpoint: (p) {
            if (enabled && p == point) {
              enabled = false;
              closing = engine.lock();
            }
          },
        );
        await engine.unlock(password);
        final a = (await engine.accounts()).single.account;
        await engine.saveEntryDraft(fields(a.id));
        enabled = true;
        if (point == 'draft-staged') {
          await expectLater(
            engine.saveEntryDraft(fields(a.id, amount: '9')),
            throwsA(isA<PreviewLocked>()),
          );
        } else {
          await expectLater(
            engine.submitEntryDraft(),
            throwsA(isA<PreviewLocked>()),
          );
        }
        await closing;
        await engine.unlock(password);
        final draft = await engine.entryDraft();
        if (point == 'draft-committed') {
          expect(draft, null);
          expect((await engine.entries()).length, 2);
        } else {
          expect(draft, isNotNull);
          expect((await engine.entries()).length, 1);
          if (point == 'draft-staged') expect(draft!.fields.amount, '9');
        }
      },
    );
  }

  test('schema upgrade blocks unresolved local form and succeeds after source-version resolution', () async {
    await engine.lock();
    final legacyWork = Directory('${work.path}/legacy');
    final legacy = engineAt(legacyWork, vault, schemaVersion: 6);
    await setup(legacy);
    final a = account(legacy);
    await legacy.createAccount(a, opening(a));
    await legacy.saveEntryDraft(fields(a.id));
    await legacy.lock();
    final target = engineAt(legacyWork, vault, schemaVersion: 7);
    try {
      await expectLater(
        target.upgrade(password),
        throwsA(isA<DraftNeedsResolution>()),
      );
      await legacy.unlock(password);
      expect((await legacy.entryDraft())!.fields.amount, '7');
      await legacy.submitEntryDraft();
      await legacy.lock();
      await target.upgrade(password);
      expect((await target.entries()).length, 2);
      expect(await target.entryDraft(), null);
    } finally {
      await legacy.lock();
      await target.lock();
    }
  });
  for (final point in [
    'draft-restore-cleared',
    'draft-restore-ready',
    'draft-restore-opened',
  ]) {
    test('restore locking at $point cannot reopen an unlocked lease', () async {
      await engine.lock();
      var enabled = false;
      Future<void>? closing;
      engine = engineAt(
        work,
        vault,
        schemaVersion: 7,
        draftCheckpoint: (p) {
          if (enabled && p == point) {
            enabled = false;
            closing = engine.lock();
          }
        },
      );
      await engine.unlock(password);
      final backup = await engine.exportBackup();
      final a = (await engine.accounts()).single.account;
      await engine.post(income(a));
      enabled = true;
      await expectLater(
        engine.importBackup(backup, password, recovery: false),
        throwsA(isA<PreviewLocked>()),
      );
      await closing;
      expect(engine.isUnlocked, false);
      await engine.unlock(password);
      expect(
        (await engine.entries()).length,
        point == 'draft-restore-cleared' ? 2 : 1,
      );
      await engine.saveEntryDraft(fields(a.id));
      expect(await engine.entryDraft(), isNotNull);
    });
  }
  test('financial rejection after preparing rolls back and permits explicit corrected retry', () async {
    final a = (await engine.accounts()).single.account;
    final draft = await engine.saveEntryDraft(
      EntryFields(
        income: true,
        amount: '7',
        date: '2000-01-01',
        accountId: a.id,
      ),
    );
    await expectLater(engine.submitEntryDraft(), throwsA(anything));
    expect((await engine.entryDraft())!.submission, isNotNull);
    expect((await engine.entries()).length, 1);
    await engine.reopenEntryDraft();
    await engine.saveEntryDraft(fields(a.id));
    await engine.submitEntryDraft();
    expect((await engine.entries()).first.id, draft.id);
    expect(
      (await engine.accounts()).single.balance.minorUnits,
      BigInt.from(10700),
    );
  });
}
