import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:sqlite3/sqlite3.dart';
import 'package:storage/storage.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late File file;
  late StorageKey key;
  final opened = <RowStore>[];

  RowStore open([StorageKey? other]) {
    final store = RowStore.open(file, other ?? key);
    opened.add(store);
    return store;
  }

  Database raw() {
    final database = sqlite3.open(file.path);
    database.execute('PRAGMA key = "x\'${key.hex}\'"');
    return database;
  }

  setUp(() {
    directory = Directory.systemTemp.createTempSync('row-store-');
    file = File('${directory.path}/ledger.db');
    key = StorageKey.random();
  });

  tearDown(() {
    for (final store in opened) {
      store.close();
    }
    opened.clear();
    directory.deleteSync(recursive: true);
  });

  test('a new store is encrypted, empty and in WAL mode', () {
    final store = open();
    expect(store.journalMode, 'wal');
    expect(store.integrityCheck(), 'ok');
    expect(store.count, 0);
    expect(store.revision, 0);
    store.close();
    final header = file.readAsBytesSync().sublist(0, 15);
    expect(String.fromCharCodes(header), isNot('SQLite format 3'));
  });

  test('the storage key never appears in its description', () {
    expect('$key', isNot(contains(key.hex)));
    expect(StorageKey.fromHex(key.hex).hex, key.hex);
    expect(() => StorageKey.fromHex('00'), throwsArgumentError);
    expect(() => StorageKey([1, 2, 3]), throwsArgumentError);
  });

  test('a wrong key is reported without leaking the error', () {
    open().close();
    expect(
      () => open(StorageKey.random()),
      throwsA(const StorageUnavailable(StorageProblem.wrongKey)),
    );
  });

  test('a file from a newer build is refused', () {
    open().close();
    final database = raw();
    database.userVersion = RowStore.schema + 1;
    database.close();
    expect(
      () => open(),
      throwsA(const StorageUnavailable(StorageProblem.newerSchema)),
    );
  });

  test('records keep their first place when changed, and survive', () {
    final store = open();
    store.write((w) {
      w.put('entry', 'b', '1');
      w.put('entry', 'a', '2');
      w.put('account', 'x', '3');
    });
    store.write((w) {
      w.put('entry', 'b', 'changed');
      w.drop('account', 'x');
      w.drop('account', 'missing');
    });
    expect(store.revision, 2);
    store.close();
    final again = open();
    final rows = again.rows();
    expect([for (final r in rows) (r.shelf, r.id, r.body)], [
      ('entry', 'b', 'changed'),
      ('entry', 'a', '2'),
    ]);
    expect(again.rows(shelf: 'account'), isEmpty);
    expect(again.count, 2);
  });

  test('a write that throws keeps nothing', () {
    final store = open();
    expect(
      () => store.write((w) {
        w.put('entry', 'a', '1');
        throw const FormatException('refused');
      }),
      throwsA(isA<FormatException>()),
    );
    expect(store.count, 0);
    expect(store.revision, 0);
  });

  test('only one connection, isolate or process owns the file', () async {
    final store = RowStore.open(file, key);
    expect(
      () => RowStore.open(file, key),
      throwsA(const StorageUnavailable(StorageProblem.inUse)),
    );
    final port = ReceivePort();
    await Isolate.spawn(_openElsewhere, [port.sendPort, file.path, key.hex]);
    expect(await port.first, StorageProblem.inUse.name);
    store.close();
    RowStore.open(file, key).close();
  });

  test('a killed writer never leaves half a write', () async {
    final suffix = Platform.isWindows ? '.exe' : '';
    final worker = File('.dart_tool/worker/bundle/bin/crash_worker$suffix');
    final random = Random(20261021);
    var acknowledged = 0;
    for (var round = 0; round < 8; round++) {
      final stopAfter = 1 + random.nextInt(40);
      final process = await Process.start(worker.absolute.path, [
        file.path,
        key.hex,
        '100000',
      ]);
      final lines = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      var seen = 0;
      await for (final line in lines) {
        acknowledged = int.parse(line.split(' ').last);
        if (++seen == stopAfter) {
          process.kill(ProcessSignal.sigkill);
          break;
        }
      }
      await process.exitCode;
      final store = open();
      expect(store.integrityCheck(), 'ok');
      final entries = store.rows(shelf: 'entry').length;
      expect(store.rows(shelf: 'pair').length, entries);
      expect(entries, greaterThanOrEqualTo(acknowledged));
      store.close();
      opened.remove(store);
    }
  });

  test('ten thousand records write and load quickly', () {
    final store = open();
    const body =
        '{"date":"2026-10-21T00:00:00.000Z","type":"expense","amount":120,'
        '"account":"0190f3c2-7e4b-7c1a-9d2e-3f4a5b6c7d8e","note":"lunch"}';
    final watch = Stopwatch()..start();
    store.write((w) {
      for (var i = 0; i < 10000; i++) {
        w.put('entry', 'e$i', body);
      }
    });
    final written = watch.elapsed;
    watch.reset();
    expect(store.rows(shelf: 'entry'), hasLength(10000));
    final read = watch.elapsed;
    expect(written, lessThan(const Duration(seconds: 5)));
    expect(read, lessThan(const Duration(seconds: 2)));
  });
}

/// Opens the store from another isolate and reports why it could not.
void _openElsewhere(List<Object> message) {
  final reply = message[0] as SendPort;
  final file = File(message[1] as String);
  try {
    RowStore.open(file, StorageKey.fromHex(message[2] as String)).close();
    reply.send(null);
  } on StorageUnavailable catch (error) {
    reply.send(error.problem.name);
  }
}
