import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:app_core/app_core.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:storage_sqlcipher/storage_sqlcipher.dart';
import 'package:test/test.dart';

final class _Append implements Command<int> {
  _Append(this.operation, this.text);

  @override
  final OperationKey operation;
  final String text;

  @override
  String get input => 'append-v1:$text';

  @override
  String encodeResult(int result) => '$result';

  @override
  int decodeResult(String encoded) => int.parse(encoded);
}

const _rewrites = [
  "UPDATE events SET payload = 'x'",
  'DELETE FROM events',
  "UPDATE operations SET result = 'x'",
  'DELETE FROM operations',
];

void main() {
  final workspace = WorkspaceId(PublicId.generate());
  OperationKey key() =>
      OperationKey(workspace, OperationId(PublicId.generate()));
  late Directory directory;
  late File file;
  late StorageKey storageKey;
  final opened = <SqlCipherStore>[];

  SqlCipherStore open([StorageKey? other]) {
    final store = SqlCipherStore.open(file, other ?? storageKey);
    opened.add(store);
    return store;
  }

  int append(SqlTransaction transaction, String text) {
    return transaction.append(
      id: PublicId.generate(),
      workspace: workspace,
      kind: 'test.appended',
      payload: jsonEncode({'text': text}),
    );
  }

  Future<CommandOutcome<int>> run(
    CommandRunner<SqlTransaction> runner,
    _Append command,
  ) {
    return runner.run(command, (t) async => append(t, command.text));
  }

  Database raw() {
    final database = sqlite3.open(file.path);
    database.execute('PRAGMA key = "x\'${storageKey.hex}\'"');
    return database;
  }

  setUp(() {
    directory = Directory.systemTemp.createTempSync('storage-sqlcipher-');
    file = File('${directory.path}/ledger.db');
    storageKey = StorageKey.random();
  });

  tearDown(() {
    for (final store in opened) {
      store.close();
    }
    opened.clear();
    directory.deleteSync(recursive: true);
  });

  test('a new store is encrypted, migrated and in WAL mode', () {
    final store = open();
    expect(store.schemaVersion, SqlCipherStore.latestSchema);
    expect(store.journalMode, 'wal');
    expect(store.integrityCheck(), 'ok');
    store.close();
    final header = file.readAsBytesSync().sublist(0, 15);
    expect(String.fromCharCodes(header), isNot('SQLite format 3'));
  });

  test('the storage key never appears in its description', () {
    expect('$storageKey', isNot(contains(storageKey.hex)));
    expect(StorageKey.fromHex(storageKey.hex).hex, storageKey.hex);
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

  test('a file from a newer schema is refused', () {
    open().close();
    final database = raw();
    database.userVersion = SqlCipherStore.latestSchema + 1;
    database.close();
    expect(
      () => open(),
      throwsA(const StorageUnavailable(StorageProblem.newerSchema)),
    );
  });

  test('commands replay, conflict and roll back', () async {
    final store = open();
    final runner = CommandRunner(store);
    final command = _Append(key(), 'a');
    final first = await run(runner, command);
    final retry = await run(runner, command);
    expect(first.replayed, isFalse);
    expect(retry.replayed, isTrue);
    expect(retry.value, first.value);
    await expectLater(
      run(runner, _Append(command.operation, 'b')),
      throwsA(const AppFailure.operationConflict()),
    );
    final failing = _Append(key(), 'c');
    await expectLater(
      runner.run(failing, (transaction) async {
        append(transaction, 'partial');
        await transaction.enqueue(
          OutboxMessage(id: PublicId.generate(), topic: 't', payload: 'p'),
        );
        throw const AppFailure(FailureKind.rejected, 'test.refused');
      }),
      throwsA(const AppFailure(FailureKind.rejected, 'test.refused')),
    );
    expect(store.eventCount, 1);
    expect(store.operationCount, 1);
    expect(store.pendingOutbox(), isEmpty);
    expect((await run(runner, failing)).replayed, isFalse);
    expect(store.eventCount, 2);
  });

  test('concurrent commands queue and all commit', () async {
    final store = open();
    final runner = CommandRunner(store);
    final outcomes = await Future.wait([
      for (var i = 0; i < 20; i++) run(runner, _Append(key(), '$i')),
    ]);
    final expected = List.generate(20, (i) => i + 1);
    expect(outcomes.map((o) => o.value), expected);
    expect(store.events(workspace).map((e) => e.seq), expected);
  });

  test('committed data survives reopening', () async {
    final store = open();
    final command = _Append(key(), 'kept');
    final message = OutboxMessage(
      id: PublicId.generate(),
      topic: 'backup.requested',
      payload: '{}',
    );
    await CommandRunner(store).run(command, (transaction) async {
      await transaction.enqueue(message);
      return append(transaction, 'kept');
    });
    store.close();
    final reopened = open();
    expect(reopened.events(workspace).single.payload, '{"text":"kept"}');
    expect(reopened.pendingOutbox().single.id, message.id);
    reopened.acknowledge(message.id);
    expect(reopened.pendingOutbox(), isEmpty);
    final retry = await run(CommandRunner(reopened), command);
    expect(retry.replayed, isTrue);
    expect(reopened.eventCount, 1);
  });

  test('events and operations cannot be rewritten', () async {
    final store = open();
    await run(CommandRunner(store), _Append(key(), 'a'));
    store.close();
    final database = raw();
    addTearDown(database.close);
    // The raw connection really reads the store, so a refusal below comes
    // from the triggers, not from a wrong key.
    expect(database.select('SELECT COUNT(*) AS n FROM events').single['n'], 1);
    for (final statement in _rewrites) {
      expect(
        () => database.execute(statement),
        throwsA(
          isA<SqliteException>().having(
            (e) => e.message,
            'message',
            anyOf(contains('append-only'), contains('immutable')),
          ),
        ),
        reason: statement,
      );
    }
    expect(database.select('SELECT COUNT(*) AS n FROM events').single['n'], 1);
    final operations = database.select('SELECT COUNT(*) AS n FROM operations');
    expect(operations.single['n'], 1);
  });

  test('overlapping writes and closing mid-write are refused', () async {
    final store = open();
    addTearDown(store.close);
    final release = Completer<void>();
    final first = store.write((_) => release.future);
    await expectLater(store.write((_) async {}), throwsA(isA<StateError>()));
    expect(store.close, throwsA(isA<StateError>()));
    release.complete();
    await first;
  });

  test('an invalid event kind is rejected before writing', () async {
    final store = open();
    await expectLater(
      store.write((transaction) async {
        return transaction.append(
          id: PublicId.generate(),
          workspace: workspace,
          kind: 'Bad Kind',
          payload: '{}',
        );
      }),
      throwsArgumentError,
    );
    expect(store.eventCount, 0);
  });

  test('only one connection, isolate or process owns the file', () async {
    final store = SqlCipherStore.open(file, storageKey);
    expect(
      () => SqlCipherStore.open(file, storageKey),
      throwsA(const StorageUnavailable(StorageProblem.inUse)),
    );
    final port = ReceivePort();
    await Isolate.spawn(_openElsewhere, [
      port.sendPort,
      file.path,
      storageKey.hex,
    ]);
    expect(await port.first, StorageProblem.inUse.name);
    store.close();
    SqlCipherStore.open(file, storageKey).close();
  });

  test('a killed writer never leaves a torn or unjournaled commit', () async {
    final suffix = Platform.isWindows ? '.exe' : '';
    final worker = File('.dart_tool/worker/bundle/bin/crash_worker$suffix');
    final random = Random(20261003);
    var acknowledged = 0;
    for (var round = 0; round < 8; round++) {
      final stopAfter = 1 + random.nextInt(40);
      final process = await Process.start(worker.absolute.path, [
        file.path,
        storageKey.hex,
        '$workspace',
        '100000',
      ]);
      final output = process.stdout.transform(utf8.decoder);
      final lines = output.transform(const LineSplitter());
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
      expect(store.eventCount, store.operationCount);
      expect(store.eventCount, greaterThanOrEqualTo(acknowledged));
      store.close();
    }
  });
}

/// Opens the store from another isolate and reports why it could not.
void _openElsewhere(List<Object> message) {
  final reply = message[0] as SendPort;
  final file = File(message[1] as String);
  try {
    SqlCipherStore.open(file, StorageKey.fromHex(message[2] as String)).close();
    reply.send(null);
  } on StorageUnavailable catch (error) {
    reply.send(error.problem.name);
  }
}
