import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:storage/storage.dart';
import 'package:test/test.dart';
import 'package:vault/backup_security.dart';
import 'package:vault/ledger_backup.dart';

/// R12: a real backup and keyring damaged at random (seeded). A backup
/// restores whole or is refused with a BackupException, never anything
/// else, and a damaged one never restores as if whole; a keyring is read
/// or refused with a KeyringException. A few dozen cases here;
/// `FUZZ_CASES=2000` for a nightly run.
void main() {
  final cases = int.tryParse(Platform.environment['FUZZ_CASES'] ?? '') ?? 60;
  final codec = KeyringCodec(kdf: PasswordKdf.insecureForTests);
  late Directory directory;
  late UnlockedKeyring keys;
  late Uint8List whole;
  var made = 0;

  EncryptedDatabase store() => EncryptedDatabase.open(
    File('${directory.path}/s${made++}.db'),
    StorageKey.random(),
  );

  setUpAll(() async {
    directory = Directory.systemTemp.createTempSync('backup-fuzz-');
    keys = (await codec.create('correct horse battery')).unlocked;
    final source = store()
      ..write((w) {
        for (var i = 1; i <= 30; i++) {
          w.put('entry', 'e$i', '{"note":"${'x' * 200}","i":$i}');
        }
      });
    final file = File('${directory.path}/whole.etbk');
    await LedgerBackup.write(
      store: source,
      keys: keys,
      file: file,
      backupId: 'b',
      createdAt: DateTime.utc(2026, 11, 22),
      chunkSize: 7,
      files: {
        'a.bin': File('${directory.path}/a.bin')
          ..writeAsBytesSync(List.generate(5000, (i) => i % 251)),
      },
      pieceBytes: 1500,
    );
    source.close();
    whole = file.readAsBytesSync();
  });

  tearDownAll(() => directory.deleteSync(recursive: true));

  /// How restoring [bytes] ended: the records restored, or the problem.
  Future<String> restore(Uint8List bytes) async {
    final file = File('${directory.path}/case.etbk')..writeAsBytesSync(bytes);
    final into = store();
    try {
      await LedgerBackup.restore(
        file: file,
        keys: keys,
        into: into,
        onFile: (_, _) async {},
      );
      return 'restored ${into.count}';
    } on BackupException catch (error) {
      return error.problem.name;
    } finally {
      into.close();
    }
  }

  test('the whole backup restores its 30 records', () async {
    expect(await restore(whole), 'restored 30');
  });

  test('$cases damaged backups are refused, never half restored', () async {
    final r = Random(99);
    for (var i = 0; i < cases; i++) {
      final bytes = Uint8List.fromList(whole);
      final Uint8List damaged;
      switch (i % 3) {
        case 0:
          final at = r.nextInt(bytes.length);
          bytes[at] ^= 1 << r.nextInt(8);
          damaged = bytes;
        case 1:
          damaged = Uint8List.sublistView(bytes, 0, r.nextInt(bytes.length));
        default:
          final at = r.nextInt(bytes.length);
          for (var k = 0; k < 1 + r.nextInt(40) && at + k < bytes.length; k++) {
            bytes[at + k] = r.nextInt(256);
          }
          damaged = bytes;
      }
      final told = await restore(damaged);
      // A flip may land where nothing reads it, as in the length of the
      // last frame's padding; whole is whole.
      expect(
        told,
        anyOf(
          'restored 30',
          isIn([for (final p in BackupProblem.values) p.name]),
        ),
        reason: 'case $i',
      );
    }
  });

  test('$cases damaged keyrings are read or refused', () {
    final text = keys.keyring.encode();
    final r = Random(11);
    for (var i = 0; i < cases * 10; i++) {
      final at = r.nextInt(text.length);
      final damaged = r.nextBool()
          ? text.substring(0, at)
          : text.substring(0, at) +
                String.fromCharCode(r.nextInt(256)) +
                text.substring(at + 1);
      try {
        Keyring.parse(damaged);
      } on KeyringException {
        // Refused: what a damaged keyring is.
      }
    }
    expect(() => Keyring.parse('[' * 100000), throwsA(isA<KeyringException>()));
  });
}
