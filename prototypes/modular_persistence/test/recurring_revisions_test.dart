import 'dart:io';

import 'package:foundation_values/foundation_values.dart';
import 'package:modular_persistence_probe/database.dart';
import 'package:modular_persistence_probe/fixture_allocation.dart';
import 'package:modular_persistence_probe/recurring_revisions_adapter.dart';
import 'package:modular_persistence_probe/storage_binding.dart';
import 'package:recurring_transactions/recurring_transactions.dart';
import 'package:test/test.dart';

void main() {
  final root = Directory('.dart_tool/recurring-revisions-tests')
    ..createSync(recursive: true);
  late Directory work;
  late File file;
  late ProbeDatabase db;
  late AllocationFixture fixture;
  late PublicId templateId;
  late StorageBinding binding;
  final when = DateTime.utc(2026, 9, 29, 3);

  ProbeDatabase open(File source) => ProbeDatabase(
    source,
    storageBinding: binding,
    categoryAware: true,
    correctionsAware: true,
    tombstonesAware: true,
    budgetsAware: true,
    recurringAware: true,
  );

  RecurringTemplate plan(int version, String amount, {PublicId? account}) =>
      RecurringTemplate(
        id: templateId,
        workspace: fixture.ws,
        accountId: account ?? fixture.account.id,
        label: 'Monthly rent',
        amount: Money.parse(fixture.currency, amount),
        firstDate: BusinessDate(2026, 9, 30),
        unit: RecurrenceUnit.month,
        every: 1,
        version: version,
      );

  setUp(() async {
    work = root.createTempSync('case-');
    file = File('${work.path}/finance.db');
    binding = allocationBinding();
    db = open(file);
    fixture = AllocationFixture(db);
    templateId = PublicId.generate();
    await fixture.initialize();
  });
  tearDown(() async {
    await db.close();
    work.deleteSync(recursive: true);
  });

  test('append, retry, revision and deletion keep authority', () async {
    expect(db.schemaVersion, 16);
    final create = OperationId(PublicId.generate());
    final update = OperationId(PublicId.generate());
    await appendRecurringRevision(db, plan(1, '-100'), create, when);
    final retry = await appendRecurringRevision(
      db,
      plan(1, '-100'),
      create,
      when.add(const Duration(days: 1)),
    );
    expect(retry.recordedAt, when);
    await appendRecurringRevision(db, plan(2, '-120'), update, when);
    expect(
      (await currentRecurringTemplates(db, fixture.ws)).single.amount.majorText,
      '-120.00',
    );
    await appendRecurringRevision(
      db,
      plan(3, '-120'),
      OperationId(PublicId.generate()),
      when,
      deleted: true,
    );
    expect(await currentRecurringTemplates(db, fixture.ws), isEmpty);
    expect((await recurringHistory(db, fixture.ws)).length, 3);
    await validateRecurringRevisions(db);
  });

  test('conflict, stale edit and changed deletion roll back', () async {
    final create = OperationId(PublicId.generate());
    await appendRecurringRevision(db, plan(1, '-100'), create, when);
    for (final action in [
      () => appendRecurringRevision(db, plan(1, '-101'), create, when),
      () => appendRecurringRevision(
        db,
        plan(3, '-100'),
        OperationId(PublicId.generate()),
        when,
      ),
      () => appendRecurringRevision(
        db,
        plan(2, '-101'),
        OperationId(PublicId.generate()),
        when,
        deleted: true,
      ),
    ]) {
      await expectLater(action(), throwsFormatException);
    }
    expect((await recurringHistory(db, fixture.ws)).length, 1);
  });

  test('unknown account cannot become a stored template', () async {
    await expectLater(
      appendRecurringRevision(
        db,
        plan(1, '-100', account: PublicId.generate()),
        OperationId(PublicId.generate()),
        when,
      ),
      throwsA(isA<Exception>()),
    );
    expect(await recurringHistory(db, fixture.ws), isEmpty);
  });

  test(
    'reopen retains revisions and corrupted payload fails validation',
    () async {
      await appendRecurringRevision(
        db,
        plan(1, '-100'),
        OperationId(PublicId.generate()),
        when,
      );
      await db.close();
      db = open(file);
      expect(
        (await currentRecurringTemplates(
          db,
          fixture.ws,
        )).single.amount.majorText,
        '-100.00',
      );
      await db.customStatement(
        'UPDATE recurring_revisions SET payload=? WHERE workspace=?',
        ['{}', fixture.ws.id.value],
      );
      await expectLater(validateRecurringRevisions(db), throwsFormatException);
    },
  );

  test(
    'reader rejects a valid-looking revision with a missing predecessor',
    () async {
      await appendRecurringRevision(
        db,
        plan(1, '-100'),
        OperationId(PublicId.generate()),
        when,
      );
      await appendRecurringRevision(
        db,
        plan(2, '-110'),
        OperationId(PublicId.generate()),
        when,
      );
      final forged = RecurringTemplateCodec().encode(plan(3, '-110'));
      await db.customStatement(
        'UPDATE recurring_revisions SET version=3,payload=? '
        'WHERE workspace=? AND id=? AND version=2',
        [forged, fixture.ws.id.value, templateId.value],
      );
      await expectLater(
        currentRecurringTemplates(db, fixture.ws),
        throwsFormatException,
      );
    },
  );
}
