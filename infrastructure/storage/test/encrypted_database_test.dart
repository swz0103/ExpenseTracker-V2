// The first run builds the crash worker, which can take a while.
@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:sqlite3/sqlite3.dart';
import 'package:storage/src/layout.dart';
import 'package:storage/storage.dart';
import 'package:test/test.dart';

/// The crash worker the "killed writer" test starts: built here when it is
/// missing or older than its source, the same way tooling/run-host-checks.ps1
/// does, so a plain `dart test` works on a clean checkout.
Future<void> _ensureCrashWorker() async {
  final suffix = Platform.isWindows ? '.exe' : '';
  final built = File('.dart_tool/worker/bundle/bin/crash_worker$suffix');
  final sources = [
    File('bin/crash_worker.dart'),
    for (final entity in Directory('lib').listSync(recursive: true))
      if (entity is File && entity.path.endsWith('.dart')) entity,
    File('pubspec.lock'),
  ];
  final newest = sources
      .map((f) => f.lastModifiedSync())
      .reduce((a, b) => a.isAfter(b) ? a : b);
  if (built.existsSync() && !built.lastModifiedSync().isBefore(newest)) return;
  final out = Directory('.dart_tool/build-crash_worker');
  final result = await Process.run(Platform.resolvedExecutable, [
    'build',
    'cli',
    '--target',
    'bin/crash_worker.dart',
    '--output',
    out.path,
  ]);
  if (result.exitCode != 0) {
    fail(
      'Could not build the crash worker (dart build cli, exit '
      '${result.exitCode}); the "killed writer" test needs it.\n'
      '${result.stdout}\n${result.stderr}',
    );
  }
  final bundle = Directory('.dart_tool/worker/bundle');
  if (bundle.existsSync()) bundle.deleteSync(recursive: true);
  bundle.createSync(recursive: true);
  await _copy(Directory('${out.path}/bundle'), bundle);
}

Future<void> _copy(Directory from, Directory to) async {
  for (final entity in from.listSync(recursive: true, followLinks: false)) {
    final relative = entity.path.substring(from.path.length + 1);
    final target = '${to.path}/$relative';
    if (entity is Directory) {
      Directory(target).createSync(recursive: true);
    } else if (entity is File) {
      Directory(target).parent.createSync(recursive: true);
      entity.copySync(target);
    }
  }
}

void main() {
  setUpAll(_ensureCrashWorker);

  late Directory directory;
  late File file;
  late StorageKey key;
  final opened = <EncryptedDatabase>[];

  EncryptedDatabase open([StorageKey? other]) {
    final store = EncryptedDatabase.open(file, other ?? key);
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

  test('a book read a page at a time holds every row once, in order', () {
    final store = open();
    store.write((w) {
      for (var i = 0; i < 23; i++) {
        w.put('entry', 'e$i', '{"n":$i}');
      }
    });
    final read = <String>[];
    var after = 0;
    for (;;) {
      final page = store.rowsAfter(after, limit: 5);
      if (page.isEmpty) break;
      expect(page.length, lessThanOrEqualTo(5));
      read.addAll(page.map((r) => r.id));
      after = page.last.seq;
    }
    expect(read, [for (final r in store.rows()) r.id]);
    expect(read, hasLength(23));
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
    database.userVersion = EncryptedDatabase.schema + 1;
    database.close();
    expect(
      () => open(),
      throwsA(const StorageUnavailable(StorageProblem.newerSchema)),
    );
  });

  test('a file is brought up by each layout step it lacks, once', () {
    open().close();
    final database = raw();
    addTearDown(database.close);
    expect(database.userVersion, EncryptedDatabase.schema);
    final ran = <int>[];
    // A later layout: two more steps after this build's own.
    final steps = [
      for (var n = 0; n < EncryptedDatabase.schema; n++)
        (Database db) => ran.add(n),
      (Database db) {
        ran.add(EncryptedDatabase.schema);
        db.execute('ALTER TABLE rows ADD COLUMN note TEXT');
      },
      (Database db) => ran.add(EncryptedDatabase.schema + 1),
    ];
    bringUpLayout(database, steps);
    // Only the steps the file lacked ran, and the file says so.
    expect(ran, [EncryptedDatabase.schema, EncryptedDatabase.schema + 1]);
    expect(database.userVersion, EncryptedDatabase.schema + 2);
    bringUpLayout(database, steps);
    expect(ran, hasLength(2));
  });

  test('a layout step that fails leaves the file as it was', () {
    open().close();
    final database = raw();
    addTearDown(database.close);
    expect(
      () => bringUpLayout(database, [
        for (var n = 0; n < EncryptedDatabase.schema; n++) (Database db) {},
        (Database db) => db.execute('ALTER TABLE rows ADD COLUMN note TEXT'),
        (Database db) => throw StateError('step 2 fails'),
      ]),
      throwsStateError,
    );
    expect(database.userVersion, EncryptedDatabase.schema);
    expect(
      database.select('PRAGMA table_info(rows)').map((r) => r['name']),
      isNot(contains('note')),
    );
  });

  test('numbers kept beside the records stay apart from the revision', () {
    final store = open();
    expect(store.meta('book'), isNull);
    store.write((w) => w.setMeta('book', 2), counts: false);
    expect(store.meta('book'), 2);
    store.write((w) => w.setMeta('book', 3), counts: false);
    expect(store.meta('book'), 3);
    expect(store.revision, 0);
    expect(
      () => store.write((w) => w.setMeta('revision', 9)),
      throwsArgumentError,
    );
    expect(store.revision, 0);
  });

  test('one record is found by its shelf and id', () {
    final store = open();
    store.write((w) {
      w.put('entry', 'e1', '{"category":"飲食"}');
      w.put('budget', 'e1', '{"limit":1}');
    });
    expect(store.row('entry', 'e1')!.body, '{"category":"飲食"}');
    expect(store.row('budget', 'e1')!.body, '{"limit":1}');
    expect(store.row('entry', 'nope'), isNull);
  });

  test('a ledger of the old event-journal format is told apart', () {
    final database = raw();
    database.execute('CREATE TABLE events (seq INTEGER PRIMARY KEY)');
    database.userVersion = 3;
    database.close();
    expect(
      () => open(),
      throwsA(const StorageUnavailable(StorageProblem.oldFormat)),
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
    // Fetched data is kept without counting as a change.
    store.write((w) => w.put('market', 'quotes', '{}'), counts: false);
    expect(store.revision, 2);
    expect(store.rows(shelf: 'market'), hasLength(1));
    store.write((w) => w.drop('market', 'quotes'));
    expect(store.revision, 3);
    store.close();
    final again = open();
    final rows = again.rows();
    expect(
      [for (final r in rows) (r.shelf, r.id, r.body)],
      [('entry', 'b', 'changed'), ('entry', 'a', '2')],
    );
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
    final store = EncryptedDatabase.open(file, key);
    expect(
      () => EncryptedDatabase.open(file, key),
      throwsA(const StorageUnavailable(StorageProblem.inUse)),
    );
    final port = ReceivePort();
    await Isolate.spawn(_openElsewhere, [port.sendPort, file.path, key.hex]);
    expect(await port.first, StorageProblem.inUse.name);
    store.close();
    EncryptedDatabase.open(file, key).close();
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
    EncryptedDatabase.open(
      file,
      StorageKey.fromHex(message[2] as String),
    ).close();
    reply.send(null);
  } on StorageUnavailable catch (error) {
    reply.send(error.problem.name);
  }
}
