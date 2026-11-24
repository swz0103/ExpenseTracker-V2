/// A backup of a book of 100,000 records does not hold the screen still
/// (D41): the records are read, compressed and sealed on a worker isolate
/// (EncryptedDatabase.readApart). Measured as the longest the isolate is
/// held during the backup, against reading the same records here at once
/// as the backup did before, so it holds on any machine; judged on
/// interleaved pairs the host did not stall (held.dart, `shareOf`); the
/// limit and how it was measured are in thresholds.md
/// (`backup_read_block`).
@Tags(['timing'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:storage/storage.dart';
import 'package:vault/backup_security.dart';
import 'package:vault/ledger_backup.dart';

import '../support/held.dart';

void main() {
  /// The longest the isolate may be held during the backup (the median
  /// of the clean pairs), as a share of the book read here at once:
  /// about three times the worst measured. Read here, as before, it
  /// would be 1 or more.
  const limit = 0.2;

  const body =
      '{"id":"e","date":"2026-10-21","type":"expense","amount":120,'
      '"account":"0190f3c2-7e4b-7c1a-9d2e-3f4a5b6c7d8e","category":"飲食日常",'
      '"note":"lunch","_v":2,"_at":1761000000000}';

  test('a backup of 100,000 records holds the screen for a small share of '
      'reading them here', () async {
    final dir = Directory.systemTemp.createTempSync('backup-read-');
    final store = EncryptedDatabase.open(
      File('${dir.path}/l.db'),
      StorageKey.random(),
    );
    final keys = (await KeyringCodec(
      kdf: PasswordKdf.insecureForTests,
    ).create('correct horse battery')).unlocked;
    try {
      store.write((w) {
        for (var i = 0; i < 100000; i++) {
          w.put('entry', 'e$i', body);
        }
      });

      var n = 0;
      Future<Held<void>> backUp() {
        final at = n++;
        return timeHeld(
          () => LedgerBackup.write(
            store: store,
            keys: keys,
            file: File('${dir.path}/b$at.etbk'),
            backupId: 'b$at',
            createdAt: DateTime.utc(2026, 11, 23),
          ),
        );
      }

      // As the backup read before: every record here at once, then made
      // into the items it sends to the worker.
      Future<Held<void>> readHere() => timeHeld(() async {
        final rows = store.rows();
        final items = [
          for (final row in rows) [row.shelf, row.id, row.body],
        ];
        expect(items, hasLength(100000));
      });

      // Warm up both, so neither is charged for compiling.
      await readHere();
      await backUp();
      // What is left held is the isolate group's garbage collection,
      // which the worker's allocations set off now and then: the median
      // of interleaved pairs, the backup first in each.
      final result = await shareOf(
        apart: backUp,
        whole: readHere,
        limit: limit,
      );
      final header = await LedgerBackup.readHeader(File('${dir.path}/b1.etbk'));
      expect(header.rows, 100000);
      expectShare(result, 'backup_read_block');
    } finally {
      store.close();
      dir.deleteSync(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 6)));
}
