import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:backup_envelope_probe/envelope.dart';
import 'package:expense_preview/preview_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  final root = Directory('.dart_tool/engine-tests')
    ..createSync(recursive: true);
  late Directory work;
  late MemoryVault vault;
  late PreviewEngine engine;
  setUp(() {
    work = root.createTempSync('case-');
    vault = MemoryVault();
    engine = engineAt(work, vault);
  });
  tearDown(() async {
    await engine.lock();
    if (!work.absolute.path.startsWith(
      '${root.absolute.path}${Platform.pathSeparator}',
    )) {
      throw StateError('unsafe cleanup');
    }
    work.deleteSync(recursive: true);
  });
  test('restoring an empty backup uses the same workspace before and after reopening', () async {
    await setup(engine);
    final initial = engine.workspace;
    final emptyBackup = await engine.exportBackup();
    await engine.lock();
    final source = engineAt(Directory('${work.path}/foreign'), MemoryVault());
    try {
      await setup(source);
      final a = account(source);
      await source.createAccount(a, opening(a));
      final foreignBackup = await source.exportBackup();
      await source.lock();
      await engine.unlock(password);
      await engine.importBackup(foreignBackup, password, recovery: false);
      expect(engine.workspace, a.workspace);
      await engine.importBackup(emptyBackup, password, recovery: false);
      expect(engine.workspace, initial);
      expect(await engine.accounts(), isEmpty);
      await engine.lock();
      await engine.unlock(password);
      expect(engine.workspace, initial);
    } finally {
      await source.lock();
    }
  });
  test('published profile never recreates a missing ledger or overwrites retained keys', () async {
    await setup(engine);
    final a = account(engine);
    await engine.createAccount(a, opening(a));
    await engine.lock();
    final keys = Map.of(vault.values);
    final retained = Directory('${work.path}/ledger')
        .renameSync('${work.path}/retained-ledger');
    await expectLater(engine.unlock(password), throwsA(isA<PreviewInvalid>()));
    expect(Directory('${work.path}/ledger').existsSync(), isFalse);
    expect(vault.values, keys);
    retained.renameSync('${work.path}/ledger');
    await engine.unlock(password);
    expect(
      (await engine.accounts()).single.balance.minorUnits,
      BigInt.from(10000),
    );
  });
  test('confirmed pending profile can initialize only before its first publication', () async {
    final draft = await engine.prepareSetup(password);
    final info = jsonDecode(
      utf8.decode(
        await EnvelopeCodec().openWithPassword(draft.envelope, password),
      ),
    ) as Map;
    vault.values['recovery_${info['identity']}'] = draft.recoveryKey;
    File('${work.path}/profile.pending')
        .writeAsStringSync(draft.envelope, flush: true);
    expect(await engine.hasProfile(), isTrue);
    await engine.unlock(password);
    expect(await engine.accounts(), isEmpty);
    expect(File('${work.path}/profile.pending').existsSync(), isFalse);
    expect(File('${work.path}/profile.envelope').existsSync(), isTrue);
  });
  test('import row-size limits preserve backup headroom despite valid JSON whitespace or metadata', () async {
    await setup(engine);
    final a = account(engine);
    await engine.createAccount(a, opening(a));
    final original = await EnvelopeCodec().openWithPassword(
      await engine.exportBackup(),
      password,
    );
    for (final field in ['source_context', 'input', 'payload']) {
      final copy = jsonDecode(utf8.decode(original)) as Map;
      final table = field == 'source_context'
          ? 'events'
          : field == 'input'
          ? 'receipts'
          : 'accounts';
      final row = copy['tables'][table][0] as Map;
      row[field] = List.filled(5000, ' ').join() + (row[field] as String);
      expect(
        () => validatePreviewSnapshot(utf8.encode(jsonEncode(copy))),
        throwsA(isA<PreviewInvalid>()),
      );
    }
    expect(
      (await engine.accounts()).single.balance.minorUnits,
      BigInt.from(10000),
    );
  });
  test(
    'verified safety copy can be exported and tampering is not returned',
    () async {
      final key = await setup(engine);
      final a = account(engine);
      await engine.createAccount(a, opening(a));
      final backup = await engine.exportBackup();
      await engine.post(income(a));
      final before = await engine.exportBackup();
      await engine.importBackup(backup, password, recovery: false);
      expect(await engine.hasSafetyCopy(), isTrue);
      final safety = await engine.exportPreviousBackup();
      expect(
        await EnvelopeCodec().openWithRecovery(safety, key),
        await EnvelopeCodec().openWithPassword(before, password),
      );
      final saved = work.listSync().whereType<File>().singleWhere(
        (f) => f.path.contains('before-restore'),
      );
      saved.writeAsStringSync('corrupt', flush: true);
      await expectLater(
        engine.exportPreviousBackup(),
        throwsA(isA<BackupException>()),
      );
      expect(
        (await engine.accounts()).single.balance.minorUnits,
        BigInt.from(10000),
      );
    },
  );
  test(
    'repeated lock waits for accepted posting and never silently duplicates it',
    () async {
      await setup(engine);
      final a = account(engine);
      await engine.createAccount(a, opening(a));
      final p = income(a);
      final posting = expectLater(
        engine.post(p),
        throwsA(isA<PreviewLocked>()),
      );
      final first = engine.lock();
      final second = engine.lock();
      await Future.wait([first, second, posting]);
      await engine.unlock(password);
      await engine.post(p);
      expect(
        (await engine.accounts()).single.balance.minorUnits,
        BigInt.from(10700),
      );
    },
  );
  test(
    'locking during import authentication leaves current ledger unchanged',
    () async {
      await setup(engine);
      final a = account(engine);
      await engine.createAccount(a, opening(a));
      final backup = await engine.exportBackup();
      await engine.post(income(a));
      final importing = expectLater(
        engine.importBackup(backup, password, recovery: false),
        throwsA(isA<PreviewLocked>()),
      );
      await engine.lock();
      await importing;
      await engine.unlock(password);
      expect(
        (await engine.accounts()).single.balance.minorUnits,
        BigInt.from(10700),
      );
    },
  );
  test(
    'setup requires saved recovery and never writes an unconfirmed draft',
    () async {
      final draft = await engine.prepareSetup(password);
      await expectLater(
        engine.finishSetup(draft, password, savedRecovery: false),
        throwsA(isA<PreviewInvalid>()),
      );
      expect(await engine.hasProfile(), isFalse);
      expect(vault.values, isEmpty);
      await engine.finishSetup(draft, password, savedRecovery: true);
      expect(engine.isUnlocked, isTrue);
      expect(await engine.accounts(), isEmpty);
      expect(
        File('${work.path}/profile.envelope').readAsStringSync(),
        isNot(contains(password)),
      );
      await expectLater(
        engine.prepareSetup(password),
        throwsA(isA<PreviewInvalid>()),
      );
    },
  );
  test('lock blocks all business operations and new engine reopens financial state', () async {
    await setup(engine);
    final a = account(engine);
    await engine.createAccount(a, opening(a));
    final p = income(a);
    await engine.post(p);
    await engine.post(p);
    expect(
      (await engine.accounts()).single.balance.minorUnits,
      BigInt.from(10700),
    );
    await engine.lock();
    await expectLater(engine.accounts(), throwsA(isA<PreviewLocked>()));
    await expectLater(engine.entries(), throwsA(isA<PreviewLocked>()));
    await expectLater(engine.post(p), throwsA(isA<PreviewLocked>()));
    await expectLater(engine.exportBackup(), throwsA(isA<PreviewLocked>()));
    engine = engineAt(work, vault);
    await expectLater(
      engine.unlock('wrong-password'),
      throwsA(isA<BackupException>()),
    );
    expect(engine.isUnlocked, isFalse);
    await engine.unlock(password);
    expect(
      (await engine.accounts()).single.balance.minorUnits,
      BigInt.from(10700),
    );
  });
  test('background lock during slow unlock cannot reopen session', () async {
    await setup(engine);
    await engine.lock();
    final entered = Completer<void>();
    final release = Completer<void>();
    vault.beforeRead = (name) async {
      if (name.startsWith('recovery_')) {
        entered.complete();
        await release.future;
      }
    };
    final unlocking = engine.unlock(password);
    final failure = expectLater(unlocking, throwsA(isA<PreviewLocked>()));
    await entered.future;
    await engine.lock();
    release.complete();
    await failure;
    expect(engine.isUnlocked, isFalse);
    vault.beforeRead = null;
    await engine.unlock(password);
    expect(engine.isUnlocked, isTrue);
  });
  test(
    'missing or altered secure recovery fails without replacement',
    () async {
      await setup(engine);
      await engine.lock();
      final name = vault.values.keys.singleWhere(
        (k) => k.startsWith('recovery_'),
      );
      final prior = vault.values.remove(name);
      await expectLater(
        engine.unlock(password),
        throwsA(isA<PreviewInvalid>()),
      );
      expect(vault.values.containsKey(name), isFalse);
      vault.values[name] = 'corrupt';
      await expectLater(
        engine.unlock(password),
        throwsA(isA<BackupException>()),
      );
      expect(vault.values[name], 'corrupt');
      vault.values[name] = prior!;
      await engine.unlock(password);
    },
  );
  test('known pending profile resumes after authentication, unknown does not reset', () async {
    await setup(engine);
    await engine.lock();
    File('${work.path}/profile.envelope')
        .renameSync('${work.path}/profile.pending');
    expect(await engine.hasProfile(), isTrue);
    await expectLater(
      engine.unlock('wrong-password'),
      throwsA(isA<BackupException>()),
    );
    expect(File('${work.path}/profile.pending').existsSync(), isTrue);
    await engine.unlock(password);
    expect(File('${work.path}/profile.envelope').existsSync(), isTrue);
    await engine.lock();
    File('${work.path}/profile.envelope').deleteSync();
    await expectLater(engine.hasProfile(), throwsA(isA<PreviewInvalid>()));
  });
  test(
    'vault failure cannot publish a profile or initialize a ledger',
    () async {
      final draft = await engine.prepareSetup(password);
      vault.failWrites = true;
      await expectLater(
        engine.finishSetup(draft, password, savedRecovery: true),
        throwsStateError,
      );
      expect(await engine.hasProfile(), isFalse);
      expect(Directory('${work.path}/ledger').existsSync(), isFalse);
      vault.failWrites = false;
      await engine.finishSetup(draft, password, savedRecovery: true);
    },
  );
  for (final recovery in [false, true]) {
    test(
      'clean ${recovery ? 'recovery' : 'password'} import preserves values and receipts; new exports retain local credentials',
      () async {
        final originalKey = await setup(engine);
        final a = account(engine);
        await engine.createAccount(a, opening(a));
        final p = income(a);
        await engine.post(p);
        final backup = await engine.exportBackup();
        await engine.lock();
        final target = Directory('${work.path}/target');
        final targetVault = MemoryVault();
        final fresh = engineAt(target, targetVault);
        try {
          final newKey = await setup(fresh);
          await fresh.importBackup(
            backup,
            recovery ? originalKey : password,
            recovery: recovery,
          );
          expect(fresh.workspace, a.workspace);
          await fresh.post(p);
          expect(
            (await fresh.accounts()).single.balance.minorUnits,
            BigInt.from(10700),
          );
          final next = await fresh.exportBackup();
          final restored = await EnvelopeCodec().openWithRecovery(next, newKey);
          expect(
            restored,
            await EnvelopeCodec().openWithPassword(backup, password),
          );
          await expectLater(
            EnvelopeCodec().openWithRecovery(next, originalKey),
            throwsA(isA<BackupException>()),
          );
          expect(
            target.listSync().whereType<File>().where(
              (f) => f.path.contains('before-restore'),
            ),
            hasLength(1),
          );
        } finally {
          await fresh.lock();
        }
      },
    );
  }
  test('incorrect password and authenticated invalid finances leave active data intact', () async {
    await setup(engine);
    final a = account(engine);
    await engine.createAccount(a, opening(a));
    final backup = await engine.exportBackup();
    await expectLater(
      engine.importBackup(backup, 'incorrect-password', recovery: false),
      throwsA(isA<BackupException>()),
    );
    final parsed = jsonDecode(
      utf8.decode(await EnvelopeCodec().openWithPassword(backup, password)),
    ) as Map;
    parsed['tables']['events'][0]['income'] = '99';
    final invalid = await EnvelopeCodec().create(
      utf8.encode(jsonEncode(parsed)),
      password: password,
    );
    await expectLater(
      engine.importBackup(invalid.envelope, password, recovery: false),
      throwsA(anything),
    );
    expect(
      (await engine.accounts()).single.balance.minorUnits,
      BigInt.from(10000),
    );
    await engine.post(income(a));
    expect(
      (await engine.accounts()).single.balance.minorUnits,
      BigInt.from(10700),
    );
  });
  test(
    'preview rejects authenticated unsupported transfers before replacement',
    () async {
      await setup(engine);
      final a = account(engine);
      await engine.createAccount(a, opening(a));
      final backup = await engine.exportBackup();
      final parsed = jsonDecode(
        utf8.decode(await EnvelopeCodec().openWithPassword(backup, password)),
      ) as Map;
      parsed['tables']['events'][0]['kind'] = 'transfer';
      final invalid = await EnvelopeCodec().create(
        utf8.encode(jsonEncode(parsed)),
        password: password,
      );
      await expectLater(
        engine.importBackup(invalid.envelope, password, recovery: false),
        throwsA(isA<PreviewInvalid>()),
      );
      expect(
        (await engine.accounts()).single.balance.minorUnits,
        BigInt.from(10000),
      );
      expect(
        work.listSync().whereType<File>().where(
          (f) => f.path.contains('before-restore'),
        ),
        isEmpty,
      );
    },
  );
}
