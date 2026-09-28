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
  final root = Directory('.dart_tool/tombstone-snapshot-tests')
    ..createSync(recursive: true);
  final codec = SnapshotCodec(correctionsAware: true, tombstonesAware: true);
  final currency = Currency('USD', 2);
  final date = BusinessDate(2026, 9, 28);
  late Directory work;
  late ProbeDatabase source;
  late WorkspaceId workspace;
  late Account account;
  late PostingTombstone command;

  StorageBinding binding() => StorageBinding(
    PublicId.generate(),
    PublicId.generate(),
    OperationId(PublicId.generate()),
    'b' * 64,
  );
  OperationKey op() =>
      OperationKey(workspace, OperationId(PublicId.generate()));
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
      openDatabase: (f) => ProbeDatabase(
        f,
        storageBinding: identity,
        correctionsAware: true,
        tombstonesAware: true,
      ),
    );
    return ProbeDatabase(
      file,
      storageBinding: identity,
      correctionsAware: true,
      tombstonesAware: true,
    );
  }

  setUp(() async {
    work = root.createTempSync('case-');
    workspace = WorkspaceId(PublicId.generate());
    source = ProbeDatabase(
      File('${work.path}/source'),
      storageBinding: binding(),
      correctionsAware: true,
      tombstonesAware: true,
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
        amount: Money.parse(currency, '100'),
      ),
    );
    final original = Posting.expense(
      id: PublicId.generate(),
      operation: op(),
      date: date,
      account: ref(account),
      amount: Money.parse(currency, '10'),
    );
    await flows.post(original);
    command = PostingTombstone(
      original: original,
      operation: op(),
      reason: 'mistaken entry',
    );
    await flows.tombstone(command);
  });
  tearDown(() async {
    await source.close();
    if (!work.resolveSymbolicLinksSync().startsWith(
      '${root.resolveSymbolicLinksSync()}${Platform.pathSeparator}',
    )) {
      throw StateError('Unsafe synthetic cleanup');
    }
    work.deleteSync(recursive: true);
  });

  test(
    'marker and exact effective balance round-trip to clean stage',
    () async {
      final bytes = await codec.capture(source);
      final parsed = jsonDecode(utf8.decode(bytes)) as Map;
      expect(parsed['version'], 13);
      expect(parsed['schema'], 14);
      expect(parsed['modules']['ledger_tombstones'], 1);
      expect((parsed['tables']['event_tombstones'] as List), hasLength(1));
      final restored = await stage(bytes, 'restored');
      try {
        expect(await codec.capture(restored), bytes);
        final flows = FinancialWorkflows(restored);
        expect((await flows.tombstone(command)).replayed, true);
        expect(
          await flows.ledger.balance(ref(account)),
          Money.parse(currency, '100'),
        );
        expect(await codec.capture(restored), bytes);
      } finally {
        await restored.close();
      }
    },
  );

  test('missing, orphan or tampered tombstone authority is refused', () async {
    final bytes = await codec.capture(source);
    for (final kind in [
      'missing-marker',
      'orphan',
      'wrong-operation',
      'wrong-kind',
      'missing-receipt',
      'wrong-audit',
      'wrong-reason',
      'wrong-facts',
    ]) {
      final parsed = jsonDecode(utf8.decode(bytes)) as Map;
      final tables = parsed['tables'] as Map;
      final marker = (tables['event_tombstones'] as List).single as Map;
      final receipt = (tables['receipts'] as List).firstWhere(
        (r) => r['operation_id'] == command.operation.operation.toString(),
      ) as Map;
      final audit = (tables['audit'] as List).firstWhere(
        (r) => r['operation_id'] == command.operation.operation.toString(),
      ) as Map;
      if (kind == 'missing-marker') tables['event_tombstones'] = [];
      if (kind == 'orphan') marker['event_id'] = PublicId.generate().value;
      if (kind == 'wrong-operation') {
        marker['operation_id'] = OperationId(PublicId.generate()).toString();
      }
      if (kind == 'wrong-kind') {
        marker['event_id'] = ((tables['events'] as List).firstWhere(
          (e) => e['kind'] == 'opening',
        ) as Map)['id'];
      }
      if (kind == 'missing-receipt') {
        (tables['receipts'] as List).remove(receipt);
      }
      if (kind == 'wrong-audit') audit['kind'] = 'ledger.expense';
      if (kind == 'wrong-reason') marker['reason'] = 'changed';
      if (kind == 'wrong-facts') {
        final input = jsonDecode(receipt['input'] as String) as List;
        input[1][2] = 'income';
        receipt['input'] = jsonEncode(input);
      }
      await expectLater(
        stage(utf8.encode(jsonEncode(parsed)), 'invalid-$kind'),
        throwsA(isA<InvalidSnapshot>()),
        reason: kind,
      );
    }
  });

  test('schema 13 snapshot upgrades with an empty tombstone table', () async {
    final old = ProbeDatabase(
      File('${work.path}/old-corrections'),
      storageBinding: binding(),
      correctionsAware: true,
    );
    try {
      final legacy = await SnapshotCodec(correctionsAware: true).capture(old);
      final restored = await stage(legacy, 'from-corrections');
      try {
        final current =
            jsonDecode(utf8.decode(await codec.capture(restored))) as Map;
        expect(current['version'], 13);
        expect(current['tables']['event_tombstones'], isEmpty);
      } finally {
        await restored.close();
      }
    } finally {
      await old.close();
    }
  });
}
