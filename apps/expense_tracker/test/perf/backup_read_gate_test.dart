import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:storage/storage.dart';
import 'package:vault/backup_security.dart';
import 'package:vault/ledger_backup.dart';

/// A backup of a book of 100,000 records does not hold the screen still
/// (D41): the records are read, compressed and sealed on a worker isolate
/// (EncryptedDatabase.readApart). Measured as the longest the isolate is
/// held during the backup, against reading the same records here at once
/// as the backup did before, so it holds on any machine; the limit and how
/// it was measured are in thresholds.md (`backup_read_block`).
void main() {
  /// The longest the isolate may be held during the backup (the middle
  /// of five runs), as a share of the book read here at once: about three
  /// the worst measured. Read here, as before, it would be 1 or more.
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

      /// The longest the isolate was held while [work] ran, in ms.
      Future<int> held(Future<void> Function() work) async {
        final tick = Stopwatch()..start();
        var last = 0;
        var block = 0;
        final timer = Timer.periodic(const Duration(milliseconds: 1), (_) {
          final now = tick.elapsedMilliseconds;
          if (now - last > block) block = now - last;
          last = now;
        });
        await Future<void>.delayed(const Duration(milliseconds: 20));
        block = 0;
        last = tick.elapsedMilliseconds;
        await work();
        // The tick after the last hold, before the timer stops.
        await Future<void>.delayed(const Duration(milliseconds: 20));
        timer.cancel();
        return block;
      }

      Future<void> backUp(int n) => LedgerBackup.write(
        store: store,
        keys: keys,
        file: File('${dir.path}/b$n.etbk'),
        backupId: 'b$n',
        createdAt: DateTime.utc(2026, 11, 23),
      );

      // Warm up both, so neither is charged for compiling.
      store.rows();
      await backUp(0);
      // As the backup read before: every record here at once, then made
      // into the items it sends to the worker.
      final atOnce = await held(() async {
        final rows = store.rows();
        final items = [
          for (final row in rows) [row.shelf, row.id, row.body],
        ];
        expect(items, hasLength(100000));
      });
      // What is left held is the isolate group's garbage collection,
      // which the worker's allocations set off now and then: the middle
      // of five runs.
      final runs = [for (var n = 1; n <= 5; n++) await held(() => backUp(n))]
        ..sort();
      final apart = runs[2];
      final header = await LedgerBackup.readHeader(File('${dir.path}/b1.etbk'));
      expect(header.rows, 100000);
      final share = apart / atOnce;
      // ignore: avoid_print
      print(
        'backup_read_block: read here at once $atOnce ms held; '
        'backup apart $runs ms held, middle $apart; '
        'share ${share.toStringAsFixed(3)}',
      );
      expect(share, lessThanOrEqualTo(limit));
    } finally {
      store.close();
      dir.deleteSync(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
