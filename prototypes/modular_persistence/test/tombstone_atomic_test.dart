import 'dart:convert';
import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:modular_persistence_probe/database.dart';
import 'package:modular_persistence_probe/fixture_allocation.dart'
    show allocationBinding;
import 'package:modular_persistence_probe/refunds_adapter.dart';
import 'package:modular_persistence_probe/reversals_adapter.dart';
import 'package:modular_persistence_probe/workflows.dart';
import 'package:test/test.dart';

void main() {
  final root = Directory('.dart_tool/tombstone-atomic-tests')
    ..createSync(recursive: true);
  late Directory work;
  late ProbeDatabase db;
  late FinancialWorkflows flows;
  late WorkspaceId workspace;
  late Account account;
  late Posting original;
  final usd = Currency('USD', 2), jpy = Currency('JPY', 0);
  final date = BusinessDate(2026, 9, 28);

  OperationKey op() =>
      OperationKey(workspace, OperationId(PublicId.generate()));
  PostingAccount ref(Account a) => PostingAccount(
    id: a.id,
    workspace: workspace,
    currency: a.currency,
    expectedVersion: a.version,
  );
  PostingTombstone deletion([Posting? source]) => PostingTombstone(
    original: source ?? original,
    operation: op(),
    reason: 'synthetic mistaken entry',
  );
  Future<String> state() async {
    final data = <String, Object>{};
    for (final table in [
      'accounts',
      'events',
      'legs',
      'event_reversals',
      'event_corrections',
      'event_tombstones',
      'receipts',
      'audit',
    ]) {
      data[table] = [
        for (final row
            in await db
                .customSelect('SELECT * FROM $table ORDER BY rowid')
                .get())
          row.data,
      ];
    }
    return jsonEncode(data);
  }

  setUp(() async {
    work = root.createTempSync('case-');
    workspace = WorkspaceId(PublicId.generate());
    db = ProbeDatabase(
      File('${work.path}/finance.db'),
      storageBinding: allocationBinding(),
      correctionsAware: true,
      tombstonesAware: true,
    );
    flows = FinancialWorkflows(db);
    account = Account.open(
      id: PublicId.generate(),
      workspace: workspace,
      name: 'synthetic USD',
      kind: AccountKind.bank,
      currency: usd,
      openedOn: date,
    );
    await flows.createAccount(
      account,
      Posting.opening(
        id: PublicId.generate(),
        operation: op(),
        date: date,
        account: ref(account),
        amount: Money.parse(usd, '100'),
      ),
    );
    original = Posting.expense(
      id: PublicId.generate(),
      operation: op(),
      date: date,
      account: ref(account),
      amount: Money.parse(usd, '10'),
    );
    await flows.post(original);
  });
  tearDown(() async {
    await db.close();
    if (!work.resolveSymbolicLinksSync().startsWith(
      '${root.resolveSymbolicLinksSync()}${Platform.pathSeparator}',
    )) {
      throw StateError('Unsafe synthetic cleanup');
    }
    work.deleteSync(recursive: true);
  });

  test(
    'schema 14 excludes once but retains history, receipt and audit',
    () async {
      expect(db.schemaVersion, 14);
      expect(await flows.ledger.balance(ref(account)), Money.parse(usd, '90'));
      final command = deletion();
      expect((await flows.tombstone(command)).replayed, false);
      expect(await flows.ledger.balance(ref(account)), Money.parse(usd, '100'));
      final committed = await state();
      expect((await flows.tombstone(command)).replayed, true);
      expect(await state(), committed);
      expect(
        (await db.customSelect('SELECT * FROM events').get()),
        hasLength(2),
      );
      expect(
        (await db.customSelect('SELECT * FROM event_tombstones').get()),
        hasLength(1),
      );
      for (final read in [
        () => readReversalSource(db, workspace, original.id),
        () => readRefundSource(db, workspace, original.id),
      ]) {
        await expectLater(read(), throwsA(isA<LedgerException>()));
      }
      await expectLater(
        flows.correct(
          PostingCorrection(
            original: original,
            replacement: Posting.expense(
              id: PublicId.generate(),
              operation: op(),
              date: date,
              account: ref(account),
              amount: Money.parse(usd, '7'),
            ),
            reversalId: PublicId.generate(),
            reversalOperation: op(),
          ),
        ),
        throwsA(isA<LedgerException>()),
      );
      expect(await state(), committed);
      await expectLater(
        flows.tombstone(deletion()),
        throwsA(isA<OperationConflict>()),
      );
    },
  );

  test('all transfer legs and fee leave effective balance together', () async {
    final foreign = Account.open(
      id: PublicId.generate(),
      workspace: workspace,
      name: 'synthetic JPY',
      kind: AccountKind.bank,
      currency: jpy,
      openedOn: date,
    );
    await flows.createAccount(
      foreign,
      Posting.opening(
        id: PublicId.generate(),
        operation: op(),
        date: date,
        account: ref(foreign),
        amount: Money.parse(jpy, '100'),
      ),
    );
    final transfer = Posting.transfer(
      id: PublicId.generate(),
      operation: op(),
      date: date,
      source: ref(account),
      destination: ref(foreign),
      principal: Money.parse(usd, '10'),
      received: Money.parse(jpy, '1500'),
      fee: Money.parse(usd, '0.10'),
    );
    await flows.post(transfer);
    expect(await flows.ledger.balance(ref(account)), Money.parse(usd, '79.90'));
    expect(await flows.ledger.balance(ref(foreign)), Money.parse(jpy, '1600'));
    await flows.tombstone(deletion(transfer));
    expect(await flows.ledger.balance(ref(account)), Money.parse(usd, '90'));
    expect(await flows.ledger.balance(ref(foreign)), Money.parse(jpy, '100'));
  });

  test(
    'stale frozen facts and write failures cannot leave half a deletion',
    () async {
      final wrong = Posting.expense(
        id: original.id,
        operation: original.operation,
        date: date,
        account: ref(account),
        amount: Money.parse(usd, '9'),
      );
      final before = await state();
      await expectLater(
        flows.tombstone(deletion(wrong)),
        throwsA(isA<LedgerException>()),
      );
      expect(await state(), before);
      final command = deletion();
      for (final point in ['tombstone', 'receipt', 'audit']) {
        await expectLater(
          flows.tombstone(
            command,
            checkpoint: (at) {
              if (at == point) throw StateError('injected');
            },
          ),
          throwsStateError,
        );
        expect(await state(), before, reason: point);
      }
      await flows.tombstone(command);
      expect(await flows.ledger.balance(ref(account)), Money.parse(usd, '100'));
    },
  );

  test('an already reversed event cannot be tombstoned', () async {
    await flows.post(
      Posting.reversal(
        id: PublicId.generate(),
        operation: op(),
        date: date,
        original: original,
      ),
    );
    final before = await state();
    await expectLater(
      flows.tombstone(deletion()),
      throwsA(isA<LedgerException>()),
    );
    expect(await state(), before);
  });

  test('an already corrected event cannot be tombstoned', () async {
    await flows.correct(
      PostingCorrection(
        original: original,
        replacement: Posting.expense(
          id: PublicId.generate(),
          operation: op(),
          date: date,
          account: ref(account),
          amount: Money.parse(usd, '7'),
        ),
        reversalId: PublicId.generate(),
        reversalOperation: op(),
      ),
    );
    final before = await state();
    await expectLater(
      flows.tombstone(deletion()),
      throwsA(isA<LedgerException>()),
    );
    expect(await state(), before);
  });
}
