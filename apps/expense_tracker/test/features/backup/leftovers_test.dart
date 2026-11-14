import 'dart:io';

import 'package:expense_tracker/src/features/backup/model/leftovers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory files;
  late Directory cache;

  setUp(() {
    files = Directory.systemTemp.createTempSync('files-');
    cache = Directory.systemTemp.createTempSync('cache-');
  });
  tearDown(() {
    files.deleteSync(recursive: true);
    cache.deleteSync(recursive: true);
  });

  File make(Directory folder, String path, {DateTime? at}) {
    final file = File('${folder.path}/$path')
      ..createSync(recursive: true)
      ..writeAsStringSync('plain');
    if (at != null) file.setLastModifiedSync(at);
    return file;
  }

  test('plain copies left by a stopped run are deleted', () async {
    final now = DateTime(2026, 10, 27, 12);
    final export = make(files, 'exports/記帳本.etbk');
    final ready = make(cache, 'receipt-ready.jpg');
    final restore = make(cache, 'restore.etbk');
    final camera = make(
      cache,
      'camera/receipt.jpg',
      at: now.subtract(const Duration(hours: 1)),
    );
    final ledger = make(files, 'ledger.db');
    // Android's backup takes all of cloud/: only its one copy stays.
    final copy = make(files, 'cloud/記帳本.etbk');
    final half = make(files, 'cloud/記帳本-20261027-120000000.etbk');
    await clearLeftovers(files, cache: cache, now: now);
    expect(copy.existsSync(), isTrue);
    for (final gone in [export, ready, restore, camera, half]) {
      expect(gone.existsSync(), isFalse, reason: gone.path);
    }
    expect(ledger.existsSync(), isTrue);
  });

  test("a photo taken while the app was closed waits a day", () async {
    final now = DateTime(2026, 10, 27, 12);
    final fresh = make(
      cache,
      'receipt-leftover.jpg',
      at: now.subtract(const Duration(hours: 2)),
    );
    await clearLeftovers(files, cache: cache, now: now);
    expect(fresh.existsSync(), isTrue);
    fresh.setLastModifiedSync(now.subtract(const Duration(days: 2)));
    await clearLeftovers(files, cache: cache, now: now);
    expect(fresh.existsSync(), isFalse);
  });
}
