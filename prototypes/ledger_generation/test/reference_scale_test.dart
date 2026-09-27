import 'dart:convert';
import 'dart:io';

import 'package:categories/categories.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:ledger_generation_probe/ledger_store.dart';
import 'package:test/test.dart';

import 'support/reference_fixture.dart';

void main() {
  test('upgraded session retains 5000 events and allocations at full category history capacity', () async {
    final root = Directory('.dart_tool/reference-scale-tests')
      ..createSync(recursive: true);
    final f = ReferenceFixture(root.createTempSync('case-'));
    final timer = Stopwatch()..start();
    try {
      await f.initialize();
      await f.upgrade();
      final upgradeMs = timer.elapsedMilliseconds;
      var expectedUnits = BigInt.from(12000);
      late Posting last;
      final first = f.expense();
      await f.store().withSession((s) async {
        // Two existing events: opening + legacy unallocated income.
        for (var i = 2; i < LedgerSession.maxEvents; i++) {
          last = i == 2 ? first : (i.isEven ? f.expense() : f.income());
          expect((await s.post(last)).replayed, isFalse);
          expect((await s.post(last)).replayed, isTrue);
          expectedUnits += BigInt.from(i.isEven ? -1000 : 2000);
        }
        for (var i = 3; i < LedgerSession.maxCategories; i++) {
          await s.createCategory(
            f.operation(),
            PublicId.generate(),
            '分類 $i',
            CategoryKind.expense,
          );
        }
        // Fill history, then merge/archive after all recorded selections.
        for (
          var i = 0;
          i <
              LedgerSession.maxCategoryChanges -
                  LedgerSession.maxCategories -
                  2;
          i++
        ) {
          await s.renameCategory(f.operation(), f.food, i + 1, '餐飲 $i');
        }
        await s.mergeCategory(
          f.operation(),
          sourceId: f.food,
          expectedSourceVersion: 767,
          targetId: f.travel,
          expectedTargetVersion: 1,
        );
        await s.archiveCategory(f.operation(), f.travel, 1, archived: true);
        expect((await s.post(first)).replayed, isTrue);
        await expectLater(s.post(f.income()), throwsA(isA<PreviewCapacity>()));
        await expectLater(
          s.renameCategory(f.operation(), f.salary, 1, '超額'),
          throwsA(isA<PreviewCapacity>()),
        );
      });
      final writesMs = timer.elapsedMilliseconds - upgradeMs;
      final snapshot = await f.store().snapshot();
      expect(
        validateSessionCapacity(snapshot, categoryReferences: true),
        snapshot,
      );
      expect(referenceTables(snapshot)['allocations'], hasLength(7497));
      expect(
        await f.store().balance(f.reference),
        Money(f.account.currency, expectedUnits),
      );
      final backup = await f.store().backup(
        referencePassword,
        recoveryKey: f.credential.recoveryKey,
      );
      for (final recovery in [false, true]) {
        final target = f.target('restore-$recovery');
        await target.restore(
          backup.envelope,
          newOperation(),
          password: recovery ? null : referencePassword,
          recoveryKey: recovery ? f.credential.recoveryKey : null,
        );
        expect(await target.snapshot(), snapshot);
        expect(
          await target.balance(f.reference),
          Money(f.account.currency, expectedUnits),
        );
        await target.withSession((s) async {
          expect((await s.post(first)).replayed, isTrue);
          expect((await s.post(last)).replayed, isTrue);
          expect(await s.allocations(f.workspace, first.id), hasLength(2));
          expect(
            (await s.categories(f.workspace)).resolve(f.food).archived,
            isTrue,
          );
          await expectLater(
            s.post(f.income()),
            throwsA(isA<PreviewCapacity>()),
          );
        });
        expect(await target.snapshot(), snapshot);
      }
      File('.dart_tool/reference-session-scale-result.json').writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          'recordedUtc': DateTime.now().toUtc().toIso8601String(),
          'platform': Platform.operatingSystemVersion,
          'dart': Platform.version,
          'events': 5000,
          'newPostings': 4998,
          'postingRetries': 4998,
          'allocations': 7497,
          'categories': 256,
          'categoryChanges': 1024,
          'snapshotBytes': snapshot.length,
          'expectedBalanceMinor': expectedUnits.toString(),
          'upgradeAndSetupMs': upgradeMs,
          'writesMs': writesMs,
          'totalMs': timer.elapsedMilliseconds,
          'bothRestoreRoutesVerified': true,
          'fullDataEquality': true,
          'replayAfterMergeArchive': true,
          'capacityGuardPreserved': true,
          'deviceTested': false,
        }),
        flush: true,
      );
    } finally {
      removeReferenceFixture(root, f.directory);
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
