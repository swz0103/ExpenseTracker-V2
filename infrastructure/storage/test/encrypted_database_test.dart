// The first run builds the crash worker, which can take a while.
@Timeout(Duration(minutes: 5))
library;

import 'dart:async';
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
    expect(store.isOpen, isTrue);
    store.close();
    expect(store.isOpen, isFalse);
    final header = file.readAsBytesSync().sublist(0, 15);
    expect(String.fromCharCodes(header), isNot('SQLite format 3'));
  });

  test('the first write kept is told once (D102)', () async {
    var told = 0;
    final store = EncryptedDatabase.open(file, key, written: () => told++);
    opened.add(store);
    expect(told, 0, reason: 'opening writes no record');
    store.write((w) => w.put('entry', 'a', '{}'));
    expect(told, 1);
    store.write((w) => w.put('entry', 'b', '{}'));
    await store.writeApart([RowChange.put('entry', 'c', '{}')]);
    expect(told, 1);
    store.close();
    // Through a write apart first, on another opening.
    var apart = 0;
    final again = EncryptedDatabase.open(file, key, written: () => apart++);
    opened.add(again);
    await again.writeApart([RowChange.put('entry', 'd', '{}')]);
    expect(apart, 1);
  });

  test('a write is kept, never thrown, when what it tells of it throws; '
      'told again at the next write (review 18)', () async {
    var tries = 0;
    final failed = <Object>[];
    final store = EncryptedDatabase.open(
      file,
      key,
      written: () {
        tries++;
        if (tries < 3) throw const FileSystemException('disk full');
      },
      writtenFailed: (error, _) => failed.add(error),
    );
    opened.add(store);
    store.write((w) => w.put('entry', 'a', '{}'));
    expect(store.rows().single.id, 'a');
    expect(failed, [isA<FileSystemException>()]);
    await store.writeApart([RowChange.put('entry', 'b', '{}')]);
    expect(store.count, 2);
    expect(failed, hasLength(2));
    // The third telling goes through; none after it.
    store.write((w) => w.put('entry', 'c', '{}'));
    store.write((w) => w.put('entry', 'd', '{}'));
    expect(tries, 3);
    expect(failed, hasLength(2));
  });

  test('a write is kept when what it tells of it throws and nobody is told '
      'of that', () {
    final store = EncryptedDatabase.open(
      file,
      key,
      written: () => throw const FileSystemException('disk full'),
    );
    opened.add(store);
    store.write((w) => w.put('entry', 'a', '{}'));
    expect(store.count, 1);
  });

  test('the integrity check runs on a worker as here', () async {
    final store = open()..write((w) => w.put('entry', 'a', '{}'));
    expect(await store.workApart(_integrity), 'ok');
    store.close();
  });

  test('a worker reads the records of some shelves a page at a time, in the '
      'order kept (PERF-3)', () async {
    final store = open()
      ..write((w) {
        for (var i = 0; i < 5; i++) {
          w.put('entry', 'e$i', '$i');
          if (i.isEven) w.put('trash', 't$i', '-');
        }
        w.put('category', 'c', 'c');
      });
    expect(keptPage, 1000);
    // Pages of two: e0 e1 | e2 e3 | e4 c (the trash left out), then none.
    expect(await store.workApart(_keptInTwos), 'e0 e1 e2 e3 e4 c; 6');
    store.close();
  });

  test('a worker reads shelves of few records whole by their shelf, in the '
      'order kept, through the shelf index (review 36 #2)', () async {
    final store = open()
      ..write((w) {
        w.put('category', 'c1', 'c');
        for (var i = 0; i < 5; i++) {
          w.put('entry', 'e$i', '$i');
        }
        w.put('account', 'a1', 'a');
        w.put('category', 'c2', 'c');
      });
    expect(await store.workApart(_keptFew), 'c1 a1 c2; 3');
    store.close();
    final database = raw();
    addTearDown(database.close);
    final plan = [
      for (final r in database.select('EXPLAIN QUERY PLAN $keptShelfQuery', [
        'account',
      ]))
        r['detail'] as String,
    ];
    expect(plan, ['SEARCH rows USING INDEX sqlite_autoindex_rows_1 (shelf=?)']);
  });

  test('the page size is set as the file is opened, the one cutShort counts '
      'in', () {
    expect(EncryptedDatabase.pageSize, 4096);
    final store = open()..write((w) => w.put('entry', 'a', 'x' * 9000));
    store.close();
    final database = raw();
    addTearDown(database.close);
    expect(
      database.select('PRAGMA cipher_page_size').single.values.single,
      '4096',
    );
    expect(file.lengthSync() % EncryptedDatabase.pageSize, 0);
  });

  test('damage is told apart from any other failure', () {
    expect(
      EncryptedDatabase.damageIn(
        const StorageUnavailable(StorageProblem.damaged),
      ),
      isTrue,
    );
    expect(
      EncryptedDatabase.damageIn(
        const StorageUnavailable(StorageProblem.wrongKey),
      ),
      isFalse,
    );
    expect(EncryptedDatabase.damageIn(StateError('closed')), isFalse);
  });

  test('the library is built with threads, for work apart (D41)', () {
    // SQLCipher as the app ships it: one connection, two isolates.
    expect(EncryptedDatabase.serialized, isTrue);
    expect(EncryptedDatabase.threadSafe(['THREADSAFE=1']), isTrue);
    expect(
      EncryptedDatabase.threadSafe(['OMIT_LOAD_EXTENSION', 'THREADSAFE=2']),
      isTrue,
    );
    expect(EncryptedDatabase.threadSafe(['THREADSAFE=0']), isFalse);
    expect(EncryptedDatabase.threadSafe(const []), isFalse);
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

  group('a damaged file (D94)', () {
    const damaged = StorageUnavailable(StorageProblem.damaged);

    /// A book of 3,000 rows, its log folded into the file as it closes.
    void fill() {
      open()
        ..write((w) {
          for (var i = 0; i < 3000; i++) {
            w.put('entry', 'e$i', '{"id":"e$i","note":"${'n' * 100}"}');
          }
        })
        ..close();
      opened.clear();
    }

    test('of no bytes is damaged, never opened as a new empty book', () {
      file.writeAsBytesSync(const []);
      expect(() => open(), throwsA(damaged));
      // Nothing was written into it.
      expect(file.lengthSync(), 0);
    });

    test('of no bytes but a log holding its pages is not cut short', () {
      file.writeAsBytesSync(const []);
      File('${file.path}-wal').writeAsBytesSync([1, 2, 3]);
      expect(EncryptedDatabase.cutShort(file), isFalse);
      expect(EncryptedDatabase.cutShort(File('${file.path}.none')), isFalse);
    });

    test('cut short of a whole page is damaged', () {
      fill();
      final bytes = file.readAsBytesSync();
      // 4096 * 5 + 100: five whole pages and part of a sixth.
      file.writeAsBytesSync(bytes.sublist(0, 4096 * 5 + 100));
      expect(() => open(), throwsA(damaged));
    });

    test('a first page that does not open: damaged only for a vouched '
        'key, the key wrong otherwise', () {
      fill();
      final bytes = file.readAsBytesSync();
      bytes[2000] ^= 0x10;
      file.writeAsBytesSync(bytes);
      expect(
        () => open(),
        throwsA(StorageUnavailable(StorageProblem.wrongKey)),
      );
      expect(
        () => EncryptedDatabase.open(file, key, keyVouched: true),
        throwsA(damaged),
      );
    });

    test('a later page damaged is told as damaged when it is read', () {
      fill();
      final bytes = file.readAsBytesSync();
      // Page 20 of the file, all zeros.
      bytes.fillRange(4096 * 20, 4096 * 21, 0);
      file.writeAsBytesSync(bytes);
      final store = EncryptedDatabase.open(file, key, keyVouched: true);
      opened.add(store);
      expect(() => store.rows(), throwsA(damaged));
    });

    test('a later page damaged is told as damaged when read apart', () async {
      fill();
      final bytes = file.readAsBytesSync();
      bytes.fillRange(4096 * 20, 4096 * 21, 0);
      file.writeAsBytesSync(bytes);
      final store = open();
      await expectLater(
        store.readApart((snapshot) async => snapshot.rows.length),
        throwsA(damaged),
      );
    });

    test('SQLite\'s own damage codes are told as damage', () {
      expect(
        EncryptedDatabase.isDamage(
          SqliteException(extendedResultCode: 11, message: 'malformed'),
        ),
        isTrue,
      );
      expect(
        EncryptedDatabase.isDamage(
          SqliteException(extendedResultCode: 26, message: 'notadb'),
        ),
        isTrue,
      );
      expect(
        EncryptedDatabase.isDamage(
          SqliteException(extendedResultCode: 5, message: 'busy'),
        ),
        isFalse,
      );
    });
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

  test('a copy made again continues the revision of the ledger it copies '
      '(review 26)', () {
    final store = open();
    store.write((w) => w.put('entry', 'e1', '{}'));
    expect(store.revision, 1);
    // Put at 57, not counted: 57.
    store.write((w) => w.continueRevision(57), counts: false);
    expect(store.revision, 57);
    // Put at 57 and counted: 58.
    store.write((w) => w.continueRevision(57));
    expect(store.revision, 58);
    store.write((w) => w.put('entry', 'e2', '{}'));
    expect(store.revision, 59);
    expect(
      () => store.write((w) => w.continueRevision(-1)),
      throwsArgumentError,
    );
    expect(store.revision, 59);
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

  test('a record moved to another shelf and back keeps its place (D75)', () {
    final store = open();
    store.write((w) {
      w.put('entry', 'a', '1');
      w.put('entry', 'b', '2');
      w.put('entry', 'c', '3');
    });
    store.write((w) => w.move('entry', 'trash', 'b', 'deleted'));
    expect(
      [for (final r in store.rows()) (r.shelf, r.id, r.body)],
      [('entry', 'a', '1'), ('trash', 'b', 'deleted'), ('entry', 'c', '3')],
    );
    store.write((w) => w.put('entry', 'd', '4'));
    store.write(
      (w) => w.apply(const RowChange.move('trash', 'entry', 'b', '2')),
    );
    expect(
      [for (final r in store.rows(shelf: 'entry')) r.id],
      ['a', 'b', 'c', 'd'],
    );
    // Nothing to move: kept as new, last; a stale record in the way goes.
    store.write((w) {
      w.put('trash', 'e', 'old');
      w.move('entry', 'trash', 'e', '5');
    });
    expect(store.rows(shelf: 'trash').single.body, '5');
    expect(store.rows().last.id, 'e');
  });

  test('a record taken away and put back at its place stands there again '
      '(D119)', () {
    final store = open();
    store.write((w) {
      w.put('budget', 'a', '1');
      w.put('budget', 'b', '2');
      w.put('budget', 'c', '3');
    });
    final place = store.row('budget', 'b')!.seq;
    store.write((w) => w.drop('budget', 'b'));
    store.write((w) => w.putAt('budget', 'b', 'back', place));
    expect(
      [for (final r in store.rows(shelf: 'budget')) (r.id, r.body)],
      [('a', '1'), ('b', 'back'), ('c', '3')],
    );
    expect(store.row('budget', 'b')!.seq, place);
    // Already kept: changed where it stands, as put does.
    final c = store.row('budget', 'c')!.seq;
    store.write((w) => w.putAt('budget', 'c', 'changed', place));
    expect(store.row('budget', 'c')!.seq, c);
    expect(store.row('budget', 'c')!.body, 'changed');
    // A place another record holds: kept as new, last.
    store.write((w) => w.apply(const RowChange.putAt('budget', 'd', '4', 1)));
    expect(store.rows().last.id, 'd');
    expect(store.rows().first.id, 'a');
  });

  test('a change put at a place, sent apart, stands there (D119)', () async {
    final store = open();
    store.write((w) {
      w.put('recurring', 'a', '1');
      w.put('recurring', 'b', '2');
    });
    final place = store.row('recurring', 'a')!.seq;
    store.write((w) => w.drop('recurring', 'a'));
    await store.writeApart([RowChange.putAt('recurring', 'a', 'back', place)]);
    expect([for (final r in store.rows()) r.id], ['a', 'b']);
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

  group('a write apart (DAT-03)', () {
    test('the library may be used from another thread', () {
      // The connection is handed to a worker isolate, which runs on
      // another thread; SQLite then keeps the connection's own lock.
      expect(sqlite3.usedCompileOption('THREADSAFE=1'), isTrue);
    });

    test(
      'puts and drops in one transaction on a worker, and counts once',
      () async {
        final store = open();
        store.write(
          (w) => w
            ..put('entry', 'old', 'x')
            ..put('entry', 'keep', 'k'),
        );
        expect(store.revision, 1);
        await store.writeApart([
          for (var i = 0; i < 3; i++) RowChange.put('entry', 'e$i', 'b$i'),
          const RowChange.drop('entry', 'old'),
        ]);
        expect(
          [for (final r in store.rows()) (r.id, r.body)],
          [('keep', 'k'), ('e0', 'b0'), ('e1', 'b1'), ('e2', 'b2')],
        );
        // 1 before, one write apart that counts.
        expect(store.revision, 2);
        await store.writeApart([
          const RowChange.put('price', '2330', '1000'),
        ], counts: false);
        expect(store.revision, 2);
        // Still the only owner of the file, and still the same connection.
        expect(
          () => EncryptedDatabase.open(file, key),
          throwsA(const StorageUnavailable(StorageProblem.inUse)),
        );
      },
    );

    test('while it runs nothing else uses the store: the revision is the '
        'one before, a read or a write throws, close waits', () async {
      final store = open();
      store.write((w) => w.put('entry', 'a', '1'));
      final running = store.writeApart([
        for (var i = 0; i < 20000; i++) RowChange.put('entry', 'e$i', '{}'),
      ]);
      expect(store.busyApart, isTrue);
      expect(store.revision, 1);
      expect(() => store.rows(), throwsStateError);
      expect(
        () => store.write((w) => w.put('entry', 'b', '2')),
        throwsStateError,
      );
      expect(
        () => store.writeApart(const [RowChange.drop('entry', 'a')]),
        throwsStateError,
      );
      // The journal beside the records waits as well.
      expect(() => store.journal.postingCount, throwsStateError);
      expect(() => store.journal.transaction(() => 1), throwsStateError);
      await store.idle;
      await running;
      expect(store.busyApart, isFalse);
      expect(store.revision, 2);
      // 1 + 20,000.
      expect(store.count, 20001);

      final closing = store.writeApart([const RowChange.drop('entry', 'a')]);
      store.close();
      // To be closed: no longer open to anyone new.
      expect(store.isOpen, isFalse);
      await closing;
      expect(() => store.journal.postingCount, throwsStateError);
      expect(() => store.rows(), throwsStateError);
      final again = open();
      expect(again.count, 20000);
      expect(again.revision, 3);
    });

    test('the caller\'s isolate is not held while it runs', () async {
      final store = open();
      const body =
          '{"date":"2026-10-21T00:00:00.000Z","type":"expense","amount":120,'
          '"account":"0190f3c2-7e4b-7c1a-9d2e-3f4a5b6c7d8e","note":"lunch"}';
      var ticks = 0;
      final timer = Timer.periodic(
        const Duration(milliseconds: 1),
        (_) => ticks++,
      );
      await store.writeApart([
        for (var i = 0; i < 50000; i++) RowChange.put('entry', 'e$i', body),
      ]);
      timer.cancel();
      // The timer kept firing while 50,000 rows were written: the
      // isolate was free. Written here, it would not fire at all.
      expect(ticks, greaterThan(1));
      expect(store.count, 50000);
    });
  });

  // What a read apart runs on its worker is sent there: top-level
  // functions, so no closure carries the store along.
  group('a read apart (D41)', () {
    test('reads every record and the revision on a worker', () async {
      final store = open();
      store.write(
        (w) => w
          ..put('entry', 'a', '1')
          ..put('price', 'p', '9'),
      );
      store.write((w) => w.put('entry', 'b', '2'));
      // Two writes that count: revision 2.
      expect(await store.readApart(_said), '2:a=1,p=9,b=2');
      expect(store.busyApart, isFalse);
    });

    test('with the book\'s version and the file\'s layout', () async {
      final store = open();
      expect(await store.readApart(_versions), (book: null, layout: 1));
      store.write(
        (w) => w.setMeta(EncryptedDatabase.bookVersionKey, 2),
        counts: false,
      );
      expect(await store.readApart(_versions), (book: 2, layout: 1));
    });

    test('a write while it reads waits, and lands after: the snapshot is '
        'the book as it stood', () async {
      final store = open();
      store.write((w) {
        for (var i = 0; i < 20000; i++) {
          w.put('entry', 'e$i', '{}');
        }
      });
      final reading = store.readApart(_counted);
      // The read holds the store: a write now is refused, never mixed in.
      expect(store.busyApart, isTrue);
      expect(store.revision, 1);
      expect(
        () => store.write((w) => w.put('entry', 'late', '1')),
        throwsStateError,
      );
      expect(
        () => store.writeApart(const [RowChange.drop('entry', 'e0')]),
        throwsStateError,
      );
      // Reading here meanwhile is fine: nothing writes.
      expect(store.row('entry', 'e7')?.body, '{}');
      expect(store.meta('revision'), 1);
      // A write that waits for the read lands after it.
      final writing = () async {
        while (store.busyApart) {
          await store.idle;
        }
        store.write((w) => w.put('entry', 'late', '1'));
      }();
      final snapshot = await reading;
      await writing;
      // 20,000 rows at revision 1: the write that waited is not in it.
      expect(snapshot, (rows: 20000, revision: 1));
      // On disk: 20,000 + 1 rows, revision 2.
      expect(store.count, 20001);
      expect(store.revision, 2);
    });

    test(
      'the store is free once the rows are read, while the rest runs',
      () async {
        final store = open();
        store.write((w) => w.put('entry', 'a', '1'));
        final worker = ReceivePort();
        final reading = store.readApart(_waitingOn(worker.sendPort));
        final go = await worker.first as SendPort;
        // The rows are read and the store is free, though [then] still runs.
        await store.idle;
        expect(store.busyApart, isFalse);
        store.write((w) => w.put('entry', 'b', '2'));
        go.send(null);
        expect(await reading, 1);
        expect(store.count, 2);
      },
    );

    test('a read that fails frees the store', () async {
      final store = open();
      store.write((w) => w.put('entry', 'a', '1'));
      await expectLater(store.readApart(_fails), throwsStateError);
      expect(store.busyApart, isFalse);
      expect(store.count, 1);
    });

    test('closed while it reads: closed once the read is done', () async {
      final store = open();
      store.write((w) => w.put('entry', 'a', '1'));
      final reading = store.readApart(_rowCount);
      store.close();
      expect(await reading, 1);
      expect(() => store.rows(), throwsStateError);
    });

    test(
      'the caller\'s isolate is not held while 100,000 rows are read',
      () async {
        final store = open();
        const body =
            '{"date":"2026-10-21T00:00:00.000Z","type":"expense","amount":120,'
            '"account":"0190f3c2-7e4b-7c1a-9d2e-3f4a5b6c7d8e","note":"lunch"}';
        store.write((w) {
          for (var i = 0; i < 100000; i++) {
            w.put('entry', 'e$i', body);
          }
        });
        var ticks = 0;
        final timer = Timer.periodic(
          const Duration(milliseconds: 1),
          (_) => ticks++,
        );
        final read = await store.readApart(_rowCount);
        timer.cancel();
        // The timer kept firing while the rows were read: read here, it
        // would not fire at all.
        expect(ticks, greaterThan(1));
        expect(read, 100000);
      },
    );
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

/// The revision and the records a read apart found, as text.
Future<String> _said(StoreSnapshot s) async =>
    '${s.revision}:${[for (final r in s.rows) '${r.id}=${r.body}'].join(',')}';

/// How many records a read apart found, and at which revision.
Future<({int rows, int revision})> _counted(StoreSnapshot s) async =>
    (rows: s.rows.length, revision: s.revision);

/// How many records a read apart found.
Future<int> _rowCount(StoreSnapshot s) async => s.rows.length;

/// What a read apart runs fails, as sealing a backup could.
Future<int> _fails(StoreSnapshot s) async => throw StateError('sealing failed');

/// Hands [send] a port, then waits on the worker until it is told to go.
Future<int> Function(StoreSnapshot) _waitingOn(SendPort send) => (s) async {
  final go = ReceivePort();
  send.send(go.sendPort);
  await go.first;
  return s.rows.length;
};

/// The book's version and the layout a read apart found.
Future<({int? book, int layout})> _versions(StoreSnapshot s) async =>
    (book: s.book, layout: s.layout);

/// The integrity check, run on the worker of a work apart.
Future<String> _integrity(ApartStore store) async => store.integrityCheck();

Future<String> _keptFew(ApartStore store) async {
  final rows = store.kept(const ['account', 'category'], few: true).toList();
  return '${[for (final r in rows) r.id].join(' ')}; ${rows.length}';
}

Future<String> _keptInTwos(ApartStore store) async {
  final rows = store.kept(const ['entry', 'category'], page: 2).toList();
  final seqs = [for (final r in rows) r.seq];
  // Each place after the one before: in the order kept.
  for (var i = 1; i < seqs.length; i++) {
    if (seqs[i] <= seqs[i - 1]) return 'out of order';
  }
  return '${[for (final r in rows) r.id].join(' ')}; ${rows.length}';
}
