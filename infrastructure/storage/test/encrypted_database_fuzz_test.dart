import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:storage/storage.dart';
import 'package:test/test.dart';

/// R12 F8 (D94): a ledger file damaged at random (seeded), opened with
/// the key its keyring vouches for and read through. It opens and reads,
/// or it is told as damaged: never a raw SQLite error, never "wrong key",
/// never a new empty book. A few dozen cases here; `FUZZ_CASES=600` for a
/// nightly run.
void main() {
  final cases = int.tryParse(Platform.environment['FUZZ_CASES'] ?? '') ?? 40;
  late Directory directory;
  late StorageKey key;
  late Uint8List original;

  setUpAll(() {
    directory = Directory.systemTemp.createTempSync('damaged-');
    key = StorageKey.random();
    final file = File('${directory.path}/whole.db');
    EncryptedDatabase.open(file, key)
      ..write((w) {
        for (var i = 0; i < 3000; i++) {
          w.put('entry', 'e$i', '{"id":"e$i","note":"${'n' * 100}"}');
        }
      })
      ..close();
    original = file.readAsBytesSync();
  });

  tearDownAll(() => directory.deleteSync(recursive: true));

  var made = 0;

  /// How opening and reading [bytes] ended: `ok`, or the problem told.
  String outcome(Uint8List bytes) {
    final file = File('${directory.path}/case${made++}.db')
      ..writeAsBytesSync(bytes);
    EncryptedDatabase? store;
    try {
      store = EncryptedDatabase.open(file, key, keyVouched: true);
      store.count;
      store.rows();
      store.integrityCheck();
      return 'ok';
    } on StorageUnavailable catch (error) {
      return error.problem.name;
    } finally {
      store?.close();
    }
  }

  test('$cases damaged files: opened, or told as damaged', () {
    final r = Random(321);
    final seen = <String>{};
    void expectTold(String what, Uint8List bytes) {
      final told = outcome(bytes);
      seen.add(told);
      expect(told, anyOf('ok', 'damaged'), reason: what);
    }

    expectTold('no bytes', Uint8List(0));
    expectTold('16 bytes', Uint8List(16));
    expectTold('a text file', Uint8List.fromList('日期,金額\n'.codeUnits));
    for (var i = 0; i < cases; i++) {
      final bytes = Uint8List.fromList(original);
      switch (i % 4) {
        case 0:
          final at = r.nextInt(bytes.length);
          bytes[at] ^= 1 << r.nextInt(8);
          expectTold('a bit flipped at $at', bytes);
        case 1:
          final page = r.nextInt(bytes.length ~/ EncryptedDatabase.pageSize);
          bytes.fillRange(
            page * EncryptedDatabase.pageSize,
            (page + 1) * EncryptedDatabase.pageSize,
            0,
          );
          expectTold('page $page zeroed', bytes);
        case 2:
          final length = r.nextInt(bytes.length);
          expectTold('cut to $length', bytes.sublist(0, length));
        default:
          final at = r.nextInt(100);
          bytes[at] = r.nextInt(256);
          expectTold('header byte $at', bytes);
      }
    }
    expect(seen, contains('damaged'));
  }, timeout: const Timeout(Duration(minutes: 10)));
}
