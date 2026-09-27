import 'dart:convert';
import 'dart:io';

import 'package:encrypted_storage_probe/encrypted_database.dart';
import 'package:backup_envelope_probe/envelope.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:modular_persistence_probe/categories_adapter.dart';
import 'package:modular_persistence_probe/storage_binding.dart';
import 'package:validated_restore_probe/snapshot.dart';

/// Synthetic metadata workload, with final expectations built independently
/// from the commands and no device or real financial input.
Future<void> main() async {
  final root = Directory('.dart_tool/category-scale')
    ..createSync(recursive: true);
  final work = root.createTempSync('run-');
  final ws = WorkspaceId(PublicId.generate());
  final ids = List.generate(256, (_) => PublicId.generate());
  StorageBinding binding() => StorageBinding(
    PublicId.generate(),
    PublicId.generate(),
    OperationId(PublicId.generate()),
    'd' * 64,
  );
  final codec = SnapshotCodec(categoryAware: true);
  final key = StorageKey.random(), identity = binding();
  final db = openEncrypted(
    File('${work.path}/source'),
    key,
    storageBinding: identity,
    categoryAware: true,
  );
  final adapter = CategoriesAdapter(db);
  final operations = <({OperationKey key, CategoryMutation change})>[];
  Future<void> run(List<Object?> input) async {
    final operation = OperationKey(ws, OperationId(PublicId.generate()));
    final change = CategoryMutation.fromInput(input);
    final result = await adapter.mutate(operation, change);
    if (result.replayed) throw StateError('Unexpected replay');
    operations.add((key: operation, change: change));
  }

  final timings = <String, int>{};
  final watch = Stopwatch()..start();
  try {
    for (var i = 0; i < ids.length; i++) {
      await run([
        'category-v1',
        'create',
        ids[i].value,
        '原分類$i',
        'expense',
        i < 16 ? null : ids[(i - 16) % 16].value,
      ]);
    }
    for (var i = 0; i < ids.length; i++) {
      await run(['category-v1', 'rename', ids[i].value, 1, '分類$i']);
    }
    for (var i = 16; i < ids.length; i++) {
      await run([
        'category-v1',
        'move',
        ids[i].value,
        2,
        ids[(i - 16 + 1) % 16].value,
      ]);
    }
    for (var i = 16; i < ids.length; i++) {
      await run(['category-v1', 'archive', ids[i].value, 3, true]);
    }
    for (var i = 0; i < 16; i++) {
      await run(['category-v1', 'archive', ids[i].value, 2, true]);
    }
    for (var i = 0; i < 16; i++) {
      await run(['category-v1', 'archive', ids[i].value, 3, false]);
    }
    timings['writeMs'] = watch.elapsedMilliseconds;
    if (operations.length != 1024)
      throw StateError('Unexpected operation count');
    watch.reset();
    for (final operation in operations.reversed) {
      if (!(await adapter.mutate(operation.key, operation.change)).replayed)
        throw StateError('Duplicate mutation');
    }
    timings['replayMs'] = watch.elapsedMilliseconds;
    final catalog = await adapter.read(ws);
    for (var i = 0; i < ids.length; i++) {
      final category = catalog.get(ids[i]);
      if (category.name != '分類$i' ||
          category.version != 4 ||
          category.archived != (i >= 16) ||
          category.parentId != (i < 16 ? null : ids[(i - 16 + 1) % 16]) ||
          category.replacementId != null) {
        throw StateError('Independent expected state mismatch');
      }
    }
    watch.reset();
    final bytes = await codec.capture(db);
    timings['captureAndHistoryValidationMs'] = watch.elapsedMilliseconds;
    final backup = await EnvelopeCodec().create(
      bytes,
      password: 'category-scale-fixture-password',
    );
    await db.close();
    for (final recovery in [false, true]) {
      watch.reset();
      final recovered = recovery
          ? await EnvelopeCodec().openWithRecovery(
              backup.envelope,
              backup.recoveryKey,
            )
          : await EnvelopeCodec().openWithPassword(
              backup.envelope,
              'category-scale-fixture-password',
            );
      final target = File('${work.path}/${recovery ? 'recovery' : 'password'}');
      final targetKey = StorageKey.random(), targetBinding = binding();
      await codec.stage(
        recovered,
        target,
        openDatabase: (f) => openEncrypted(
          f,
          targetKey,
          storageBinding: targetBinding,
          categoryAware: true,
        ),
      );
      final restored = openEncrypted(
        target,
        targetKey,
        storageBinding: targetBinding,
        categoryAware: true,
      );
      try {
        final restoredBytes = await codec.capture(restored);
        if (base64Encode(restoredBytes) != base64Encode(bytes))
          throw StateError('Restored authority differs');
        if (!(await CategoriesAdapter(
          restored,
        ).mutate(operations.first.key, operations.first.change)).replayed)
          throw StateError('Missing restored receipt');
      } finally {
        await restored.close();
      }
      timings[recovery ? 'recoveryRestoreMs' : 'passwordRestoreMs'] =
          watch.elapsedMilliseconds;
    }
    final report = {
      'status': 'passed',
      'completedAtUtc': DateTime.now().toUtc().toIso8601String(),
      'runtime': Platform.version,
      'os': Platform.operatingSystemVersion,
      'categories': 256,
      'metadataChanges': operations.length,
      'originalReplays': operations.length,
      'restoredReplays': 2,
      'snapshotBytes': bytes.length,
      'envelopeBytes': utf8.encode(backup.envelope).length,
      'timings': timings,
      'scope': 'SQLCipher schema 4 host metadata only; separate directories in one process; no Android or publication coordinator',
    };
    final json = const JsonEncoder.withIndent('  ').convert(report);
    File('.dart_tool/category-scale-report.json')
        .writeAsStringSync('$json\n', flush: true);
    stdout.writeln(json);
    if (!work.resolveSymbolicLinksSync().startsWith(
      '${root.resolveSymbolicLinksSync()}${Platform.pathSeparator}',
    ))
      throw StateError('Unsafe cleanup');
    work.deleteSync(recursive: true);
  } finally {
    await db.close();
  }
}
