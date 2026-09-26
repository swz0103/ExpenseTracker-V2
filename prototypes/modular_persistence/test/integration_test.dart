import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:modular_persistence_probe/database.dart';
import 'package:modular_persistence_probe/workflows.dart';
import 'package:test/test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  final root = Directory('.dart_tool/integration-tests')
    ..createSync(recursive: true);
  final workspace = WorkspaceId(PublicId.generate());
  final usd = Currency('USD', 2);
  final date = BusinessDate(2026, 9, 26);
  late Directory fixture;
  late ProbeDatabase db;
  late FinancialWorkflows flows;
  setUp(() {
    fixture = root.createTempSync('db-');
    db = ProbeDatabase(File('${fixture.path}/finance.db'));
    flows = FinancialWorkflows(db);
  });
  tearDown(() async {
    await db.close();
    final resolvedRoot = root.resolveSymbolicLinksSync();
    final resolvedFixture = fixture.resolveSymbolicLinksSync();
    if (!resolvedFixture.startsWith('$resolvedRoot${Platform.pathSeparator}'))
      throw StateError('Unsafe fixture cleanup.');
    fixture.deleteSync(recursive: true);
  });
  Account account({WorkspaceId? owner}) => Account.open(
    id: PublicId.generate(),
    workspace: owner ?? workspace,
    name: 'Fixture',
    kind: AccountKind.bank,
    currency: usd,
    openedOn: date,
  );
  PostingAccount ref(Account a) => PostingAccount(
    id: a.id,
    workspace: a.workspace,
    currency: a.currency,
    expectedVersion: a.version,
  );
  OperationKey key([WorkspaceId? owner]) =>
      OperationKey(owner ?? workspace, OperationId(PublicId.generate()));
  Money money(String text) => Money.parse(usd, text);
  Posting opening(Account a, String amount, {OperationKey? operation}) =>
      Posting.opening(
        id: PublicId.generate(),
        operation: operation ?? key(a.workspace),
        date: date,
        account: ref(a),
        amount: money(amount),
      );
  Posting income(Account a, String amount, {OperationKey? operation}) =>
      Posting.income(
        id: PublicId.generate(),
        operation: operation ?? key(a.workspace),
        date: date,
        account: ref(a),
        amount: money(amount),
      );
  Future<Map<String, int>> counts() async {
    final result = <String, int>{};
    for (final table in [
      'accounts',
      'events',
      'legs',
      'openings',
      'allocations',
      'receipts',
      'audit',
    ]) {
      result[table] =
          (await db
                  .customSelect('SELECT count(*) AS n FROM $table')
                  .getSingle())
              .read<int>('n');
    }
    expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    expect(
      (await db.customSelect('PRAGMA integrity_check').getSingle())
          .data
          .values
          .single,
      'ok',
    );
    return result;
  }

  for (final checkpoint in ['account', 'event', 'leg', 'receipt', 'audit']) {
    test(
      'TX-01 create rollback after $checkpoint leaves all tables empty',
      () async {
        final a = account();
        await expectLater(
          flows.createAccount(
            a,
            opening(a, '100'),
            checkpoint: (point) {
              if (point == checkpoint) throw StateError('injected');
            },
          ),
          throwsStateError,
        );
        expect((await counts()).values, everyElement(0));
      },
    );
  }
  test(
    'LED-01 account and real postings survive reopen with balance 115',
    () async {
      final a = account();
      await flows.createAccount(a, opening(a, '100'));
      await flows.post(income(a, '20'));
      await flows.post(
        Posting.expense(
          id: PublicId.generate(),
          operation: key(),
          date: date,
          account: ref(a),
          amount: money('5'),
        ),
      );
      await db.close();
      db = ProbeDatabase(File('${fixture.path}/finance.db'));
      flows = FinancialWorkflows(db);
      expect((await flows.accounts.read(workspace, a.id)).name, a.name);
      expect(await flows.ledger.balance(ref(a)), money('115'));
      expect(await counts(), {
        'accounts': 1,
        'events': 3,
        'legs': 3,
        'openings': 1,
        'allocations': 0,
        'receipts': 3,
        'audit': 3,
      });
      final report = await db
          .customSelect(
            'SELECT sum(income) AS income, sum(expense) AS expense FROM events',
          )
          .getSingle();
      expect(report.read<int>('income'), 2000);
      expect(report.read<int>('expense'), 500);
    },
  );
  test('TX-02 replay after reopen returns original result even with new proposed result ID', () async {
    final a = account();
    final operation = key();
    await flows.createAccount(a, opening(a, '0'));
    final original = await flows.post(income(a, '20', operation: operation));
    await db.close();
    db = ProbeDatabase(File('${fixture.path}/finance.db'));
    flows = FinancialWorkflows(db);
    final retry = await flows.post(income(a, '20', operation: operation));
    expect(retry.id, original.id);
    expect(retry.replayed, isTrue);
    await expectLater(
      flows.post(income(a, '21', operation: operation)),
      throwsA(isA<OperationConflict>()),
    );
    expect(await flows.ledger.balance(ref(a)), money('20'));
    expect((await counts())['audit'], 2);
  });
  test('TX-04 archived state is reloaded and stale preview rejected', () async {
    final a = account();
    await flows.createAccount(a, opening(a, '10'));
    final preview = income(a, '20');
    await flows.archive(workspace, a.id, 1, OperationId(PublicId.generate()));
    await expectLater(
      flows.post(preview),
      throwsA(
        isA<AccountException>().having(
          (e) => e.code,
          'code',
          AccountError.versionConflict,
        ),
      ),
    );
    final restored = await flows.accounts.read(workspace, a.id);
    expect(restored.state, AccountState.archived);
    expect(restored.version, 2);
    expect(await flows.ledger.balance(ref(a)), money('10'));
    expect((await counts())['events'], 1);
  });
  test(
    'opening unique constraint rolls back a second opening completely',
    () async {
      final a = account();
      await flows.createAccount(a, opening(a, '10'));
      final before = await counts();
      await expectLater(
        flows.post(opening(a, '99')),
        throwsA(isA<SqliteException>()),
      );
      expect(await counts(), before);
      expect(await flows.ledger.balance(ref(a)), money('10'));
    },
  );
  test(
    'transfer failure rolls both sides back, then retry charges fee once',
    () async {
      final a = account();
      final b = account();
      await flows.createAccount(a, opening(a, '100'));
      await flows.createAccount(b, opening(b, '0'));
      final transfer = Posting.transfer(
        id: PublicId.generate(),
        operation: key(),
        date: date,
        source: ref(a),
        destination: ref(b),
        principal: money('25'),
        fee: money('1'),
      );
      final before = await counts();
      await expectLater(
        flows.post(
          transfer,
          checkpoint: (point) {
            if (point == 'leg') throw StateError('injected');
          },
        ),
        throwsStateError,
      );
      expect(await counts(), before);
      await flows.post(transfer);
      await flows.post(transfer);
      expect(await flows.ledger.balance(ref(a)), money('74'));
      expect(await flows.ledger.balance(ref(b)), money('25'));
      expect((await counts())['audit'], 3);
    },
  );
  test('final balance overflow rejects and leaves prior data intact', () async {
    final a = account();
    await flows.createAccount(a, opening(a, '92233720368547758.07'));
    final before = await counts();
    await expectLater(
      flows.post(income(a, '0.01')),
      throwsA(isA<MoneyException>()),
    );
    expect(await counts(), before);
  });
  test('workspace lookup cannot reuse another workspace account', () async {
    final a = account();
    await flows.createAccount(a, opening(a, '10'));
    final other = WorkspaceId(PublicId.generate());
    await expectLater(
      flows.accounts.read(other, a.id),
      throwsA(isA<AccountException>()),
    );
    final wrongRef = PostingAccount(
      id: a.id,
      workspace: other,
      currency: usd,
      expectedVersion: 1,
    );
    await expectLater(
      flows.post(
        Posting.income(
          id: PublicId.generate(),
          operation: key(other),
          date: date,
          account: wrongRef,
          amount: money('2'),
        ),
      ),
      throwsA(isA<AccountException>()),
    );
    expect(await flows.ledger.balance(ref(a)), money('10'));
  });
  test(
    'simultaneous retries on one Drift executor produce one posting',
    () async {
      final a = account();
      await flows.createAccount(a, opening(a, '0'));
      final posting = income(a, '5');
      final results = await Future.wait([
        flows.post(posting),
        flows.post(posting),
      ]);
      expect(
        results.map((result) => result.replayed),
        unorderedEquals([false, true]),
      );
      expect(await flows.ledger.balance(ref(a)), money('5'));
      expect((await counts())['events'], 2);
    },
  );
}
