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
  final root = Directory('.dart_tool/reversal-atomic-tests')
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
  Posting reversal() => Posting.reversal(
    id: PublicId.generate(),
    operation: op(),
    date: date,
    original: original,
    reason: 'wrong',
  );
  Future<String> state() async {
    final data = <String, Object>{};
    for (final t in [
      'accounts',
      'events',
      'legs',
      'event_refunds',
      'event_reversals',
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
      reversalsAware: true,
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

  test(
    'each write checkpoint rolls back reversal and original; replay once',
    () async {
      final before = await state(), p = reversal();
      for (final point in ['event', 'reversal', 'leg', 'receipt', 'audit']) {
        await expectLater(
          flows.post(
            p,
            checkpoint: (x) {
              if (x == point) throw StateError('injected');
            },
          ),
          throwsStateError,
        );
        expect(await state(), before);
      }
      await flows.post(p);
      expect((await flows.post(p)).replayed, true);
      expect(await flows.ledger.balance(ref(a)), money('100'));
    },
  );
  test('archived participating account cannot reverse; state and original retained', () async {
    await flows.archive(workspace, a.id, 1, OperationId(PublicId.generate()));
    final before = await state();
    await expectLater(flows.post(reversal()), throwsA(isA<AccountException>()));
    expect(await state(), before);
  });
  test(
    'each of three transfer legs and FX context rolls back together',
    () async {
      final foreign = Account.open(
        id: PublicId.generate(),
        workspace: workspace,
        name: 'JPY',
        kind: AccountKind.bank,
        currency: Currency('JPY', 0),
        openedOn: date,
      );
      await flows.createAccount(
        foreign,
        Posting.opening(
          id: PublicId.generate(),
          operation: op(),
          date: date,
          account: ref(foreign),
          amount: Money.parse(foreign.currency, '100'),
        ),
      );
      final source = Posting.transfer(
        id: PublicId.generate(),
        operation: op(),
        date: date,
        source: ref(a),
        destination: ref(foreign),
        principal: money('3'),
        received: Money.parse(foreign.currency, '450'),
        fee: money('0.01'),
      );
      await flows.post(source);
      final p = Posting.reversal(
        id: PublicId.generate(),
        operation: op(),
        date: date,
        original: source,
      );
      final before = await state();
      for (var n = 1; n <= 3; n++) {
        var seen = 0;
        await expectLater(
          flows.post(
            p,
            checkpoint: (x) {
              if (x == 'leg' && ++seen == n) throw StateError('injected');
            },
          ),
          throwsStateError,
        );
        expect(await state(), before);
      }
      await expectLater(
        flows.post(
          p,
          checkpoint: (x) {
            if (x == 'conversion') throw StateError('injected');
          },
        ),
        throwsStateError,
      );
      expect(await state(), before);
      await flows.post(p);
      expect(await flows.ledger.balance(ref(a)), money('90'));
      expect(
        await flows.ledger.balance(ref(foreign)),
        Money.parse(foreign.currency, '100'),
      );
    },
  );
}
