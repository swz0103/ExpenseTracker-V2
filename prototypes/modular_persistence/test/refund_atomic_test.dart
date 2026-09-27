import 'dart:convert';
import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:modular_persistence_probe/database.dart';
import 'package:modular_persistence_probe/fixture_allocation.dart'
    show allocationBinding;
import 'package:modular_persistence_probe/workflows.dart';
import 'package:test/test.dart';

void main() {
  final root = Directory('.dart_tool/refund-atomic-tests')
    ..createSync(recursive: true);
  final workspace = WorkspaceId(PublicId.generate()),
      currency = Currency('USD', 2),
      date = BusinessDate(2026, 9, 28);
  late Directory work;
  late ProbeDatabase db;
  late FinancialWorkflows flows;
  late Account a, b;
  late Posting original;
  OperationKey op([WorkspaceId? ws]) =>
      OperationKey(ws ?? workspace, OperationId(PublicId.generate()));
  Money money(String n) => Money.parse(currency, n);
  PostingAccount ref(Account a) => PostingAccount(
    id: a.id,
    workspace: a.workspace,
    currency: a.currency,
    expectedVersion: a.version,
  );
  Posting refund({Account? account, WorkspaceId? ws, PublicId? source}) =>
      Posting.refund(
        id: PublicId.generate(),
        operation: op(ws),
        date: date,
        account: ref(account ?? b),
        originalId: source ?? original.id,
        amount: money('10'),
      );
  Future<String> state() async {
    final data = <String, Object>{};
    for (final t in [
      'accounts',
      'events',
      'legs',
      'event_refunds',
      'event_fx',
      'allocations',
      'receipts',
      'audit',
    ]) {
      data[t] = [
        for (final r
            in await db.customSelect('SELECT * FROM $t ORDER BY rowid').get())
          r.data,
      ];
    }
    return jsonEncode(data);
  }

  setUp(() async {
    work = root.createTempSync('case-');
    db = ProbeDatabase(
      File('${work.path}/finance.db'),
      storageBinding: allocationBinding(),
      refundsAware: true,
    );
    flows = FinancialWorkflows(db);
    Account account() => Account.open(
      id: PublicId.generate(),
      workspace: workspace,
      name: 'synthetic',
      kind: AccountKind.bank,
      currency: currency,
      openedOn: date,
    );
    a = account();
    b = account();
    for (final account in [a, b]) {
      await flows.createAccount(
        account,
        Posting.opening(
          id: PublicId.generate(),
          operation: op(),
          date: date,
          account: ref(account),
          amount: money('100'),
        ),
      );
    }
    original = Posting.expense(
      id: PublicId.generate(),
      operation: op(),
      date: date,
      account: ref(a),
      amount: money('10'),
    );
    await flows.post(original);
  });
  tearDown(() async {
    await db.close();
    if (!work.resolveSymbolicLinksSync().startsWith(
      '${root.resolveSymbolicLinksSync()}${Platform.pathSeparator}',
    ))
      throw StateError('Unsafe cleanup');
    work.deleteSync(recursive: true);
  });
  test('every unclassified refund write checkpoint rolls back relation, cash, receipt and audit', () async {
    final before = await state(), p = refund();
    for (final point in ['event', 'refund', 'leg', 'receipt', 'audit']) {
      await expectLater(
        flows.post(
          p,
          checkpoint: (current) {
            if (current == point) throw StateError('injected');
          },
        ),
        throwsStateError,
      );
      expect(await state(), before);
    }
    await flows.post(p);
    expect((await flows.post(p)).replayed, true);
    expect(await flows.ledger.balance(ref(a)), money('90'));
    expect(await flows.ledger.balance(ref(b)), money('110'));
  });
  test('archived paying account may refund to active recipient; archived recipient and foreign workspace reject', () async {
    await flows.archive(workspace, a.id, 1, OperationId(PublicId.generate()));
    final before = await state();
    await expectLater(
      flows.post(refund(account: a)),
      throwsA(isA<AccountException>()),
    );
    expect(await state(), before);
    final other = WorkspaceId(PublicId.generate());
    final foreign = Account.open(
      id: PublicId.generate(),
      workspace: other,
      name: 'other',
      kind: AccountKind.bank,
      currency: currency,
      openedOn: date,
    );
    await flows.createAccount(
      foreign,
      Posting.opening(
        id: PublicId.generate(),
        operation: op(other),
        date: date,
        account: ref(foreign),
        amount: money('0'),
      ),
    );
    final across = await state();
    await expectLater(
      flows.post(refund(account: foreign, ws: other)),
      throwsA(isA<LedgerException>()),
    );
    expect(await state(), across);
    await flows.post(refund());
    expect(await flows.ledger.balance(ref(b)), money('110'));
  });
}
