import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:storage_sqlcipher/storage_sqlcipher.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late File file;
  late StorageKey key;

  final v1 = ['CREATE TABLE notes (id TEXT PRIMARY KEY, body TEXT) STRICT'];
  final v2 = ['ALTER TABLE notes ADD COLUMN pinned INTEGER NOT NULL DEFAULT 0'];

  setUp(() {
    directory = Directory.systemTemp.createTempSync('schema-module-');
    file = File('${directory.path}/ledger.db');
    key = StorageKey.random();
  });

  tearDown(() => directory.deleteSync(recursive: true));

  SqlCipherStore open(List<List<String>> steps) =>
      SqlCipherStore.open(file, key, modules: [SchemaModule('notes', steps)]);

  test('module steps apply once and survive reopening', () async {
    var store = open([v1]);
    expect(store.moduleVersion('notes'), 1);
    await store.write((transaction) async {
      transaction.execute('INSERT INTO notes VALUES (?, ?)', ['a', 'kept']);
      expect(transaction.select('SELECT body FROM notes'), [
        {'body': 'kept'},
      ]);
    });
    store.close();
    store = open([v1, v2]);
    expect(store.moduleVersion('notes'), 2);
    expect(store.select('SELECT * FROM notes'), [
      {'id': 'a', 'body': 'kept', 'pinned': 0},
    ]);
    store.close();
    store = open([v1, v2]);
    expect(store.moduleVersion('notes'), 2);
    store.close();
  });

  test('a module written by a newer build is refused', () {
    open([v1, v2]).close();
    expect(
      () => open([v1]),
      throwsA(const StorageUnavailable(StorageProblem.newerSchema)),
    );
  });

  test('a failing step leaves the module at its previous version', () {
    open([v1]).close();
    expect(
      () => open([
        v1,
        v2,
        ['NOT SQL'],
      ]),
      throwsA(isA<SqliteException>()),
    );
    final store = open([v1, v2]);
    expect(store.moduleVersion('notes'), 2);
    store.close();
  });

  test('projection writes roll back with their transaction', () async {
    final store = open([v1]);
    await expectLater(
      store.write((transaction) async {
        transaction.execute('INSERT INTO notes VALUES (?, ?)', ['a', 'x']);
        throw StateError('refused');
      }),
      throwsStateError,
    );
    expect(store.select('SELECT * FROM notes'), isEmpty);
    store.close();
  });

  test('module names are validated', () {
    expect(() => SchemaModule('Bad Name', const []), throwsArgumentError);
    expect(
      () => SqlCipherStore.open(
        file,
        key,
        modules: [SchemaModule('a', const []), SchemaModule('a', const [])],
      ),
      throwsArgumentError,
    );
  });
}
