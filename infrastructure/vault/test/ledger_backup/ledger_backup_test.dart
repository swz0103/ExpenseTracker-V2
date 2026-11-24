import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart'
    show SecretBoxAuthenticationError;
import 'package:storage/storage.dart';
import 'package:test/test.dart';
import 'package:vault/backup_security.dart';
import 'package:vault/ledger_backup.dart';

const password = 'correct horse battery';
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
  late EncryptedDatabase source;
  late CreatedKeyring keys;
  var stores = 0;

  EncryptedDatabase open() => EncryptedDatabase.open(
    File('${directory.path}/store-${stores++}.db'),
    StorageKey.random(),
  );

  List<(String, String, String)> rowsOf(EncryptedDatabase store) => [
    for (final row in store.rows()) (row.shelf, row.id, row.body),
  ];

  setUpAll(() async {
    keys = await codec.create(password);
  });

  setUp(() {
    directory = Directory.systemTemp.createTempSync('ledger-backup-');
    source = open();
    source.write((w) {
      w.put('account', 'cash', '{"name":"現金","opening":100000}');
      for (var i = 1; i <= 30; i++) {
        w.put('entry', 'e$i', '{"amount":${i * 100},"note":"午餐 $i"}');
      }
    });
    // A changed record keeps its place.
    source.write((w) => w.put('entry', 'e1', '{"amount":1}'));
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
      backupId: 'b-${stores++}',
      createdAt: DateTime.utc(2026, 10, 3, 12),
      chunkSize: chunkSize,
    );
    return file;
  }

  Future<EncryptedDatabase> restore(
    File file, {
    UnlockedKeyring? using,
    void Function(String shelf, String id, String body)? accept,
  }) async {
    final header = await LedgerBackup.readHeader(file);
    final unlocked =
        using ??
        await codec.unlockWithRecovery(header.keyring, keys.recoveryCode);
    final target = open();
    addTearDown(target.close);
    await LedgerBackup.restore(
      file: file,
      keys: unlocked,
      into: target,
      accept: accept,
    );
    return target;
  }

  test('files ride along and come back by name', () async {
    final photo = File('${directory.path}/photo.bin')
      ..writeAsBytesSync(List.generate(5000, (i) => i % 251));
    final file = File('${directory.path}/with-files.etb');
    await LedgerBackup.write(
      store: source,
      keys: keys.unlocked,
      file: file,
      backupId: 'with-files',
      createdAt: DateTime.utc(2026, 10, 3, 12),
      files: {'lunch.etr': photo},
    );
    final header = await LedgerBackup.readHeader(file);
    final unlocked = await codec.unlockWithRecovery(
      header.keyring,
      keys.recoveryCode,
    );
    final target = open();
    addTearDown(target.close);
    final back = <String, List<int>>{};
    await LedgerBackup.restore(
      file: file,
      keys: unlocked,
      into: target,
      onFile: (name, bytes) async => back[name] = bytes,
    );
    expect(back.keys, ['lunch.etr']);
    expect(back['lunch.etr'], photo.readAsBytesSync());
    expect(rowsOf(target), rowsOf(source));
  });

  test('sealed files open only under their own name and ledger', () async {
    final box = await FileBox.derive(keys.unlocked, 'receipts');
    final sealed = await box.seal('a.etr', [1, 2, 3, 4]);
    expect(await box.open('a.etr', sealed), [1, 2, 3, 4]);
    await expectLater(
      box.open('b.etr', sealed),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
    final other = await FileBox.derive(
      (await codec.create(password)).unlocked,
      'receipts',
    );
    await expectLater(
      other.open('a.etr', sealed),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
    final again = await FileBox.derive(keys.unlocked, 'receipts');
    expect(await again.open('a.etr', sealed), [1, 2, 3, 4]);
  });

  test('a backup restores the same records, in order', () async {
    final file = await backup();
    final header = await LedgerBackup.readHeader(file);
    expect(header.rows, source.count);
    expect(header.revision, source.revision);
    expect(header.keyring.id, keys.keyring.id);
    expect(header.createdAt, DateTime.utc(2026, 10, 3, 12));

    final target = await restore(file);
    expect(rowsOf(target), rowsOf(source));
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
    expect(target.count, source.count);
  });

  test('a rotated backup key still restores older backups', () async {
    final old = await backup();
    final rotated = await keys.unlocked.rotateBackupKey();
    final fresh = await backup(using: rotated);
    expect((await LedgerBackup.readHeader(fresh)).backupEpoch, 2);
    expect((await restore(old, using: rotated)).count, source.count);
    expect((await restore(fresh)).count, source.count);
  });

  test('the header is read from the start of a backup alone, within its '
      'reach, and a start too short or not a backup is refused', () async {
    final old = await backup();
    final rotated = await keys.unlocked.rotateBackupKey();
    final fresh = await backup(using: rotated);
    final bytes = fresh.readAsBytesSync();
    // A keyring with two epochs still fits well inside the reach.
    final headerEnd = 8 + 4 + frames(fresh)[1].length;
    expect(headerEnd, lessThan(LedgerBackup.headerReach));
    final header = LedgerBackup.headerOf(bytes.sublist(0, headerEnd));
    expect(header.backupEpoch, 2);
    expect(header.keyring.id, keys.keyring.id);
    // More than the header, the whole file here, reads the same.
    expect(LedgerBackup.headerOf(old.readAsBytesSync()).backupEpoch, 1);
    expect(
      () => LedgerBackup.headerOf(bytes.sublist(0, headerEnd - 1)),
      fails(BackupProblem.invalidFormat),
    );
    expect(
      () => LedgerBackup.headerOf(bytes.sublist(0, 10)),
      fails(BackupProblem.invalidFormat),
    );
    expect(
      () => LedgerBackup.headerOf('hello, this is not a backup'.codeUnits),
      fails(BackupProblem.invalidFormat),
    );
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
    final rows = '"rows":${source.count}';
    edited[1] = header.replaceFirst(rows, '"rows":99999').codeUnits;
    expect(String.fromCharCodes(edited[1]), isNot(header));
    writeFrames(file, edited);
    await expectLater(restore(file), fails(BackupProblem.authenticationFailed));
  });

  test("another ledger's keys and a non-empty target are refused", () async {
    final file = await backup();
    final stranger = await codec.create(password);
    final target = open();
    addTearDown(target.close);
    await expectLater(
      LedgerBackup.restore(file: file, keys: stranger.unlocked, into: target),
      fails(BackupProblem.authenticationFailed),
    );
    await expectLater(
      LedgerBackup.restore(file: file, keys: keys.unlocked, into: source),
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

  test('a file over 4 GiB is refused before any of it is read (R12)', () async {
    expect(LedgerBackup.maxBackupBytes, 4294967296);
    // Sparse: one byte past the limit, taking no room on the disk.
    final file = File('${directory.path}/huge.etbk');
    final handle = file.openSync(mode: FileMode.write);
    handle
      ..setPositionSync(LedgerBackup.maxBackupBytes)
      ..writeByteSync(0)
      ..closeSync();
    await expectLater(
      LedgerBackup.readHeader(file),
      fails(BackupProblem.tooLarge),
    );
  });

  test('a newer format, a tail or an unknown epoch are refused', () async {
    final file = await backup();
    final original = frames(file);
    final header = String.fromCharCodes(original[1]);
    expect(header, contains('"version":5'));
    writeFrames(file, [
      original[0],
      header.replaceFirst('"version":5', '"version":6').codeUnits,
      ...original.skip(2),
    ]);
    await expectLater(
      LedgerBackup.readHeader(file),
      fails(BackupProblem.unsupportedVersion),
    );

    writeFrames(file, [...original, original[2]]);
    await expectLater(restore(file), fails(BackupProblem.invalidFormat));

    final rotated = await keys.unlocked.rotateBackupKey();
    final newer = await backup(using: rotated);
    await expectLater(
      restore(newer, using: keys.unlocked),
      fails(BackupProblem.authenticationFailed),
    );
  });

  test('a record the app cannot read fails the restore', () async {
    source.write((w) => w.put('entry', 'broken', 'not json'));
    final file = await backup();
    await expectLater(
      restore(
        file,
        accept: (shelf, id, body) {
          if (body == 'not json') throw const FormatException('unreadable');
        },
      ),
      fails(BackupProblem.invalidContent),
    );
  });
}
