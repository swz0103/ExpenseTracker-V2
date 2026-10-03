import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:backup_security/backup_security.dart';
import 'package:bookkeeping/bookkeeping.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger_vault/ledger_vault.dart';
import 'package:test/test.dart';

const password = 'correct horse battery';
final codec = KeyringCodec(kdf: PasswordKdf.insecureForTests);

Matcher fails(VaultProblem problem) =>
    throwsA(isA<VaultException>().having((e) => e.problem, 'problem', problem));

const wrongSecret = KeyringException(KeyringError.wrongSecret);

/// Stands in for an Android Keystore key.
final class FakeDeviceKey implements DeviceKeyWrapper {
  final _secrets = <String, List<int>>{};

  @override
  Future<List<int>> wrap(List<int> secret, List<int> context) async {
    final handle = 'blob-${_secrets.length}:${context.join(',')}';
    _secrets[handle] = List.of(secret);
    return handle.codeUnits;
  }

  @override
  Future<List<int>> unwrap(List<int> wrapped, List<int> context) async {
    final handle = String.fromCharCodes(wrapped);
    final secret = _secrets[handle];
    if (secret == null || !handle.endsWith(':${context.join(',')}')) {
      throw StateError('not this device');
    }
    return secret;
  }
}

void main() {
  late Directory directory;
  late LedgerVault vault;
  final twd = Currency.of('TWD');

  setUp(() {
    directory = Directory.systemTemp.createTempSync('ledger-vault-');
    vault = LedgerVault(Directory('${directory.path}/ledger'), codec: codec);
  });

  tearDown(() => directory.deleteSync(recursive: true));

  Future<void> openAccount(OpenVault open, [WorkspaceId? workspace]) async {
    workspace ??= WorkspaceId(PublicId.generate());
    await Bookkeeping(open.ledger).openAccount(
      OpenAccount(
        operation: OperationKey(workspace, OperationId(PublicId.generate())),
        accountId: PublicId.generate(),
        name: '現金',
        kind: AccountKind.cash,
        currency: twd,
        openedOn: BusinessDate(2026, 10, 3),
        openingBalance: Money(twd, BigInt.from(100)),
        openingPostingId: PublicId.generate(),
      ),
    );
  }

  test('a new ledger reopens with the password or recovery code', () async {
    expect(vault.exists, isFalse);
    await expectLater(
      vault.unlockWithPassword(password),
      fails(VaultProblem.missing),
    );
    final (open, recovery) = await vault.create(password);
    final workspace = open.workspace;
    // An empty ledger keeps offering one workspace until the first command.
    expect(open.workspace, same(workspace));
    await openAccount(open, workspace);
    final events = open.store.eventCount;
    open.close();
    expect(vault.exists, isTrue);
    expect(vault.keyringFile.readAsStringSync(), isNot(contains(recovery)));
    await expectLater(
      vault.create(password),
      fails(VaultProblem.alreadyExists),
    );

    final again = await vault.unlockWithPassword(password);
    expect(again.store.eventCount, events);
    expect(again.workspace, workspace);
    again.close();
    final recovered = await vault.unlockWithRecovery(recovery);
    expect(recovered.store.eventCount, events);
    recovered.close();
    await expectLater(
      vault.unlockWithPassword('wrong password here'),
      throwsA(wrongSecret),
    );
  });

  test('a changed password is saved; another ledger is refused', () async {
    final (open, _) = await vault.create(password);
    open.close();
    final changed = await open.keys.changePassword('a brand new password');
    await vault.save(changed);
    await expectLater(vault.unlockWithPassword(password), throwsA(wrongSecret));
    (await vault.unlockWithPassword('a brand new password')).close();

    final stranger = await codec.create(password);
    await expectLater(
      vault.save(stranger.unlocked),
      fails(VaultProblem.otherLedger),
    );
  });

  test('a device key opens the ledger without the password', () async {
    final device = FakeDeviceKey();
    final (open, _) = await vault.create(password);
    await openAccount(open);
    final events = open.store.eventCount;
    await open.updateKeys(await open.keys.addDevice('phone-1', device));
    expect(open.keys.keyring.deviceIds, ['phone-1']);
    open.close();

    final unlocked = await vault.unlockWithDevice('phone-1', device);
    expect(unlocked.store.eventCount, events);
    unlocked.close();
    await expectLater(
      vault.unlockWithDevice('phone-1', FakeDeviceKey()),
      throwsA(wrongSecret),
    );
  });

  test('a crash while replacing the keyring keeps a usable one', () async {
    final (open, _) = await vault.create(password);
    open.close();
    vault.keyringFile.renameSync('${vault.keyringFile.path}.new');
    expect(vault.exists, isTrue);
    (await vault.unlockWithPassword(password)).close();
    expect(vault.keyringFile.existsSync(), isTrue);

    // A crash while writing the very first keyring leaves half a file:
    // that is no ledger, so setup can run again.
    final fresh = LedgerVault(
      Directory('${directory.path}/fresh'),
      codec: codec,
    );
    fresh.directory.createSync();
    File('${fresh.directory.path}/keyring.json.new').writeAsStringSync('{"id');
    expect(fresh.exists, isFalse);
    await expectLater(
      fresh.unlockWithPassword(password),
      fails(VaultProblem.missing),
    );
    final (again, _) = await fresh.create(password);
    again.close();
    expect(fresh.exists, isTrue);

    vault.keyringFile.writeAsStringSync('{"broken": true}');
    await expectLater(
      vault.unlockWithPassword(password),
      fails(VaultProblem.damagedKeyring),
    );
  });

  test('a restored keyring opens a fresh database with its key', () async {
    final source = LedgerVault(
      Directory('${directory.path}/source'),
      codec: codec,
    );
    final (open, _) = await source.create(password);
    open.close();
    final header = await codec.unlockWithPassword(open.keys.keyring, password);

    final adopted = await vault.adopt(header);
    expect(adopted.store.eventCount, 0);
    expect(adopted.keys.databaseKey, open.keys.databaseKey);
    adopted.close();
    await expectLater(vault.adopt(header), fails(VaultProblem.alreadyExists));
  });
}
