import 'dart:convert';
import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:backup_envelope_probe/envelope.dart';
import 'package:categories/categories.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:ledger_generation_probe/ledger_store.dart';
import 'package:ledger_generation_probe/safety_backup.dart';
import 'package:storage_generation_probe/fixture_catalog_protection.dart';
import 'package:storage_generation_probe/fixture_key_slots.dart';
import 'package:storage_generation_probe/generation_store.dart';
import 'package:validated_restore_probe/snapshot.dart';

const referencePassword = 'synthetic-reference-upgrade-only';
OperationId newOperation() => OperationId(PublicId.generate());
Map referenceTables(List<int> bytes) =>
    (jsonDecode(utf8.decode(bytes)) as Map)['tables'] as Map;

final class ReferenceFixture {
  ReferenceFixture(this.directory);
  final Directory directory;
  final workspace = WorkspaceId(PublicId.generate());
  final food = PublicId.generate(),
      travel = PublicId.generate(),
      salary = PublicId.generate();
  late final keys = FixtureKeySlots(Directory('${directory.path}/keys'));
  late final backups = Directory('${directory.path}/backups')..createSync();
  late final Account account = Account.open(
    id: PublicId.generate(),
    workspace: workspace,
    name: '合成帳戶',
    kind: AccountKind.cash,
    currency: Currency('USD', 2),
    openedOn: BusinessDate(2026, 1, 1),
  );
  late GenerationReceipt original;
  late CreatedBackup credential;
  late UpgradeRequest request;
  late Posting priorIncome;
  late List<int> before, expected;
  PostingAccount get reference => PostingAccount(
    id: account.id,
    workspace: workspace,
    currency: account.currency,
    expectedVersion: 1,
  );
  OperationKey operation() => OperationKey(workspace, newOperation());
  Money money(String amount) => Money.parse(account.currency, amount);
  LedgerStore store({bool references = true}) => LedgerStore(
    Directory('${directory.path}/store'),
    keys,
    catalogProtection: fixtureCatalogProtection(keys),
    categoryAware: true,
    categoryReferences: references,
  );
  LedgerStore target(String name) {
    final slots = FixtureKeySlots(Directory('${directory.path}/$name-keys'));
    return LedgerStore(
      Directory('${directory.path}/$name'),
      slots,
      catalogProtection: fixtureCatalogProtection(slots),
      categoryReferences: true,
    );
  }

  Posting income({bool allocated = true}) => Posting.income(
    id: PublicId.generate(),
    operation: operation(),
    date: BusinessDate(2026, 9, 27),
    account: reference,
    amount: money('20'),
    allocations: allocated
        ? [Allocation(salary, money('20'), expectedCategoryVersion: 1)]
        : [],
  );
  Posting expense({List<Allocation>? allocations, OperationKey? op}) =>
      Posting.expense(
        id: PublicId.generate(),
        operation: op ?? operation(),
        date: BusinessDate(2026, 9, 27),
        account: reference,
        amount: money('10'),
        allocations:
            allocations ??
            [
              Allocation(food, money('6'), expectedCategoryVersion: 1),
              Allocation(travel, money('4'), expectedCategoryVersion: 1),
            ],
      );
  Future<void> initialize() async {
    final old = store(references: false);
    original = await old.initialize(newOperation());
    priorIncome = income(allocated: false);
    await old.withSession((s) async {
      await s.createAccount(
        account,
        Posting.opening(
          id: PublicId.generate(),
          operation: operation(),
          date: account.openedOn,
          account: reference,
          amount: money('100'),
        ),
      );
      await s.createCategory(operation(), food, '餐飲', CategoryKind.expense);
      await s.createCategory(operation(), travel, '交通', CategoryKind.expense);
      await s.createCategory(operation(), salary, '薪資', CategoryKind.income);
      await s.post(priorIncome);
    });
    before = await old.snapshot();
    credential = await old.backup(referencePassword);
    await plan();
  }

  Future<void> plan() async {
    before = await store().snapshot();
    expected = SnapshotCodec(categoryReferences: true).canonicalize(before);
    request = await planCategoryReferenceUpgrade(
      store(),
      newOperation(),
      PublicId.generate(),
    );
  }

  File get backupFile =>
      File('${backups.path}/${request.backupId.value}.envelope');
  Future<UpgradeReceipt> upgrade({void Function(String)? checkpoint}) =>
      upgradeCategoryReferences(
        store(),
        request,
        backups,
        password: referencePassword,
        recoveryKey: credential.recoveryKey,
        checkpoint: checkpoint,
      );
  Future<ProcessResult> childUpgrade(String checkpoint) {
    final input = File('${directory.path}/request.json')
      ..writeAsStringSync(request.encode());
    final unlock = File('${directory.path}/credentials.json')
      ..writeAsStringSync(
        jsonEncode({
          'password': referencePassword,
          'recoveryKey': credential.recoveryKey,
        }),
      );
    return referenceWorker([
      store().generations.directory.absolute.path,
      keys.directory.absolute.path,
      input.absolute.path,
      unlock.absolute.path,
      backups.absolute.path,
      'upgrade',
      checkpoint,
      '${directory.absolute.path}/upgraded.json',
      'references',
    ]);
  }
}

Future<ProcessResult> referenceWorker(List<String> arguments) => Process.run(
  File(
    '.dart_tool/worker/bundle/bin/ledger_worker${Platform.isWindows ? '.exe' : ''}',
  ).absolute.path,
  arguments,
);

void removeReferenceFixture(Directory root, Directory owned) {
  if (!owned.resolveSymbolicLinksSync().startsWith(
    '${root.resolveSymbolicLinksSync()}${Platform.pathSeparator}',
  )) {
    throw StateError('Unsafe fixture cleanup');
  }
  owned.deleteSync(recursive: true);
}
