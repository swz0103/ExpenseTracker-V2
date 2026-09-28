import 'dart:convert';
import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:modular_persistence_probe/database.dart';
import 'package:modular_persistence_probe/storage_binding.dart';
import 'package:modular_persistence_probe/workflows.dart';
import 'package:test/test.dart';
import 'package:validated_restore_probe/snapshot.dart';

void main() {
  final root = Directory('.dart_tool/correction-snapshot-tests')
    ..createSync(recursive: true);
  final codec = SnapshotCodec(correctionsAware: true);
  final currency = Currency('USD', 2);
  final date = BusinessDate(2026, 9, 28);
  late Directory work;
  late ProbeDatabase source;
  late WorkspaceId workspace;
  late Account account;
  late PostingCorrection proposal;

  StorageBinding binding() => StorageBinding(
    PublicId.generate(),
    PublicId.generate(),
    OperationId(PublicId.generate()),
    'b' * 64,
  );
  OperationKey op() =>
      OperationKey(workspace, OperationId(PublicId.generate()));
  Money money(String n) => Money.parse(currency, n);
  PostingAccount ref(Account a) => PostingAccount(
    id: a.id,
    workspace: a.workspace,
    currency: a.currency,
    expectedVersion: a.version,
  );
  Future<ProbeDatabase> stage(List<int> bytes, String name) async {
    final identity = binding();
    final file = File('${work.path}/$name');
    await codec.stage(
      bytes,
      file,
      openDatabase: (f) =>
          ProbeDatabase(f, storageBinding: identity, correctionsAware: true),
    );
    return ProbeDatabase(
      file,
      storageBinding: identity,
      correctionsAware: true,
    );
  }

  setUp(() async {
    work = root.createTempSync('case-');
    workspace = WorkspaceId(PublicId.generate());
    source = ProbeDatabase(
      File('${work.path}/source'),
      storageBinding: binding(),
      correctionsAware: true,
    );
    final flows = FinancialWorkflows(source);
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
    final original = Posting.expense(
      id: PublicId.generate(),
      operation: op(),
      date: date,
      account: ref(account),
      amount: money('10'),
    );
    await flows.post(original);
    proposal = PostingCorrection(
      original: original,
      replacement: Posting.expense(
        id: PublicId.generate(),
        operation: op(),
        date: BusinessDate(2026, 10, 1),
        account: ref(account),
        amount: money('7'),
      ),
      reversalId: PublicId.generate(),
      reversalOperation: op(),
      reason: 'amount correction',
    );
    await flows.correct(proposal);
  });
  tearDown(() async {
    await source.close();
    if (!work.resolveSymbolicLinksSync().startsWith(
      '${root.resolveSymbolicLinksSync()}${Platform.pathSeparator}',
    )) {
      throw StateError('Unsafe cleanup');
    }
    work.deleteSync(recursive: true);
  });

  test(
    'correction relationship, receipts and balance round-trip exactly',
    () async {
      final bytes = await codec.capture(source);
      final root = jsonDecode(utf8.decode(bytes)) as Map;
      expect(root['version'], 12);
      expect(root['schema'], 13);
      expect(root['modules']['ledger_corrections'], 1);
      final restored = await stage(bytes, 'restored');
      try {
        expect(await codec.capture(restored), bytes);
        expect(
          (await FinancialWorkflows(restored).correct(proposal)).replayed,
          true,
        );
        expect(
          await FinancialWorkflows(restored).ledger.balance(ref(account)),
          money('93'),
        );
        expect(await codec.capture(restored), bytes);
      } finally {
        await restored.close();
      }
    },
  );

  test('missing link, orphan, wrong kind, date, audit and pair receipt are refused', () async {
    final bytes = await codec.capture(source);
    for (final kind in [
      'missing-link',
      'orphan',
      'kind',
      'date',
      'audit',
      'receipt',
    ]) {
      final parsed = jsonDecode(utf8.decode(bytes)) as Map;
      final tables = parsed['tables'] as Map;
      final link = (tables['event_corrections'] as List).single as Map;
      if (kind == 'missing-link') tables['event_corrections'] = [];
      if (kind == 'orphan') link['replacement_id'] = PublicId.generate().value;
      if (kind == 'kind') {
        link['replacement_id'] = ((tables['events'] as List).firstWhere(
          (event) => event['kind'] == 'opening',
        ) as Map)['id'];
      }
      if (kind == 'date') {
        final inverse = (tables['events'] as List).firstWhere(
          (event) => event['id'] == proposal.reversal.id.value,
        ) as Map;
        inverse['business_date'] = '2026-09-29';
      }
      if (kind == 'audit') {
        final audit = (tables['audit'] as List).firstWhere(
          (row) => row['entity_id'] == proposal.replacement.id.value,
        ) as Map;
        audit['kind'] = 'ledger.income';
      }
      if (kind == 'receipt') {
        final receipt = (tables['receipts'] as List).firstWhere(
          (row) => row['result_id'] == proposal.reversal.id.value,
        ) as Map;
        final input = jsonDecode(receipt['input'] as String) as List;
        input[4] = 'replacement';
        receipt['input'] = jsonEncode(input);
      }
      await expectLater(
        stage(utf8.encode(jsonEncode(parsed)), 'invalid-$kind'),
        throwsA(isA<InvalidSnapshot>()),
      );
    }
  });

  test(
    'old notes snapshot upgrades with empty correction link table',
    () async {
      final old = ProbeDatabase(
        File('${work.path}/old-notes'),
        storageBinding: binding(),
        notesAware: true,
      );
      try {
        final legacy = await SnapshotCodec(notesAware: true).capture(old);
        final restored = await stage(legacy, 'from-notes');
        try {
          final current =
              jsonDecode(utf8.decode(await codec.capture(restored))) as Map;
          expect(current['version'], 12);
          expect(current['tables']['event_corrections'], isEmpty);
        } finally {
          await restored.close();
        }
      } finally {
        await old.close();
      }
    },
  );
}
