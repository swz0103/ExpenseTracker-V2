import 'dart:convert';
import 'dart:io';

import 'package:foundation_values/foundation_values.dart';
import 'package:modular_persistence_probe/database.dart';
import 'package:modular_persistence_probe/fixture_allocation.dart';
import 'package:modular_persistence_probe/recurring_revisions_adapter.dart';
import 'package:modular_persistence_probe/storage_binding.dart';
import 'package:recurring_transactions/recurring_transactions.dart';
import 'package:test/test.dart';
import 'package:validated_restore_probe/snapshot.dart';

void main() {
  final root = Directory('.dart_tool/recurring-snapshot-tests')
    ..createSync(recursive: true);
  late Directory work;
  late ProbeDatabase source;
  late AllocationFixture fixture;
  late PublicId templateId;
  final codec = SnapshotCodec(
    generationAware: true,
    correctionsAware: true,
    tombstonesAware: true,
    budgetsAware: true,
    recurringAware: true,
  );

  ProbeDatabase database(
    File file,
    StorageBinding binding, {
    bool recurring = true,
  }) => ProbeDatabase(
    file,
    storageBinding: binding,
    categoryAware: true,
    correctionsAware: true,
    tombstonesAware: true,
    budgetsAware: true,
    recurringAware: recurring,
  );

  RecurringTemplate template(int version, String amount) => RecurringTemplate(
    id: templateId,
    workspace: fixture.ws,
    accountId: fixture.account.id,
    label: 'Monthly rent',
    amount: Money.parse(fixture.currency, amount),
    firstDate: BusinessDate(2026, 9, 30),
    unit: RecurrenceUnit.month,
    every: 1,
    version: version,
  );

  setUp(() async {
    work = root.createTempSync('case-');
    source = database(File('${work.path}/source.db'), allocationBinding());
    fixture = AllocationFixture(source);
    templateId = PublicId.generate();
    await fixture.initialize();
  });
  tearDown(() async {
    await source.close();
    work.deleteSync(recursive: true);
  });

  test(
    'recurring revisions survive portable stage with new local binding',
    () async {
      await appendRecurringRevision(
        source,
        template(1, '-100'),
        OperationId(PublicId.generate()),
        DateTime.utc(2026, 9, 29),
      );
      await appendRecurringRevision(
        source,
        template(2, '-120'),
        OperationId(PublicId.generate()),
        DateTime.utc(2026, 9, 30),
      );
      final bytes = await codec.capture(source);
      final targetFile = File('${work.path}/target.db');
      final binding = allocationBinding();
      await codec.stage(
        bytes,
        targetFile,
        openDatabase: (file) => database(file, binding),
      );
      final target = database(targetFile, binding);
      try {
        expect((await recurringHistory(target, fixture.ws)).length, 2);
        expect(
          (await currentRecurringTemplates(
            target,
            fixture.ws,
          )).single.amount.majorText,
          '-120.00',
        );
        expect(await codec.capture(target), bytes);
      } finally {
        await target.close();
      }
    },
  );

  test(
    'corrupt recurring authority is rejected before export or stage',
    () async {
      await appendRecurringRevision(
        source,
        template(1, '-100'),
        OperationId(PublicId.generate()),
        DateTime.utc(2026, 9, 29),
      );
      final bytes = await codec.capture(source);
      final tampered = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final tables = tampered['tables'] as Map<String, dynamic>;
      (tables['recurring_revisions'] as List).single['payload'] = '{}';
      await expectLater(
        codec.stage(
          utf8.encode(jsonEncode(tampered)),
          File('${work.path}/tampered.db'),
          openDatabase: (file) => database(file, allocationBinding()),
        ),
        throwsA(isA<InvalidSnapshot>()),
      );
      await source.customStatement('UPDATE recurring_revisions SET payload=?', [
        '{}',
      ]);
      await expectLater(codec.capture(source), throwsA(isA<InvalidSnapshot>()));
    },
  );

  test(
    'schema 15 snapshot stages into schema 16 with empty templates',
    () async {
      final oldFile = File('${work.path}/old.db');
      final old = database(oldFile, allocationBinding(), recurring: false);
      final oldFixture = AllocationFixture(old);
      try {
        await oldFixture.initialize();
        final previous = SnapshotCodec(
          generationAware: true,
          correctionsAware: true,
          tombstonesAware: true,
          budgetsAware: true,
        );
        final bytes = await previous.capture(old);
        final targetFile = File('${work.path}/upgraded.db');
        final binding = allocationBinding();
        await codec.stage(
          bytes,
          targetFile,
          openDatabase: (file) => database(file, binding),
        );
        final target = database(targetFile, binding);
        try {
          expect(await recurringHistory(target, oldFixture.ws), isEmpty);
          expect(target.schemaVersion, 16);
          expect(await codec.capture(target), codec.canonicalize(bytes));
        } finally {
          await target.close();
        }
      } finally {
        await old.close();
      }
    },
  );
}
