import 'dart:convert';
import 'dart:io';

import 'package:backup_envelope_probe/envelope.dart';
import 'package:encrypted_storage_probe/encrypted_database.dart';
import 'package:ledger/ledger.dart';
import 'package:modular_persistence_probe/categories_adapter.dart';
import 'package:modular_persistence_probe/workflows.dart';
import 'package:test/test.dart';
import 'package:validated_restore_probe/snapshot.dart';

import 'package:modular_persistence_probe/fixture_allocation.dart';

void main() {
  test('5000 encrypted events retain 7498 historical allocations through both restore routes', () async {
    final root = Directory('.dart_tool/allocation-scale-tests')
      ..createSync(recursive: true);
    final work = root.createTempSync('case-'), watch = Stopwatch()..start();
    final codec = SnapshotCodec(categoryReferences: true);
    final db = openEncrypted(
      File('${work.path}/source'),
      StorageKey.random(),
      storageBinding: allocationBinding(),
      categoryReferences: true,
    );
    late AllocationFixture fixture;
    late Posting last;
    late List<int> bytes;
    var expectedMinor = BigInt.from(10000);
    late int writesMs;
    try {
      try {
        fixture = AllocationFixture(db);
        await fixture.initialize();
        final workflow = FinancialWorkflows(db);
        for (var i = 1; i < 5000; i++) {
          last = i.isOdd
              ? fixture.income()
              : fixture.expense(
                  allocations: [
                    Allocation(
                      fixture.food,
                      fixture.money('6'),
                      expectedCategoryVersion: 1,
                    ),
                    Allocation(
                      fixture.travel,
                      fixture.money('4'),
                      expectedCategoryVersion: 1,
                    ),
                  ],
                );
          expect((await workflow.post(last)).replayed, isFalse);
          expect((await workflow.post(last)).replayed, isTrue);
          expectedMinor += BigInt.from(i.isOdd ? 2000 : -1000);
        }
        writesMs = watch.elapsedMilliseconds;
        final categories = CategoriesAdapter(db);
        await categories.mutate(
          fixture.operation(),
          CategoryMutation.rename(fixture.food, 1, '舊飲食'),
        );
        await categories.mutate(
          fixture.operation(),
          CategoryMutation.merge(fixture.food, 2, fixture.travel, 1),
        );
        await categories.mutate(
          fixture.operation(),
          CategoryMutation.archive(fixture.travel, 1, true),
        );
        await categories.mutate(
          fixture.operation(),
          CategoryMutation.archive(fixture.salary, 1, true),
        );
        expect(
          (await workflow.ledger.balance(fixture.reference)).minorUnits,
          expectedMinor,
        );
        bytes = await codec.capture(db);
        final tables = (jsonDecode(utf8.decode(bytes)) as Map)['tables'] as Map;
        expect(tables['events'], hasLength(5000));
        expect(tables['allocations'], hasLength(7498));
      } finally {
        await db.close();
      }
      const password = 'synthetic-allocation-scale';
      final backup = await EnvelopeCodec().create(bytes, password: password);
      for (final recovery in [false, true]) {
        final plaintext = recovery
            ? await EnvelopeCodec().openWithRecovery(
                backup.envelope,
                backup.recoveryKey,
              )
            : await EnvelopeCodec().openWithPassword(backup.envelope, password);
        expect(plaintext, bytes);
        final file = File('${work.path}/target-$recovery'),
            key = StorageKey.random(),
            binding = allocationBinding();
        await codec.stage(
          plaintext,
          file,
          openDatabase: (f) => openEncrypted(
            f,
            key,
            storageBinding: binding,
            categoryReferences: true,
          ),
        );
        final restored = openEncrypted(
          file,
          key,
          storageBinding: binding,
          categoryReferences: true,
        );
        try {
          expect(await codec.capture(restored), bytes);
          expect(
            (await FinancialWorkflows(restored).ledger
                    .balance(fixture.reference))
                .minorUnits,
            expectedMinor,
          );
          expect(
            (await FinancialWorkflows(restored).post(last)).replayed,
            isTrue,
          );
          expect(await codec.capture(restored), bytes);
        } finally {
          await restored.close();
        }
      }
      File('.dart_tool/allocation-scale-result.json').writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          'recordedUtc': DateTime.now().toUtc().toIso8601String(),
          'platform': Platform.operatingSystemVersion,
          'dart': Platform.version,
          'events': 5000,
          'newPostings': 4999,
          'postingRetries': 4999,
          'allocations': 7498,
          'categoryChanges': 7,
          'snapshotBytes': bytes.length,
          'expectedBalanceMinor': expectedMinor.toString(),
          'writesMs': writesMs,
          'totalMs': watch.elapsedMilliseconds,
          'fullDataEquality': true,
          'balancePreserved': true,
          'retryAfterArchive': true,
          'bothRestoreRoutesVerified': true,
          'deviceTested': false,
        }),
        flush: true,
      );
    } finally {
      if (!work.absolute.path.startsWith(
        '${root.absolute.path}${Platform.pathSeparator}',
      ))
        throw StateError('Unsafe cleanup');
      work.deleteSync(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 8)));
}
