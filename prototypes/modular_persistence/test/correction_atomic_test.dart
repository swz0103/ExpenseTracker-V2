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
  final root = Directory('.dart_tool/correction-atomic-tests')
    ..createSync(recursive: true);
  final workspace = WorkspaceId(PublicId.generate());
  final currency = Currency('USD', 2);
  final date = BusinessDate(2026, 9, 28);
  late Directory work;
  late ProbeDatabase db;
  late FinancialWorkflows flows;
  late Account account;
  late Posting original;

  OperationKey op() =>
      OperationKey(workspace, OperationId(PublicId.generate()));
  Money money(String amount) => Money.parse(currency, amount);
  PostingAccount ref(Account a, {int? version}) => PostingAccount(
    id: a.id,
    workspace: a.workspace,
    currency: a.currency,
    expectedVersion: version ?? a.version,
  );
  PostingCorrection correction({int? replacementVersion}) => PostingCorrection(
    original: original,
    replacement: Posting.expense(
      id: PublicId.generate(),
      operation: op(),
      date: BusinessDate(2026, 10, 31),
      account: ref(account, version: replacementVersion),
      amount: money('7'),
    ),
    reversalId: PublicId.generate(),
    reversalOperation: op(),
    reason: 'incorrect amount and month',
  );
  Future<String> state() async {
    final data = <String, Object>{};
    for (final table in [
      'accounts',
      'events',
      'legs',
      'event_reversals',
      'event_corrections',
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
    db = ProbeDatabase(
      File('${work.path}/finance.db'),
      storageBinding: allocationBinding(),
      correctionsAware: true,
    );
    flows = FinancialWorkflows(db);
    account = Account.open(
      id: PublicId.generate(),
      workspace: workspace,
      name: 'synthetic',
      kind: AccountKind.bank,
      currency: currency,
      openedOn: date,
    );
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
    original = Posting.expense(
      id: PublicId.generate(),
      operation: op(),
      date: date,
      account: ref(account),
      amount: money('10'),
    );
    await flows.post(original);
  });
  tearDown(() async {
    await db.close();
    if (!work.resolveSymbolicLinksSync().startsWith(
      '${root.resolveSymbolicLinksSync()}${Platform.pathSeparator}',
    )) {
      throw StateError('Unsafe cleanup');
    }
    work.deleteSync(recursive: true);
  });

  test(
    'two receipts and unique link commit once; replay preserves exact balance',
    () async {
      final proposal = correction();
      final result = await flows.correct(proposal);
      expect(result.replayed, false);
      expect(result.reversalId, proposal.reversal.id);
      expect(result.replacementId, proposal.replacement.id);
      expect(await flows.ledger.balance(ref(account)), money('93'));
      final committed = await state();
      expect((await flows.correct(proposal)).replayed, true);
      expect(await state(), committed);
      final link = await db
          .customSelect('SELECT * FROM event_corrections')
          .getSingle();
      expect(link.read<String>('original_id'), original.id.value);
      expect(link.read<String>('reversal_id'), proposal.reversal.id.value);
      expect(
        link.read<String>('replacement_id'),
        proposal.replacement.id.value,
      );
    },
  );

  test('schema 13 retains prior metadata tables and capability chain', () async {
    expect(db.schemaVersion, 13);
    expect(db.categoryAware, true);
    expect(db.categoryReferences, true);
    expect(db.tagsAware, true);
    expect(db.merchantsAware, true);
    expect(db.notesAware, true);
    for (final table in [
      'categories',
      'tags',
      'merchants',
      'event_note_revisions',
      'event_corrections',
    ]) {
      final rows = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='$table'",
          )
          .get();
      expect(rows, hasLength(1), reason: table);
    }
  });

  test('failure at either posting or link rolls every row back', () async {
    final proposal = correction();
    final before = await state();
    for (final point in [
      'reversal:event',
      'reversal:receipt',
      'replacement:event',
      'replacement:receipt',
      'correction:link',
    ]) {
      await expectLater(
        flows.correct(
          proposal,
          checkpoint: (seen) {
            if (seen == point) throw StateError('injected');
          },
        ),
        throwsStateError,
      );
      expect(await state(), before, reason: point);
    }
    await flows.correct(proposal);
    expect(await flows.ledger.balance(ref(account)), money('93'));
  });

  test(
    'a standalone reversal cannot be adopted as a successful correction',
    () async {
      final proposal = correction();
      await flows.post(proposal.reversal);
      final before = await state();
      await expectLater(
        flows.correct(proposal),
        throwsA(isA<OperationConflict>()),
      );
      expect(await state(), before);
    },
  );

  test(
    'a replay with changed replacement facts or another pair is rejected',
    () async {
      final proposal = correction();
      await flows.correct(proposal);
      final committed = await state();
      final changed = PostingCorrection(
        original: original,
        replacement: Posting.expense(
          id: proposal.replacement.id,
          operation: proposal.replacement.operation,
          date: proposal.replacement.date,
          account: ref(account),
          amount: money('8'),
        ),
        reversalId: proposal.reversal.id,
        reversalOperation: proposal.reversal.operation,
        reason: 'incorrect amount and month',
      );
      await expectLater(
        flows.correct(changed),
        throwsA(isA<OperationConflict>()),
      );
      await expectLater(
        flows.correct(correction()),
        throwsA(isA<OperationConflict>()),
      );
      expect(await state(), committed);
    },
  );

  test('invalid replacement rolls back an otherwise valid reversal', () async {
    final proposal = correction(replacementVersion: 99);
    final before = await state();
    await expectLater(
      flows.correct(proposal),
      throwsA(isA<AccountException>()),
    );
    expect(await state(), before);
  });

  test(
    'cross-currency transfer and source fee are replaced as one pair',
    () async {
      final yen = Currency('JPY', 0);
      final destination = Account.open(
        id: PublicId.generate(),
        workspace: workspace,
        name: 'JPY',
        kind: AccountKind.bank,
        currency: yen,
        openedOn: date,
      );
      await flows.createAccount(
        destination,
        Posting.opening(
          id: PublicId.generate(),
          operation: op(),
          date: date,
          account: ref(destination),
          amount: Money.parse(yen, '1000'),
        ),
      );
      final source = Posting.transfer(
        id: PublicId.generate(),
        operation: op(),
        date: date,
        source: ref(account),
        destination: ref(destination),
        principal: money('3'),
        received: Money.parse(yen, '450'),
        fee: money('0.01'),
      );
      await flows.post(source);
      final proposal = PostingCorrection(
        original: source,
        replacement: Posting.transfer(
          id: PublicId.generate(),
          operation: op(),
          date: BusinessDate(2026, 10, 1),
          source: ref(account),
          destination: ref(destination),
          principal: money('4'),
          received: Money.parse(yen, '600'),
          fee: money('0.02'),
        ),
        reversalId: PublicId.generate(),
        reversalOperation: op(),
      );
      await flows.correct(proposal);
      expect(await flows.ledger.balance(ref(account)), money('85.98'));
      expect(
        await flows.ledger.balance(ref(destination)),
        Money.parse(yen, '1600'),
      );
      for (final eventId in [proposal.reversal.id, proposal.replacement.id]) {
        final rows = await db
            .customSelect(
              "SELECT event_id FROM legs WHERE event_id='${eventId.value}'",
            )
            .get();
        expect(rows, hasLength(3));
      }
    },
  );
}
