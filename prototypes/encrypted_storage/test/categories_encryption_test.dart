import 'dart:convert';
import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:backup_envelope_probe/envelope.dart';
import 'package:categories/categories.dart';
import 'package:encrypted_storage_probe/encrypted_database.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:modular_persistence_probe/categories_adapter.dart';
import 'package:modular_persistence_probe/database.dart';
import 'package:modular_persistence_probe/storage_binding.dart';
import 'package:modular_persistence_probe/workflows.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:validated_restore_probe/snapshot.dart';

void main() {
  final root = Directory('.dart_tool/encrypted-category-tests')
    ..createSync(recursive: true);
  const password = 'category-backup-fixture-password';
  final codec = SnapshotCodec(categoryAware: true);
  final ws = WorkspaceId(PublicId.generate());
  StorageBinding binding() => StorageBinding(
    PublicId.generate(),
    PublicId.generate(),
    OperationId(PublicId.generate()),
    'c' * 64,
  );
  OperationKey op() => OperationKey(ws, OperationId(PublicId.generate()));
  late Directory work;
  setUp(() {
    work = root.createTempSync('case-');
  });
  tearDown(() {
    if (!work.resolveSymbolicLinksSync().startsWith(
      '${root.resolveSymbolicLinksSync()}${Platform.pathSeparator}',
    ))
      throw StateError('Unsafe cleanup');
    work.deleteSync(recursive: true);
  });
  Future<PostingAccount> seed(ProbeDatabase db) async {
    final account = Account.open(
      id: PublicId.generate(),
      workspace: ws,
      name: '加密帳戶',
      kind: AccountKind.cash,
      currency: Currency('TWD', 2),
      openedOn: BusinessDate(2026, 9, 27),
    );
    final ref = PostingAccount(
      id: account.id,
      workspace: ws,
      currency: account.currency,
      expectedVersion: 1,
    );
    await FinancialWorkflows(db).createAccount(
      account,
      Posting.opening(
        id: PublicId.generate(),
        operation: op(),
        date: account.openedOn,
        account: ref,
        amount: Money.parse(account.currency, '123.45'),
      ),
    );
    return ref;
  }

  for (final useRecovery in [false, true]) {
    test(
      'schema 4 encrypted ${useRecovery ? 'recovery' : 'password'} restore uses fresh target keys and preserves receipts',
      () async {
        final source = File('${work.path}/source');
        final sourceBinding = binding();
        final db = openEncrypted(
          source,
          StorageKey.random(),
          storageBinding: sourceBinding,
          categoryAware: true,
        );
        final ref = await seed(db);
        final category = PublicId.generate(), operation = op();
        final create = CategoryMutation.create(
          category,
          'CATEGORY_PRIVATE_MARKER',
          CategoryKind.expense,
        );
        await CategoriesAdapter(db).mutate(operation, create);
        await CategoriesAdapter(db)
            .mutate(op(), CategoryMutation.rename(category, 1, '新分類'));
        final snapshot = await codec.capture(db);
        final backup = await EnvelopeCodec().create(
          snapshot,
          password: password,
        );
        await db.close();
        expect(
          latin1
              .decode(source.readAsBytesSync())
              .contains('CATEGORY_PRIVATE_MARKER'),
          isFalse,
        );
        source.deleteSync();
        final bytes = useRecovery
            ? await EnvelopeCodec().openWithRecovery(
                backup.envelope,
                backup.recoveryKey,
              )
            : await EnvelopeCodec().openWithPassword(backup.envelope, password);
        final target = File('${work.path}/restored'),
            targetKey = StorageKey.random(),
            targetBinding = binding();
        await codec.stage(
          bytes,
          target,
          openDatabase: (f) => openEncrypted(
            f,
            targetKey,
            storageBinding: targetBinding,
            categoryAware: true,
          ),
        );
        var restored = openEncrypted(
          target,
          targetKey,
          storageBinding: targetBinding,
          categoryAware: true,
        );
        expect(await codec.capture(restored), snapshot);
        expect(
          (await FinancialWorkflows(restored).ledger.balance(ref)).minorUnits,
          BigInt.from(12345),
        );
        expect(
          (await CategoriesAdapter(
            restored,
          ).mutate(operation, create)).replayed,
          isTrue,
        );
        await restored.close();
        restored = openEncrypted(
          target,
          targetKey,
          storageBinding: targetBinding,
          categoryAware: true,
        );
        try {
          expect(await codec.capture(restored), snapshot);
          expect(
            (await CategoriesAdapter(restored).read(ws)).get(category).name,
            '新分類',
          );
        } finally {
          await restored.close();
        }
      },
    );
  }

  test('opening schema 3 as category aware refuses in-place DDL and preserves encrypted source', () async {
    final source = File('${work.path}/source'),
        key = StorageKey.random(),
        identity = binding();
    var db = openEncrypted(source, key, storageBinding: identity);
    final ref = await seed(db);
    final before = await SnapshotCodec(generationAware: true).capture(db);
    await db.close();
    db = openEncrypted(
      source,
      key,
      storageBinding: identity,
      categoryAware: true,
    );
    try {
      await expectLater(
        db.customSelect('SELECT * FROM accounts').get(),
        throwsStateError,
      );
    } finally {
      await db.close();
    }
    final raw = sqlite3.open(source.path);
    configureEncryption(raw, key);
    expect(raw.userVersion, 3);
    expect(
      raw.select("SELECT name FROM sqlite_master WHERE name='categories'"),
      isEmpty,
    );
    raw.close();
    db = openEncrypted(source, key, storageBinding: identity);
    try {
      expect(await SnapshotCodec(generationAware: true).capture(db), before);
      expect(
        (await FinancialWorkflows(db).ledger.balance(ref)).minorUnits,
        BigInt.from(12345),
      );
    } finally {
      await db.close();
    }
  });

  test('encrypted staged upgrade failure keeps old generation and its verified backup usable', () async {
    final source = File('${work.path}/source'),
        key = StorageKey.random(),
        identity = binding();
    var db = openEncrypted(source, key, storageBinding: identity);
    await seed(db);
    final before = await SnapshotCodec(generationAware: true).capture(db);
    final backup = await EnvelopeCodec().create(before, password: password);
    final backupFile = File('${work.path}/safety.envelope');
    await backupFile.writeAsString(backup.envelope, flush: true);
    expect(
      await EnvelopeCodec().openWithPassword(
        await backupFile.readAsString(),
        password,
      ),
      before,
    );
    expect(
      await EnvelopeCodec().openWithRecovery(
        await backupFile.readAsString(),
        backup.recoveryKey,
      ),
      before,
    );
    await db.close();
    await expectLater(
      codec.stage(
        before,
        File('${work.path}/failed-stage'),
        openDatabase: (f) => openEncrypted(
          f,
          StorageKey.random(),
          storageBinding: binding(),
          categoryAware: true,
        ),
        checkpoint: (at) {
          if (at == 'table:categories') throw StateError('injected');
        },
      ),
      throwsStateError,
    );
    db = openEncrypted(source, key, storageBinding: identity);
    try {
      expect(await SnapshotCodec(generationAware: true).capture(db), before);
    } finally {
      await db.close();
    }
    expect(
      await EnvelopeCodec().openWithRecovery(
        await backupFile.readAsString(),
        backup.recoveryKey,
      ),
      before,
    );
  });
}
