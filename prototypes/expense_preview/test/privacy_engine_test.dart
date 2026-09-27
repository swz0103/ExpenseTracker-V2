import 'dart:async';
import 'dart:io';

import 'package:backup_envelope_probe/envelope.dart';
import 'package:expense_preview/preview_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  late Directory root, work;
  late MemoryVault vault;
  late PreviewEngine engine;
  setUp(() async {
    root = Directory('.dart_tool/privacy-engine-tests')
      ..createSync(recursive: true);
    work = root.createTempSync('case-');
    vault = MemoryVault();
    engine = engineAt(work, vault, schemaVersion: 7);
    await setup(engine);
    final a = account(engine);
    await engine.createAccount(a, opening(a));
  });
  tearDown(() async {
    await engine.lock();
    deleteSynthetic(work, root);
  });
  test(
    'preference survives reopening and never changes financial snapshot',
    () async {
      final codec = EnvelopeCodec();
      final before = await codec.openWithPassword(
        await engine.exportBackup(),
        password,
      );
      expect(await engine.privacyMode(), PrivacyMode.visible);
      await engine.setPrivacyMode(PrivacyMode.hidden);
      await engine.lock();
      engine = engineAt(work, vault, schemaVersion: 7);
      await engine.unlock(password);
      expect(await engine.privacyMode(), PrivacyMode.hidden);
      final after = await codec.openWithPassword(
        await engine.exportBackup(),
        password,
      );
      expect(after, before);
      await engine.setPrivacyMode(PrivacyMode.visible);
      expect(await engine.privacyMode(), PrivacyMode.visible);
    },
  );
  test('unreadable unknown or failed-write preferences cannot silently reveal values', () async {
    await engine.setPrivacyMode(PrivacyMode.hidden);
    vault.failWrites = true;
    await expectLater(
      engine.setPrivacyMode(PrivacyMode.visible),
      throwsStateError,
    );
    expect(await engine.privacyMode(), PrivacyMode.hidden);
    vault.failWrites = false;
    final key = vault.values.keys.singleWhere(
      (k) => k.startsWith('privacy_v1_'),
    );
    vault.values[key] = 'future-value';
    expect(await engine.privacyMode(), PrivacyMode.hidden);
    vault.beforeRead = (name) async {
      if (name == key) throw StateError('unreadable');
    };
    expect(await engine.privacyMode(), PrivacyMode.hidden);
    vault.beforeRead = null;
    await engine.setPrivacyMode(PrivacyMode.visible);
    expect(await engine.privacyMode(), PrivacyMode.visible);
  });
  test('locking invalidates an in-flight preference read and rejects locked writes', () async {
    final entered = Completer<void>(), release = Completer<void>();
    vault.beforeRead = (name) async {
      if (name.startsWith('privacy_v1_')) {
        entered.complete();
        await release.future;
      }
    };
    final reading = engine.privacyMode();
    final expected = expectLater(reading, throwsA(isA<PreviewLocked>()));
    await entered.future;
    await engine.lock();
    release.complete();
    await expected;
    await expectLater(
      engine.setPrivacyMode(PrivacyMode.visible),
      throwsA(isA<PreviewLocked>()),
    );
    vault.beforeRead = null;
  });
  test('locking during preference readback invalidates reveal and retains its profile key', () async {
    await engine.setPrivacyMode(PrivacyMode.hidden);
    final entered = Completer<void>(), release = Completer<void>();
    final key = vault.values.keys.singleWhere(
      (k) => k.startsWith('privacy_v1_'),
    );
    vault.beforeRead = (name) async {
      if (name == key) {
        entered.complete();
        await release.future;
      }
    };
    final writing = engine.setPrivacyMode(PrivacyMode.visible);
    final expected = expectLater(writing, throwsA(isA<PreviewLocked>()));
    await entered.future;
    await engine.lock();
    release.complete();
    await expected;
    vault.beforeRead = null;
    expect(vault.values.keys.where((k) => k.startsWith('privacy_v1_')), [key]);
    await engine.unlock(password);
    // The explicitly requested setting may have persisted before interruption.
    // No old operation is allowed to publish a revealed view after locking.
    expect(await engine.privacyMode(), PrivacyMode.visible);
  });
  test('restore keeps the destination profile privacy and profiles remain isolated', () async {
    await engine.setPrivacyMode(PrivacyMode.hidden);
    final backup = await engine.exportBackup();
    final other = engineAt(
      Directory('${work.path}/other'),
      vault,
      schemaVersion: 7,
    );
    try {
      await setup(other);
      expect(await other.privacyMode(), PrivacyMode.visible);
      await other.setPrivacyMode(PrivacyMode.hidden);
      await engine.setPrivacyMode(PrivacyMode.visible);
      expect(await other.privacyMode(), PrivacyMode.hidden);
      await other.importBackup(backup, password, recovery: false);
      expect(await other.privacyMode(), PrivacyMode.hidden);
      expect(
        (await other.accounts()).single.balance.minorUnits,
        BigInt.from(10000),
      );
    } finally {
      await other.lock();
    }
  });
}
