import 'package:backup_envelope_probe/envelope.dart';

import 'dart:convert';
import 'dart:io';

import 'package:expense_preview/preview_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_values/foundation_values.dart';

import 'support.dart';

void main() {
  final root = Directory('.dart_tool/transfer-engine-tests')
    ..createSync(recursive: true);
  late Directory work;
  late MemoryVault vault;
  late PreviewEngine engine;
  late PublicId source, destination;
  late String recovery;
  String? stop;
  EntryFields fields({
    String amount = '20',
    String fee = '1.25',
    PublicId? to,
  }) => EntryFields(
    income: false,
    transfer: true,
    amount: amount,
    fee: fee,
    date: '2026-09-27',
    accountId: source,
    destinationId: to ?? destination,
  );
  Future<void> balances(int a, int b) async {
    final rows = await engine.accounts();
    expect(
      rows.singleWhere((r) => r.account.id == source).balance.minorUnits,
      BigInt.from(a),
    );
    expect(
      rows.singleWhere((r) => r.account.id == destination).balance.minorUnits,
      BigInt.from(b),
    );
  }

  setUp(() async {
    work = root.createTempSync('case-');
    vault = MemoryVault();
    stop = null;
    engine = engineAt(
      work,
      vault,
      schemaVersion: 8,
      draftCheckpoint: (p) {
        if (p == stop) throw StateError('injected');
      },
    );
    recovery = await setup(engine);
    final a = account(engine), b = account(engine, name: '銀行');
    source = a.id;
    destination = b.id;
    await engine.createAccount(a, opening(a));
    await engine.createAccount(b, opening(b));
  });
  tearDown(() async {
    await engine.lock();
    deleteSynthetic(work, root);
  });
  test('partial transfer restarts unchanged, invalid principal/fee/destination never posts', () async {
    final d = await engine.saveEntryDraft(fields(amount: '12+', fee: '.'));
    await engine.lock();
    engine = engineAt(work, vault, schemaVersion: 8);
    await engine.unlock(password);
    expect((await engine.entryDraft())!.encode(), d.encode());
    for (final f in [
      fields(amount: '0'),
      fields(amount: '-1'),
      fields(fee: '-1'),
      fields(to: source),
      fields(to: PublicId.generate()),
      fields(amount: '92233720368547758.07', fee: '1'),
    ]) {
      await engine.saveEntryDraft(f);
      await expectLater(engine.submitEntryDraft(), throwsA(anything));
      await balances(10000, 10000);
      expect((await engine.entryDraft())!.submission, isNull);
    }
    expect(await engine.entries(), hasLength(2));
  });
  for (final point in ['draft-prepared', 'draft-committed']) {
    test(
      'transfer survives $point and replay affects both accounts only once',
      () async {
        final d = await engine.saveEntryDraft(fields());
        stop = point;
        await expectLater(engine.submitEntryDraft(), throwsStateError);
        await expectLater(
          engine.saveEntryDraft(fields(amount: '21')),
          throwsA(isA<DraftNeedsResolution>()),
        );
        await engine.lock();
        engine = engineAt(work, vault, schemaVersion: 8);
        await engine.unlock(password);
        final saved = await engine.entryDraft();
        if (point == 'draft-prepared') {
          expect(saved!.id, d.id);
          await balances(10000, 10000);
          await engine.submitEntryDraft();
        } else {
          expect(saved, isNull);
        }
        await balances(7875, 12000);
        expect(await engine.entries(), hasLength(3));
        expect(await engine.entryDraft(), isNull);
        final row = (await engine.entries()).first;
        expect(row.id, d.id);
        expect(row.destinationId, destination);
        expect(row.fee!.minorUnits, BigInt.from(125));
      },
    );
  }
  test('transfer backup restores with password and recovery independently after all original storage and keys are deleted', () async {
    await engine.saveEntryDraft(fields());
    await engine.submitEntryDraft();
    final expected = await engine.exportBackup();
    final bytes = await EnvelopeCodec().openWithPassword(expected, password);
    final bad = jsonDecode(expected) as Map;
    bad['unknown'] = true;
    await expectLater(
      engine.importBackup(jsonEncode(bad), password, recovery: false),
      throwsA(anything),
    );
    await balances(7875, 12000);
    await engine.lock();
    deleteSynthetic(work, root);
    vault.values.clear();
    work = root.createTempSync('restore-');
    for (final useRecovery in [false, true]) {
      final target = Directory('${work.path}/$useRecovery');
      final newVault = MemoryVault();
      engine = engineAt(target, newVault, schemaVersion: 8);
      await setup(engine);
      await engine.importBackup(
        expected,
        useRecovery ? recovery : password,
        recovery: useRecovery,
      );
      await balances(7875, 12000);
      final exported = await engine.exportBackup();
      expect(await EnvelopeCodec().openWithPassword(exported, password), bytes);
      await engine.lock();
      engine = engineAt(target, newVault, schemaVersion: 8);
      await engine.unlock(password);
      await balances(7875, 12000);
      await engine.lock();
    }
  });
  test('schema 7 draft blocks upgrade, then explicit upgrade preserves ledger and old reader fails closed', () async {
    await engine.lock();
    final legacyRoot = Directory('${work.path}/legacy');
    final legacyVault = MemoryVault();
    var legacy = engineAt(legacyRoot, legacyVault, schemaVersion: 7);
    await setup(legacy);
    final a = account(legacy);
    await legacy.createAccount(a, opening(a));
    await legacy.saveEntryDraft(
      EntryFields(income: false, amount: '', date: '', accountId: a.id),
    );
    await legacy.lock();
    var modern = engineAt(legacyRoot, legacyVault, schemaVersion: 8);
    await expectLater(
      modern.upgrade(password),
      throwsA(isA<DraftNeedsResolution>()),
    );
    await modern.lock();
    await legacy.unlock(password);
    await legacy.discardEntryDraft();
    await legacy.lock();
    await expectLater(
      modern.unlock(password),
      throwsA(isA<PreviewUpgradeRequired>()),
    );
    await modern.upgrade(password);
    expect(
      (await modern.accounts()).single.balance.minorUnits,
      BigInt.from(10000),
    );
    await modern.lock();
    await expectLater(legacy.unlock(password), throwsA(anything));
    await legacy.lock();
    modern = engineAt(legacyRoot, legacyVault, schemaVersion: 8);
    await modern.unlock(password);
    expect(await modern.entries(), hasLength(1));
    await modern.lock();
  });
}
