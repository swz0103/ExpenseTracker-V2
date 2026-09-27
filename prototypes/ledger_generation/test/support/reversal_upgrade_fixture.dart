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

const reversalPassword = 'synthetic-reference-upgrade-only';
OperationId reversalOperation() => OperationId(PublicId.generate());
Map reversalTables(List<int> bytes) =>
    (jsonDecode(utf8.decode(bytes)) as Map)['tables'] as Map;

final class ReversalUpgradeFixture {
  ReversalUpgradeFixture(this.directory);
  final Directory directory;
  final workspace = WorkspaceId(PublicId.generate());
  final tag = PublicId.generate();
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
  OperationKey operation() => OperationKey(workspace, reversalOperation());
  Money money(String amount) => Money.parse(account.currency, amount);
  LedgerStore store({bool reversals = true}) => LedgerStore(
    Directory('${directory.path}/store'),
    keys,
    catalogProtection: fixtureCatalogProtection(keys),
    categoryAware: true,
    categoryReferences: true,
    tagsAware: true,
    merchantsAware: true,
    transfersAware: true,
    fxTransfersAware: true,
    refundsAware: true,
    reversalsAware: reversals,
  );
  LedgerStore target(String name) {
    final slots = FixtureKeySlots(Directory('${directory.path}/$name-keys'));
    return LedgerStore(
      Directory('${directory.path}/$name'),
      slots,
      catalogProtection: fixtureCatalogProtection(slots),
      reversalsAware: true,
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
    final old = store(reversals: false);
    original = await old.initialize(reversalOperation());
    priorIncome = income();
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
      await s.createTag(operation(), tag, '原有標籤');
      final merchant = PublicId.generate();
      await s.createMerchant(operation(), merchant, '原有商家');
      await s.post(
        priorIncome,
        tags: [TagSelection(tag, 1)],
        merchant: MerchantSelection(merchant, 1),
      );
    });
    await old.withSession((s) async {
      final second = Account.open(
        id: PublicId.generate(),
        workspace: workspace,
        name: '既有同幣轉入',
        kind: AccountKind.bank,
        currency: Currency('JPY', 0),
        openedOn: account.openedOn,
      );
      final secondRef = PostingAccount(
        id: second.id,
        workspace: workspace,
        currency: second.currency,
        expectedVersion: 1,
      );
      await s.createAccount(
        second,
        Posting.opening(
          id: PublicId.generate(),
          operation: operation(),
          date: account.openedOn,
          account: secondRef,
          amount: Money.parse(second.currency, '0'),
        ),
      );
      await s.post(
        Posting.transfer(
          id: PublicId.generate(),
          operation: operation(),
          date: account.openedOn,
          source: reference,
          destination: secondRef,
          principal: money('3'),
          received: Money.parse(second.currency, '450'),
          fee: money('0.1'),
        ),
      );
    });
    await old.withSession((s) async {
      final source = expense();
      await s.post(source);
      await s.post(
        Posting.refund(
          id: PublicId.generate(),
          operation: operation(),
          date: source.date,
          account: reference,
          originalId: source.id,
          amount: money('1'),
          allocations: [
            Allocation(food, money('1'), expectedCategoryVersion: 1),
          ],
        ),
      );
    });
    before = await old.snapshot();
    credential = await old.backup(reversalPassword);
    await plan();
  }

  Future<void> plan() async {
    before = await store().snapshot();
    expected = SnapshotCodec(reversalsAware: true).canonicalize(before);
    request = await planReversalUpgrade(
      store(),
      reversalOperation(),
      PublicId.generate(),
    );
  }

  File get backupFile =>
      File('${backups.path}/${request.backupId.value}.envelope');
  Future<UpgradeReceipt> upgrade({void Function(String)? checkpoint}) =>
      upgradeReversals(
        store(),
        request,
        backups,
        password: reversalPassword,
        recoveryKey: credential.recoveryKey,
        checkpoint: checkpoint,
      );
  Future<ProcessResult> childUpgrade(String checkpoint) {
    final input = File('${directory.path}/request.json')
      ..writeAsStringSync(request.encode());
    final unlock = File('${directory.path}/credentials.json')
      ..writeAsStringSync(
        jsonEncode({
          'password': reversalPassword,
          'recoveryKey': credential.recoveryKey,
        }),
      );
    return reversalWorker([
      store().generations.directory.absolute.path,
      keys.directory.absolute.path,
      input.absolute.path,
      unlock.absolute.path,
      backups.absolute.path,
      'upgrade',
      checkpoint,
      '${directory.absolute.path}/upgraded.json',
      'reversals',
    ]);
  }
}

Future<ProcessResult> reversalWorker(List<String> arguments) => Process.run(
  File(
    '.dart_tool/worker/bundle/bin/ledger_worker${Platform.isWindows ? '.exe' : ''}',
  ).absolute.path,
  arguments,
);

void removeReversalUpgradeFixture(Directory root, Directory owned) {
  if (!owned.resolveSymbolicLinksSync().startsWith(
    '${root.resolveSymbolicLinksSync()}${Platform.pathSeparator}',
  )) {
    throw StateError('Unsafe fixture cleanup');
  }
  owned.deleteSync(recursive: true);
}
