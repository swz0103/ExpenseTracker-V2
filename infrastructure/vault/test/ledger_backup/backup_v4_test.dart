import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:storage/storage.dart';
import 'package:test/test.dart';
import 'package:vault/backup_security.dart';
import 'package:vault/ledger_backup.dart';

const password = 'correct horse battery';
const passphrase = 'a passphrase for backups';
final codec = KeyringCodec(kdf: PasswordKdf.insecureForTests);

Matcher fails(BackupProblem problem) => throwsA(
  isA<BackupException>().having((e) => e.problem, 'problem', problem),
);

/// The frames of a backup file after its 8-byte magic.
List<Uint8List> frames(File file) {
  final bytes = file.readAsBytesSync();
  final out = <Uint8List>[];
  var at = 8;
  while (at < bytes.length) {
    final length = ByteData.sublistView(bytes, at, at + 4).getUint32(0);
    out.add(bytes.sublist(at + 4, at + 4 + length));
    at += 4 + length;
  }
  return out;
}

void main() {
  late Directory directory;
  late EncryptedDatabase source;
  late CreatedKeyring keys;
  var n = 0;

  EncryptedDatabase open() => EncryptedDatabase.open(
    File('${directory.path}/store-${n++}.db'),
    StorageKey.random(),
  );

  setUpAll(() async => keys = await codec.create(password));

  setUp(() {
    directory = Directory.systemTemp.createTempSync('backup-v4-');
    source = open();
    source.write((w) {
      for (var i = 1; i <= 10; i++) {
        w.put('entry', 'e$i', '{"note":"${'x' * 1000}"}');
      }
    });
  });

  tearDown(() {
    source.close();
    directory.deleteSync(recursive: true);
  });

  Future<File> write({
    UnlockedKeyring? using,
    Map<String, File> files = const {},
    int pieceBytes = LedgerBackup.pieceBytes,
    int chunkBytes = LedgerBackup.chunkBytes,
  }) async {
    final file = File('${directory.path}/backup-${n++}.etbk');
    await LedgerBackup.write(
      store: source,
      keys: using ?? keys.unlocked,
      file: file,
      backupId: 'b',
      createdAt: DateTime.utc(2026, 11, 22, 9),
      files: files,
      pieceBytes: pieceBytes,
      chunkBytes: chunkBytes,
    );
    return file;
  }

  test('a backup carries no app password slot (SEC-02)', () async {
    final file = await write();
    final header = await LedgerBackup.readHeader(file);
    expect(header.version, 5);
    expect(header.keyring.hasPassword, isFalse);
    final plain = utf8.decode(frames(file).first);
    final keyring = jsonDecode(
      (jsonDecode(plain) as Map<String, Object?>)['keyring']! as String,
    );
    expect((keyring as Map<String, Object?>)['password'], isNull);
    await expectLater(
      codec.unlockWithPassword(header.keyring, password),
      throwsA(const KeyringException(KeyringError.noSuchSlot)),
    );
    final opened = await codec.unlockWithRecovery(
      header.keyring,
      keys.recoveryCode,
    );
    final into = open();
    addTearDown(into.close);
    await LedgerBackup.restore(file: file, keys: opened, into: into);
    expect(into.count, 10);
  });

  test('a backup passphrase, when set, opens the backup too', () async {
    final withPassphrase = await keys.unlocked.setPassphrase(passphrase);
    final file = await write(using: withPassphrase);
    final header = await LedgerBackup.readHeader(file);
    expect(header.keyring.hasPassphrase, isTrue);
    final opened = await codec.unlockWithPassphrase(header.keyring, passphrase);
    final into = open();
    addTearDown(into.close);
    await LedgerBackup.restore(file: file, keys: opened, into: into);
    expect(into.count, 10);
  });

  test('a version 4 header holding a password slot is refused', () async {
    final file = await write();
    final parts = frames(file);
    final header = jsonDecode(utf8.decode(parts.first)) as Map<String, Object?>;
    final forged = {...header, 'keyring': keys.keyring.encode()};
    final bytes = BytesBuilder()
      ..add(file.readAsBytesSync().sublist(0, 8))
      ..add(_length(utf8.encode(jsonEncode(forged))))
      ..add(utf8.encode(jsonEncode(forged)));
    for (final frame in parts.skip(1)) {
      bytes
        ..add(_length(frame))
        ..add(frame);
    }
    file.writeAsBytesSync(bytes.toBytes());
    await expectLater(
      LedgerBackup.readHeader(file),
      fails(BackupProblem.invalidFormat),
    );
  });

  test('a large file is split into pieces and comes back whole '
      '(SEC-11)', () async {
    final random = Random(7);
    // 100,000 random bytes in pieces of 16,384: 6 whole pieces (98,304)
    // and one of 1,696.
    final photo = File(
      '${directory.path}/photo.bin',
    )..writeAsBytesSync([for (var i = 0; i < 100000; i++) random.nextInt(256)]);
    final small = File('${directory.path}/small.bin')
      ..writeAsBytesSync([1, 2, 3]);
    final file = await write(
      files: {'big.etr': photo, 'small.etr': small},
      pieceBytes: 16384,
    );
    // Header, 1 chunk of records, 7 + 1 pieces, the end.
    expect(frames(file), hasLength(1 + 1 + 8 + 1));
    final header = await LedgerBackup.readHeader(file);
    final opened = await codec.unlockWithRecovery(
      header.keyring,
      keys.recoveryCode,
    );
    final into = open();
    addTearDown(into.close);
    final back = <String, List<int>>{};
    await LedgerBackup.restore(
      file: file,
      keys: opened,
      into: into,
      onFile: (name, bytes) async => back[name] = bytes,
    );
    expect(back.keys, ['big.etr', 'small.etr']);
    expect(back['big.etr'], photo.readAsBytesSync());
    expect(back['small.etr'], [1, 2, 3]);
  });

  test('records are cut into chunks by their size too', () async {
    // A record is 5 (entry) + 2 (e1) + 1,011 (the body) = 1,018 units,
    // e10 1,019. At most 3,100 a chunk: 3 records (3,054), 3, 3, then 1.
    final file = await write(chunkBytes: 3100);
    expect(frames(file), hasLength(1 + 4 + 1));
    final header = await LedgerBackup.readHeader(file);
    final opened = await codec.unlockWithRecovery(
      header.keyring,
      keys.recoveryCode,
    );
    final into = open();
    addTearDown(into.close);
    await LedgerBackup.restore(file: file, keys: opened, into: into);
    expect(into.count, 10);
  });

  test('the writer keeps every frame within what the reader takes', () {
    // A piece of 16 MiB is 21.3 MiB of base64, and 8 Mi units of record
    // text at most 48 MiB of JSON: under the 64 MiB a frame may hold.
    expect(LedgerBackup.pieceBytes * 4 ~/ 3, lessThan(LedgerBackup.maxFrame));
    expect(LedgerBackup.chunkBytes * 6, lessThan(LedgerBackup.maxFrame));
  });

  test('a version 4 backup, written before version 5, still restores '
      '(D26)', () async {
    // Written by the format code as it was at version 4: six records, the
    // book's meta at 2 (which version 4 did not carry), one photo.
    final file = File('test/ledger_backup/fixtures/v4.etbk');
    final header = await LedgerBackup.readHeader(file);
    expect(header.version, 4);
    expect(header.rows, 6);
    expect(header.book, isNull);
    expect(header.layout, isNull);
    final opened = await codec.unlockWithPassphrase(
      header.keyring,
      'fixture passphrase',
    );
    final into = open();
    addTearDown(into.close);
    final files = <String, List<int>>{};
    await LedgerBackup.restore(
      file: file,
      keys: opened,
      into: into,
      onFile: (name, bytes) async => files[name] = bytes,
    );
    expect(
      [for (final r in into.rows()) r.id],
      ['cash', 'e1', 'e2', 'e3', 'e4', 'e5'],
    );
    expect(into.row('entry', 'e3')?.body, '{"amount":300,"note":"午餐 3"}');
    expect(files, {
      'r1.etr': [1, 2, 3, 4],
    });
    // Version 4 carried no book version: none is restored, and the app
    // brings the book up as it opens.
    expect(into.meta(EncryptedDatabase.bookVersionKey), isNull);
  });
}

List<int> _length(List<int> bytes) =>
    (ByteData(4)..setUint32(0, bytes.length)).buffer.asUint8List();
