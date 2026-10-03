import 'dart:io';
import 'dart:typed_data';

import 'package:accounts/accounts.dart';
import 'package:backup_security/backup_security.dart';
import 'package:bookkeeping/bookkeeping.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger_backup/ledger_backup.dart';
import 'package:ledger_sqlcipher/ledger_sqlcipher.dart';
import 'package:storage_sqlcipher/storage_sqlcipher.dart';
import 'package:test/test.dart';

const password = 'correct horse battery';
final twd = Currency.of('TWD');
final day = BusinessDate(2026, 10, 3);
final codec = KeyringCodec(kdf: PasswordKdf.insecureForTests);

Matcher fails(BackupProblem problem) => throwsA(
  isA<BackupException>().having((e) => e.problem, 'problem', problem),
);

/// The backup file split into its magic and frames, for tampering.
List<List<int>> frames(File file) {
  final bytes = file.readAsBytesSync();
  final out = <List<int>>[bytes.sublist(0, 8)];
  var at = 8;
  while (at < bytes.length) {
    final length = ByteData.sublistView(bytes, at, at + 4).getUint32(0);
    out.add(bytes.sublist(at + 4, at + 4 + length));
    at += 4 + length;
  }
  return out;
}

void writeFrames(File file, List<List<int>> parts) {
  final builder = BytesBuilder()..add(parts.first);
  for (final frame in parts.skip(1)) {
    builder
      ..add((ByteData(4)..setUint32(0, frame.length)).buffer.asUint8List())
      ..add(frame);
  }
  file.writeAsBytesSync(builder.toBytes());
}

void main() {
  late Directory directory;
  late SqlCipherStore source;
  late CreatedKeyring keys;
  final workspace = WorkspaceId(PublicId.generate());
  var stores = 0;

  OperationKey op() =>
      OperationKey(workspace, OperationId(PublicId.generate()));

  SqlCipherStore open() => SqlCipherStore.open(
    File('${directory.path}/store-${stores++}.db'),
    StorageKey.random(),
    modules: [ledgerSchema],
  );

  setUpAll(() async {
    keys = await codec.create(password);
  });

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('ledger-backup-');
    source = open();
    final books = Bookkeeping(LedgerStore(source));
    final cash = PublicId.generate();
    await books.openAccount(
      OpenAccount(
        operation: op(),
        accountId: cash,
        name: '現金',
        kind: AccountKind.cash,
        currency: twd,
        openedOn: day,
        openingBalance: Money(twd, BigInt.from(100000)),
        openingPostingId: PublicId.generate(),
      ),
    );
    for (var i = 1; i <= 30; i++) {
      await books.recordCashFlow(
        RecordCashFlow(
          operation: op(),
          postingId: PublicId.generate(),
          flow: CashFlow.expense,
          account: AccountRef(cash, 1),
          date: day,
          amount: Money(twd, BigInt.from(i * 100)),
        ),
      );
    }
  });

  tearDown(() {
    source.close();
    directory.deleteSync(recursive: true);
  });

  Future<File> backup({UnlockedKeyring? using, int chunkSize = 7}) async {
    final file = File('${directory.path}/backup-${stores++}.etb');
    await LedgerBackup.write(
      store: source,
      keys: using ?? keys.unlocked,
      file: file,
      backupId: PublicId.generate(),
      createdAt: UtcInstant(DateTime.utc(2026, 10, 3, 12)),
      chunkSize: chunkSize,
    );
    return file;
  }

  Future<SqlCipherStore> restore(File file, {UnlockedKeyring? using}) async {
    final header = await LedgerBackup.readHeader(file);
    final unlocked =
        using ?? await codec.unlockWithPassword(header.keyring, password);
    final target = open();
    addTearDown(target.close);
    await LedgerBackup.restore(
      file: file,
      keys: unlocked,
      into: LedgerStore(target),
    );
    return target;
  }

  test('a backup restores the same ledger on a new device', () async {
    final file = await backup();
    final header = await LedgerBackup.readHeader(file);
    expect(header.events, source.eventCount);
    expect(header.operations, source.operationCount);
    expect(header.lastSeq, source.eventCount);
    expect(header.keyring.id, keys.keyring.id);

    final target = await restore(file);
    expect(projectionRows(target), projectionRows(source));
    expect(target.operationCount, source.operationCount);
    expect(target.integrityCheck(), 'ok');
  });

  test('the recovery code opens a backup too', () async {
    final file = await backup();
    final header = await LedgerBackup.readHeader(file);
    final unlocked = await codec.unlockWithRecovery(
      header.keyring,
      keys.recoveryCode,
    );
    final target = await restore(file, using: unlocked);
    expect(target.eventCount, source.eventCount);
  });

  test('a rotated backup key still restores older backups', () async {
    final old = await backup();
    final rotated = await keys.unlocked.rotateBackupKey();
    final fresh = await backup(using: rotated);
    expect((await LedgerBackup.readHeader(fresh)).backupEpoch, 2);
    expect((await restore(old, using: rotated)).eventCount, source.eventCount);
    expect((await restore(fresh)).eventCount, source.eventCount);
  });

  test('altered, reordered or truncated backups are refused', () async {
    final file = await backup();
    final original = frames(file);
    expect(original.length, greaterThan(5));

    final flipped = [...original];
    flipped[3] = [...flipped[3]]..[20] ^= 1;
    writeFrames(file, flipped);
    await expectLater(restore(file), fails(BackupProblem.authenticationFailed));

    final swapped = [...original];
    final second = swapped[2];
    swapped[2] = swapped[3];
    swapped[3] = second;
    writeFrames(file, swapped);
    await expectLater(restore(file), fails(BackupProblem.authenticationFailed));

    writeFrames(file, original.sublist(0, original.length - 1));
    await expectLater(restore(file), fails(BackupProblem.invalidFormat));

    final header = String.fromCharCodes(original[1]);
    final edited = [...original];
    final last = '"lastSeq":${source.eventCount}';
    edited[1] = header.replaceFirst(last, '"lastSeq":99999').codeUnits;
    expect(String.fromCharCodes(edited[1]), isNot(header));
    writeFrames(file, edited);
    await expectLater(restore(file), fails(BackupProblem.authenticationFailed));
  });

  test('another ledger\'s keys and a non-empty target are refused', () async {
    final file = await backup();
    final stranger = await codec.create(password);
    final target = open();
    addTearDown(target.close);
    await expectLater(
      LedgerBackup.restore(
        file: file,
        keys: stranger.unlocked,
        into: LedgerStore(target),
      ),
      fails(BackupProblem.authenticationFailed),
    );
    await expectLater(
      LedgerBackup.restore(
        file: file,
        keys: keys.unlocked,
        into: LedgerStore(source),
      ),
      fails(BackupProblem.targetNotEmpty),
    );
  });

  test('a file that is not a backup is refused before any key', () async {
    final file = File('${directory.path}/notes.txt')
      ..writeAsStringSync('hello');
    await expectLater(
      LedgerBackup.readHeader(file),
      fails(BackupProblem.invalidFormat),
    );
  });
}
