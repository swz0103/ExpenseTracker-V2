import 'dart:io';

import 'package:storage/storage.dart';
import 'package:test/test.dart';

void main() {
  test('a write refused for want of room is told from other failures', () {
    FileSystemException failed(int code) =>
        FileSystemException('write', 'x', OSError('', code));
    // 28 is ENOSPC (Linux, Android), 112 ERROR_DISK_FULL (Windows).
    expect(isNoSpace(failed(28)), isTrue);
    expect(isNoSpace(failed(112)), isTrue);
    // 13 is EACCES: permission, not room.
    expect(isNoSpace(failed(13)), isFalse);
    expect(isNoSpace(const FileSystemException('write')), isFalse);
    expect(isNoSpace(StateError('disk full')), isFalse);
  });

  test('the database refused for want of room is told too (review 30)', () {
    // 13 is SQLITE_FULL; 13 | (1 << 8) = 269 an extended code of it.
    expect(
      isNoSpace(SqliteException(extendedResultCode: 13, message: 'full')),
      isTrue,
    );
    expect(
      isNoSpace(SqliteException(extendedResultCode: 269, message: 'full')),
      isTrue,
    );
    // 11 is SQLITE_CORRUPT: damage, not room.
    expect(
      isNoSpace(SqliteException(extendedResultCode: 11, message: 'bad')),
      isFalse,
    );
  });

  test('a database filled to its pageLimit is refused as a full disk '
      '(review 30)', () {
    final directory = Directory.systemTemp.createTempSync('no-space-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final store = EncryptedDatabase.open(
      File('${directory.path}/full.db'),
      StorageKey.random(),
      pageLimit: 16,
    );
    addTearDown(store.close);
    // 200 rows of 1000 characters need about 50 pages of 4096 bytes
    // more than the empty tables hold, and the cap is 16 or those.
    Object? refused;
    try {
      for (var i = 0; i < 200; i++) {
        store.write((w) => w.put('note', '$i', 'x' * 1000));
      }
    } on Object catch (error) {
      refused = error;
    }
    expect(refused, isA<SqliteException>());
    expect(isNoSpace(refused!), isTrue);
  });
}
