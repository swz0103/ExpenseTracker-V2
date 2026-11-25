import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:core/app_core.dart';
import 'package:core/foundation_values.dart';
import 'package:domain/data_exchange.dart';
import 'package:expense_tracker/src/core/ledger/persistence/sql_ledger_data_source.dart';
import 'package:expense_tracker/src/core/platform/startup.dart';
import 'package:expense_tracker/src/core/platform/startup_state.dart';
import 'package:expense_tracker/src/core/time/app_clock.dart';
import 'package:expense_tracker/src/features/backup/model/encrypted_backup_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault/backup_security.dart';
import 'package:vault/ledger_backup.dart';
import 'package:vault/ledger_vault.dart';

/// What leaves the app through the phone's save dialog and comes in
/// through its file picker: a backup, a CSV, a photo, a file to import.
/// Each is written in `exports` only while it is handed over.
void main() {
  late Directory directory;
  late Startup startup;
  late EncryptedBackupManager backups;
  late List<(String, String)> handed;
  var accepts = true;
  String? picked;

  setUp(() async {
    AppClock.use(FixedClock(UtcInstant(DateTime.utc(2026, 10, 3, 4))));
    directory = Directory.systemTemp.createTempSync('hand-over-');
    startup = Startup(
      LedgerVault(
        directory,
        codec: KeyringCodec(kdf: PasswordKdf.insecureForTests),
      ),
      check: SqlLedgerDataSource.check,
    );
    await startup.setUp('correct horse battery');
    final vault = switch (startup.state) {
      Ready(:final vault) => vault,
      _ => throw StateError('Not open'),
    };
    handed = [];
    accepts = true;
    picked = null;
    backups = EncryptedBackupManager(
      startup,
      vault,
      export: (path, name) async {
        // What the save dialog is given, read while it is there.
        handed.add((name, File(path).readAsBytesSync().length.toString()));
        return accepts;
      },
      pick: () async => picked,
    );
  });

  tearDown(() {
    AppClock.reset();
    if (startup.state is Ready) startup.lock();
    directory.deleteSync(recursive: true);
  });

  bool exportsEmpty() {
    final exports = Directory('${directory.path}/exports');
    return !exports.existsSync() || exports.listSync().isEmpty;
  }

  test('a backup is handed over with its photos, then not kept', () async {
    // A photo does not shrink much, as a run of one byte would.
    final noise = Random(1);
    File('${directory.path}/receipts/a.jpg')
      ..createSync(recursive: true)
      ..writeAsBytesSync(List.generate(3000, (_) => noise.nextInt(256)));
    expect(await backups.exportBackup(), isTrue);
    final (name, size) = handed.single;
    expect(name, startsWith('記帳本-20261003'));
    expect(name, endsWith('.etbk'));
    expect(int.parse(size), greaterThan(3000));
    expect(exportsEmpty(), isTrue);

    accepts = false;
    expect(await backups.exportBackup(), isFalse);
    expect(exportsEmpty(), isTrue);
  });

  test('a CSV and a picture go out as they are', () async {
    const csv = '日期,金額\n';
    expect(await backups.exportFile('紀錄.csv', csv), isTrue);
    expect(await backups.exportBytes('圖.png', [1, 2, 3]), isTrue);
    expect(handed, [('紀錄.csv', '${utf8.encode(csv).length}'), ('圖.png', '3')]);
    expect(exportsEmpty(), isTrue);
  });

  test('a file chosen to import is read, and its copy let go', () async {
    expect(await backups.readFile(), isNull, reason: 'nothing chosen');
    final copy = File('${directory.path}/picked.csv')
      ..writeAsStringSync('日期,金額');
    picked = copy.path;
    final read = await backups.readFile();
    expect((read! as TextRead).text, '日期,金額');
    expect(copy.existsSync(), isFalse);
  });

  test('a file chosen in Big5 is read as Big5; one of neither is said to '
      'be unreadable (N4)', () async {
    // 日期 in Big5 (cp950): A4 E9, B4 C1.
    final big5 = File('${directory.path}/big5.csv')
      ..writeAsBytesSync([0xA4, 0xE9, 0xB4, 0xC1]);
    picked = big5.path;
    final read = await backups.readFile();
    expect(read, isA<TextRead>());
    final text = read! as TextRead;
    expect((text.text, text.encoding), ('日期', TextEncoding.big5));
    final junk = File('${directory.path}/junk.bin')
      ..writeAsBytesSync([0x80, 0x81]);
    picked = junk.path;
    expect(await backups.readFile(), isA<TextUnreadable>());
    expect(junk.existsSync(), isFalse);
  });

  test('a backup lent to a job is gone once it is done', () async {
    late File lent;
    final header = await backups.withBackup((file) async {
      lent = file;
      return LedgerBackup.readHeader(file);
    }, withPhotos: false);
    expect(header.revision, backups.revision);
    expect(lent.existsSync(), isFalse);
    expect(backups.ledgerId, isNotEmpty);

    // Gone even when the job fails.
    await expectLater(
      backups.withBackup<void>((file) async {
        lent = file;
        throw const FileSystemException('upload cut');
      }),
      throwsA(isA<FileSystemException>()),
    );
    expect(lent.existsSync(), isFalse);
  });

  test('a recovery code is given once', () async {
    expect(backups.recoveryGiven, isFalse);
    await backups.newRecoveryCode();
    expect(backups.recoveryGiven, isTrue);
  });
}
