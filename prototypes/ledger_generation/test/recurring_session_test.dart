import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:ledger_generation_probe/ledger_store.dart';
import 'package:recurring_transactions/recurring_transactions.dart';
import 'package:storage_generation_probe/fixture_catalog_protection.dart';
import 'package:storage_generation_probe/fixture_key_slots.dart';
import 'package:test/test.dart';

void main() {
  final root = Directory('.dart_tool/recurring-session-tests')
    ..createSync(recursive: true);
  late Directory work;
  late FixtureKeySlots keys;
  late WorkspaceId workspace;
  late Account account;
  late PublicId templateId;

  LedgerStore store(String name, FixtureKeySlots slots) => LedgerStore(
    Directory('${work.path}/$name'),
    slots,
    catalogProtection: fixtureCatalogProtection(slots),
    correctionsAware: true,
    tombstonesAware: true,
    budgetsAware: true,
    recurringAware: true,
  );
  OperationId operation() => OperationId(PublicId.generate());
  RecurringTemplate template(int version, String amount) => RecurringTemplate(
    id: templateId,
    workspace: workspace,
    accountId: account.id,
    label: 'Monthly rent',
    amount: Money.parse(account.currency, amount),
    firstDate: BusinessDate(2026, 9, 30),
    unit: RecurrenceUnit.month,
    every: 1,
    version: version,
  );

  setUp(() {
    work = root.createTempSync('case-');
    keys = FixtureKeySlots(Directory('${work.path}/keys'));
    workspace = WorkspaceId(PublicId.generate());
    account = Account.open(
      id: PublicId.generate(),
      workspace: workspace,
      name: 'Cash',
      kind: AccountKind.cash,
      currency: Currency('TWD', 2),
      openedOn: BusinessDate(2026, 1, 1),
    );
    templateId = PublicId.generate();
  });
  tearDown(() {
    final base = root.resolveSymbolicLinksSync();
    final target = work.resolveSymbolicLinksSync();
    if (!target.startsWith('$base${Platform.pathSeparator}')) {
      throw StateError('Unsafe cleanup');
    }
    work.deleteSync(recursive: true);
  });

  test(
    'explicit confirmation posts once and survives both clean restores',
    () async {
      final active = store('active', keys);
      await active.initialize(operation());
      await active.withSession((session) async {
        await session.createAccount(
          account,
          Posting.opening(
            id: PublicId.generate(),
            operation: OperationKey(workspace, operation()),
            date: account.openedOn,
            account: PostingAccount(
              id: account.id,
              workspace: workspace,
              currency: account.currency,
              expectedVersion: account.version,
            ),
            amount: Money.parse(account.currency, '1000'),
          ),
        );
        final firstOperation = operation();
        final first = template(1, '-100');
        await session.saveRecurringTemplate(
          first,
          firstOperation,
          DateTime.utc(2026, 9, 29),
        );
        await session.saveRecurringTemplate(
          first,
          firstOperation,
          DateTime.utc(2026, 9, 30),
        );
        expect(await session.recurringTemplates(workspace), hasLength(1));
        final due = await session.recurringDue(
          workspace,
          after: BusinessDate(2026, 9, 29),
          through: BusinessDate(2026, 11, 30),
        );
        expect(due.map((c) => c.dueDate.toString()), [
          '2026-09-30',
          '2026-10-30',
          '2026-11-30',
        ]);
        expect((await session.entries(workspace)).length, 1);
        final eventId = PublicId.generate();
        expect(
          await session.confirmRecurring(
            due.first,
            eventId,
            operation(),
            DateTime.utc(2026, 9, 30),
          ),
          (eventId: eventId, replayed: false),
        );
        expect(
          await session.confirmRecurring(
            due.first,
            PublicId.generate(),
            operation(),
            DateTime.utc(2026, 9, 30),
          ),
          (eventId: eventId, replayed: true),
        );
        expect((await session.entries(workspace)).length, 2);
        expect(
          (await session.recurringDue(
            workspace,
            after: BusinessDate(2026, 9, 29),
            through: BusinessDate(2026, 11, 30),
          )).length,
          2,
        );
        await session.saveRecurringTemplate(
          template(2, '-120'),
          operation(),
          DateTime.utc(2026, 9, 30),
        );
        expect(
          (await session.recurringTemplates(workspace)).single.amount.majorText,
          '-120.00',
        );
        await expectLater(
          session.confirmRecurring(
            due[1],
            PublicId.generate(),
            operation(),
            DateTime.utc(2026, 10, 30),
          ),
          throwsFormatException,
        );
        expect((await session.entries(workspace)).length, 2);
        await expectLater(
          session.recurringDue(
            workspace,
            after: BusinessDate(2026, 9, 29),
            through: BusinessDate(2026, 11, 30),
            maxCandidates: 1,
          ),
          throwsStateError,
        );
        final updatedDue = await session.recurringDue(
          workspace,
          after: BusinessDate(2026, 9, 29),
          through: BusinessDate(2026, 10, 30),
          maxCandidates: 1,
        );
        expect(updatedDue.map((c) => c.dueDate.toString()), ['2026-10-30']);
        await session.confirmRecurring(
          updatedDue.single,
          PublicId.generate(),
          operation(),
          DateTime.utc(2026, 10, 30),
        );
        expect((await session.entries(workspace)).length, 3);
        expect(
          (await session.recurringDue(
            workspace,
            after: BusinessDate(2026, 9, 29),
            through: BusinessDate(2026, 11, 30),
            maxCandidates: 1,
          )).single.dueDate.toString(),
          '2026-11-30',
        );
        await expectLater(
          session.recurringDue(
            workspace,
            after: BusinessDate(2026, 9, 29),
            through: BusinessDate(2026, 11, 30),
            maxCandidates: 0,
          ),
          throwsFormatException,
        );
      });

      final before = await active.snapshot();
      final backup = await active.backup('synthetic-recurring-password');
      for (final method in ['password', 'recovery']) {
        final slots = FixtureKeySlots(Directory('${work.path}/$method-keys'));
        final restored = store(method, slots);
        await restored.restore(
          backup.envelope,
          operation(),
          password: method == 'password'
              ? 'synthetic-recurring-password'
              : null,
          recoveryKey: method == 'recovery' ? backup.recoveryKey : null,
        );
        expect(await restored.snapshot(), before);
        await restored.withSession((session) async {
          expect(
            (await session.recurringTemplates(workspace))
                .single
                .amount
                .majorText,
            '-120.00',
          );
          expect((await session.entries(workspace)).length, 3);
          expect(
            (await session.recurringDue(
              workspace,
              after: BusinessDate(2026, 9, 29),
              through: BusinessDate(2026, 11, 30),
            )).length,
            1,
          );
        });
      }
    },
  );
}
