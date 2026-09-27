import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:android_foundation/key_access.dart';
import 'package:android_foundation/secure_key_slots.dart';
import 'package:expense_preview/preview_engine.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:ledger_generation_probe/ledger_store.dart';
import 'package:storage_generation_probe/catalog_protection.dart';

const password = 'test-only-password-2026';

final class MemoryVault implements PreviewVault, SlotVault {
  final values = <String, String>{};
  bool failWrites = false;
  Future<void> Function(String)? beforeRead;
  @override
  Future<String?> read(String name) async {
    await beforeRead?.call(name);
    return values[name];
  }

  @override
  Future<void> write(String name, String value) async {
    if (failWrites) throw StateError('injected');
    values[name] = value;
  }
}

final class CatalogVault implements KeyVault {
  CatalogVault(this.vault, this.name);
  final MemoryVault vault;
  final String name;
  @override
  Future<String?> read() => vault.read(name);
  @override
  Future<void> write(String value) => vault.write(name, value);
}

PreviewEngine engineAt(
  Directory directory,
  MemoryVault vault, {
  int schemaVersion = 5,
  void Function(String)? checkpoint,
  void Function(String)? draftCheckpoint,
}) => PreviewEngine(
  directory,
  vault,
  (root, id, schema) {
    final access = KeyAccess(CatalogVault(vault, 'catalog_${id.value}'));
    return LedgerStore(
      root,
      SecureKeySlots(vault),
      categoryAware: schema >= 4,
      categoryReferences: schema >= 5,
      tagsAware: schema >= 6,
      merchantsAware: schema >= 7,
      transfersAware: schema >= 8,
      fxTransfersAware: schema >= 9,
      refundsAware: schema >= 10,
      catalogProtection: CatalogProtection(
        id,
        (exists) => access.load(databaseExists: () async => exists),
      ),
    );
  },
  schemaVersion: schemaVersion,
  upgradeCheckpoint: checkpoint,
  draftCheckpoint: draftCheckpoint,
);
Future<String> setup(PreviewEngine engine) async {
  final draft = await engine.prepareSetup(password);
  await engine.finishSetup(draft, password, savedRecovery: true);
  return draft.recoveryKey;
}

Account account(PreviewEngine engine, {String name = '日常現金'}) => Account.open(
  id: PublicId.generate(),
  workspace: engine.workspace,
  name: name,
  kind: AccountKind.cash,
  currency: Currency('TWD', 2),
  openedOn: BusinessDate(2006, 1, 1),
);
PostingAccount ref(Account a) => PostingAccount(
  id: a.id,
  workspace: a.workspace,
  currency: a.currency,
  expectedVersion: 1,
);
Posting opening(Account a) => Posting.opening(
  id: PublicId.generate(),
  operation: OperationKey(a.workspace, OperationId(PublicId.generate())),
  date: a.openedOn,
  account: ref(a),
  amount: Money.parse(a.currency, '100'),
);
Posting income(Account a, {String amount = '7'}) => Posting.income(
  id: PublicId.generate(),
  operation: OperationKey(a.workspace, OperationId(PublicId.generate())),
  date: BusinessDate(2026, 9, 27),
  account: ref(a),
  amount: Money.parse(a.currency, amount),
);

void deleteSynthetic(Directory directory, Directory root) {
  if (!directory.resolveSymbolicLinksSync().startsWith(
    '${root.resolveSymbolicLinksSync()}${Platform.pathSeparator}',
  )) {
    throw StateError('Unsafe synthetic test cleanup');
  }
  directory.deleteSync(recursive: true);
}
