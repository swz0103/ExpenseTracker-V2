import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:storage/storage.dart';
import 'package:test/test.dart';
import 'package:vault/backup_security.dart';
import 'package:vault/ledger_backup.dart';

const password = 'correct horse battery';
final codec = KeyringCodec(kdf: PasswordKdf.insecureForTests);

Matcher fails(BackupProblem problem) => throwsA(
  isA<BackupException>().having((e) => e.problem, 'problem', problem),
);

/// The magic, then the frames of a backup file.
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

/// [file] with its header frame replaced by [header].
void withHeader(File file, Map<String, Object?> header) {
  final parts = frames(file);
  final builder = BytesBuilder()..add(parts.first);
  for (final frame in [utf8.encode(jsonEncode(header)), ...parts.skip(2)]) {
    builder
      ..add((ByteData(4)..setUint32(0, frame.length)).buffer.asUint8List())
      ..add(frame);
  }
  file.writeAsBytesSync(builder.toBytes());
}

Map<String, Object?> headerOf(File file) =>
    jsonDecode(utf8.decode(frames(file)[1])) as Map<String, Object?>;

/// D26 and D41: version 5 carries the book's version and the store's
/// layout, and the records are read in one read on a worker.
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
    directory = Directory.systemTemp.createTempSync('backup-v5-');
    source = open();
    source.write((w) {
      for (var i = 1; i <= 3; i++) {
        w.put('entry', 'e$i', '{"amount":$i}');
      }
    });
  });

  tearDown(() {
    source.close();
    directory.deleteSync(recursive: true);
  });

  Future<File> write() async {
    final file = File('${directory.path}/backup-${n++}.etbk');
    await LedgerBackup.write(
      store: source,
      keys: keys.unlocked,
      file: file,
      backupId: 'b',
      createdAt: DateTime.utc(2026, 11, 23, 9),
    );
    return file;
  }

  test('the header carries the book\'s version and the layout', () async {
    source.write(
      (w) => w.setMeta(EncryptedDatabase.bookVersionKey, 2),
      counts: false,
    );
    final file = await write();
    final header = await LedgerBackup.readHeader(file);
    expect(header.version, 5);
    expect(header.book, 2);
    expect(header.layout, 1);
    expect(header.rows, 3);
    expect(header.revision, 1);
    expect(headerOf(file).keys.toSet(), {
      'format',
      'version',
      'backupId',
      'createdAt',
      'keyring',
      'backupEpoch',
      'revision',
      'rows',
      'book',
      'layout',
    });
  });

  test('a book that has no version is written as null', () async {
    final file = await write();
    expect(headerOf(file)['book'], isNull);
    expect((await LedgerBackup.readHeader(file)).book, isNull);
  });

  test('the key set is exact for each version', () async {
    final file = await write();
    final header = headerOf(file);
    // Version 5 without its layout, or with a key more: refused.
    withHeader(file, {...header}..remove('layout'));
    await expectLater(
      LedgerBackup.readHeader(file),
      fails(BackupProblem.invalidFormat),
    );
    withHeader(file, {...header, 'extra': 1});
    await expectLater(
      LedgerBackup.readHeader(file),
      fails(BackupProblem.invalidFormat),
    );
    // Version 4 never carried them.
    withHeader(file, {...header, 'version': 4});
    await expectLater(
      LedgerBackup.readHeader(file),
      fails(BackupProblem.invalidFormat),
    );
    withHeader(
      file,
      {...header, 'version': 4}
        ..removeWhere((key, _) => key == 'book' || key == 'layout'),
    );
    expect((await LedgerBackup.readHeader(file)).version, 4);
    // A layout that is not a number.
    withHeader(file, {...header, 'layout': 'one'});
    await expectLater(
      LedgerBackup.readHeader(file),
      fails(BackupProblem.invalidFormat),
    );
  });

  test('a restore keeps the book\'s version', () async {
    source.write(
      (w) => w.setMeta(EncryptedDatabase.bookVersionKey, 2),
      counts: false,
    );
    final file = await write();
    final into = open();
    addTearDown(into.close);
    await LedgerBackup.restore(file: file, keys: keys.unlocked, into: into);
    expect(into.count, 3);
    expect(into.meta(EncryptedDatabase.bookVersionKey), 2);
  });

  test(
    'the journal of postings stays out of a backup: restored, the book '
    'has none, nor its mark, and is posted afresh at its first opening',
    () async {
      source.journal.keepMark((rules: 1, revision: source.revision));
      final file = await write();
      final into = open();
      addTearDown(into.close);
      await LedgerBackup.restore(file: file, keys: keys.unlocked, into: into);
      expect(into.count, 3);
      expect(into.journal.mark, isNull);
      expect(into.journal.intentCount, 0);
    },
  );

  test('a backup of a book with no version restores none', () async {
    final file = await write();
    final into = open();
    addTearDown(into.close);
    await LedgerBackup.restore(file: file, keys: keys.unlocked, into: into);
    expect(into.meta(EncryptedDatabase.bookVersionKey), isNull);
  });

  test('a backup of a later layout is refused', () async {
    final file = await write();
    // The header is bound to every chunk: only the header is checked
    // here, before any chunk is opened.
    withHeader(file, {
      ...headerOf(file),
      'layout': EncryptedDatabase.schema + 1,
    });
    final into = open();
    addTearDown(into.close);
    await expectLater(
      LedgerBackup.restore(file: file, keys: keys.unlocked, into: into),
      fails(BackupProblem.unsupportedVersion),
    );
    expect(into.count, 0);
  });

  test('a write asked for while the backup reads lands after it: the '
      'backup is the book as it stood', () async {
    source.write((w) {
      for (var i = 0; i < 20000; i++) {
        w.put('entry', 'n$i', '{"amount":$i}');
      }
    });
    // 3 + 20,000 rows at revision 2.
    final writing = write();
    // The store is held while the records are read.
    expect(source.busyApart, isTrue);
    expect(
      () => source.write((w) => w.put('entry', 'late', '{}')),
      throwsStateError,
    );
    final late = () async {
      while (source.busyApart) {
        await source.idle;
      }
      source.write((w) => w.put('entry', 'late', '{}'));
    }();
    final file = await writing;
    await late;
    final header = await LedgerBackup.readHeader(file);
    expect(header.rows, 20003);
    expect(header.revision, 2);
    final into = open();
    addTearDown(into.close);
    await LedgerBackup.restore(file: file, keys: keys.unlocked, into: into);
    expect(into.count, 20003);
    expect(into.row('entry', 'late'), isNull);
    // The write that waited is kept: 20,004 rows at revision 3.
    expect(source.count, 20004);
    expect(source.revision, 3);
  });
}
