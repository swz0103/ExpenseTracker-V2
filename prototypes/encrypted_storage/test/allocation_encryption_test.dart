import 'dart:convert';
import 'dart:io';

import 'package:backup_envelope_probe/envelope.dart';
import 'package:encrypted_storage_probe/encrypted_database.dart';
import 'package:modular_persistence_probe/categories_adapter.dart';
import 'package:modular_persistence_probe/workflows.dart';
import 'package:test/test.dart';
import 'package:validated_restore_probe/snapshot.dart';

import 'package:modular_persistence_probe/fixture_allocation.dart';

void main() {
  final root = Directory('.dart_tool/allocation-encryption-tests')
    ..createSync(recursive: true);
  const password = 'synthetic-allocation-only';
  final codec = SnapshotCodec(categoryReferences: true);
  late Directory work;
  setUp(() {
    work = root.createTempSync('case-');
  });
  tearDown(() {
    if (!work.absolute.path.startsWith(
      '${root.absolute.path}${Platform.pathSeparator}',
    ))
      throw StateError('Unsafe cleanup');
    work.deleteSync(recursive: true);
  });
  for (final recovery in [false, true]) {
    test(
      'fresh process restores schema 5 with ${recovery ? 'recovery' : 'password'} and no source database',
      () async {
        final source = File('${work.path}/source.db');
        final db = openEncrypted(
          source,
          StorageKey.random(),
          storageBinding: allocationBinding(),
          categoryReferences: true,
        );
        late List<int> bytes;
        try {
          final fixture = AllocationFixture(db);
          await fixture.initialize();
          await FinancialWorkflows(db).post(fixture.expense());
          await FinancialWorkflows(db).post(fixture.income());
          await CategoriesAdapter(db).mutate(
            fixture.operation(),
            CategoryMutation.rename(
              fixture.food,
              1,
              'ALLOCATION_PRIVATE_MARKER',
            ),
          );
          await CategoriesAdapter(db).mutate(
            fixture.operation(),
            CategoryMutation.archive(fixture.food, 2, true),
          );
          bytes = await codec.capture(db);
        } finally {
          await db.close();
        }
        expect(
          latin1
              .decode(source.readAsBytesSync())
              .contains('ALLOCATION_PRIVATE_MARKER'),
          isFalse,
        );
        final backup = await EnvelopeCodec().create(bytes, password: password);
        final envelope = File('${work.path}/backup.envelope')
          ..writeAsStringSync(backup.envelope);
        final credential = File('${work.path}/credential.txt')
          ..writeAsStringSync(recovery ? backup.recoveryKey : password);
        source.deleteSync();
        final target = Directory('${work.path}/target')..createSync();
        final worker = File(
          '.dart_tool/worker/bundle/bin/restore_worker${Platform.isWindows ? '.exe' : ''}',
        );
        final result = await Process.run(worker.absolute.path, [
          'allocation-stage',
          target.absolute.path,
          envelope.absolute.path,
          credential.absolute.path,
          recovery ? 'recovery' : 'password',
          'none',
        ]);
        expect(result.exitCode, 0, reason: result.stderr.toString());
        expect(File('${target.path}/verified.json').readAsBytesSync(), bytes);
        expect(
          latin1
              .decode(File('${target.path}/stage.db').readAsBytesSync())
              .contains('ALLOCATION_PRIVATE_MARKER'),
          isFalse,
        );
      },
    );
  }

  test('encrypted schema 4 stage upgrade preserves source across allocation failure and dual backup readback', () async {
    final source = File('${work.path}/source.db'),
        sourceKey = StorageKey.random(),
        sourceBinding = allocationBinding();
    var db = openEncrypted(
      source,
      sourceKey,
      storageBinding: sourceBinding,
      categoryAware: true,
    );
    late List<int> before;
    try {
      final fixture = AllocationFixture(db);
      await fixture.initialize();
      before = await SnapshotCodec(categoryAware: true).capture(db);
    } finally {
      await db.close();
    }
    final original = source.readAsBytesSync();
    // Direct open is forbidden; only a separately verified stage may advance.
    db = openEncrypted(
      source,
      sourceKey,
      storageBinding: sourceBinding,
      categoryReferences: true,
    );
    try {
      await expectLater(
        db.customSelect('SELECT * FROM events').get(),
        throwsStateError,
      );
    } finally {
      await db.close();
    }
    expect(source.readAsBytesSync(), original);
    final backup = await EnvelopeCodec().create(before, password: password);
    expect(
      await EnvelopeCodec().openWithPassword(backup.envelope, password),
      before,
    );
    expect(
      await EnvelopeCodec().openWithRecovery(
        backup.envelope,
        backup.recoveryKey,
      ),
      before,
    );
    await expectLater(
      codec.stage(
        before,
        File('${work.path}/failed'),
        openDatabase: (f) => openEncrypted(
          f,
          StorageKey.random(),
          storageBinding: allocationBinding(),
          categoryReferences: true,
        ),
        checkpoint: (point) {
          if (point == 'table:allocations') throw StateError('injected');
        },
      ),
      throwsStateError,
    );
    expect(source.readAsBytesSync(), original);
    final target = File('${work.path}/stage'),
        targetKey = StorageKey.random(),
        targetBinding = allocationBinding();
    await codec.stage(
      before,
      target,
      openDatabase: (f) => openEncrypted(
        f,
        targetKey,
        storageBinding: targetBinding,
        categoryReferences: true,
      ),
    );
    db = openEncrypted(
      target,
      targetKey,
      storageBinding: targetBinding,
      categoryReferences: true,
    );
    try {
      expect(await codec.capture(db), codec.canonicalize(before));
    } finally {
      await db.close();
    }
  });
}
