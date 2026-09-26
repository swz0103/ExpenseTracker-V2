import 'dart:convert';
import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:encrypted_storage_probe/encrypted_database.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:modular_persistence_probe/database.dart';
import 'package:modular_persistence_probe/workflows.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:validated_restore_probe/restore_store.dart';
import 'package:validated_restore_probe/snapshot.dart';

const marker = 'FIXTURE_PRIVATE_FINANCE_MARKER_2026';
const password = 'encrypted-fixture-password';
void main() {
  final root = Directory('.dart_tool/encrypted-tests')
    ..createSync(recursive: true);
  late Directory work;
  late File file;
  late StorageKey key;
  final ws = WorkspaceId(PublicId.generate());
  final account = Account.open(
    id: PublicId.generate(),
    workspace: ws,
    name: marker,
    kind: AccountKind.bank,
    currency: Currency('USD', 2),
    openedOn: BusinessDate(2026, 9, 26),
  );
  final postingAccount = PostingAccount(
    id: account.id,
    workspace: ws,
    currency: account.currency,
    expectedVersion: 1,
  );
  setUp(() {
    work = root.createTempSync('case-');
    file = File('${work.path}/finance.db');
    key = StorageKey.random();
  });
  tearDown(() {
    if (!work.resolveSymbolicLinksSync().startsWith(
      '${root.resolveSymbolicLinksSync()}${Platform.pathSeparator}',
    ))
      throw StateError('Unsafe cleanup.');
    work.deleteSync(recursive: true);
  });
  Posting income() => Posting.income(
    id: PublicId.generate(),
    operation: OperationKey(ws, OperationId(PublicId.generate())),
    date: account.openedOn,
    account: postingAccount,
    amount: Money.parse(account.currency, '20'),
  );
  Future<void> seed(ProbeDatabase db) async {
    await FinancialWorkflows(db).createAccount(
      account,
      Posting.opening(
        id: PublicId.generate(),
        operation: OperationKey(ws, OperationId(PublicId.generate())),
        date: account.openedOn,
        account: postingAccount,
        amount: Money.parse(account.currency, '100'),
      ),
    );
    await FinancialWorkflows(db).post(income());
  }

  Future<void> verify(ProbeDatabase db) async {
    expect(
      await FinancialWorkflows(db).ledger.balance(postingAccount),
      Money.parse(account.currency, '120'),
    );
    expect(
      (await db.customSelect('PRAGMA cipher_integrity_check').get()),
      isEmpty,
    );
    await SnapshotCodec().validate(db);
  }

  void encryptedBytes(File target) {
    final bytes = target.readAsBytesSync();
    final content = latin1.decode(bytes);
    expect(content.startsWith('SQLite format 3'), isFalse);
    expect(content, isNot(contains(marker)));
    final raw = sqlite3.open(target.path, mode: OpenMode.readOnly);
    try {
      expect(
        () => raw.select('SELECT * FROM accounts'),
        throwsA(isA<SqliteException>()),
      );
    } finally {
      raw.close();
    }
  }

  test('pinned engine is SQLCipher with a crypto provider', () {
    final raw = sqlite3.open(file.path);
    try {
      configureEncryption(raw, key);
      final version = raw.select('PRAGMA cipher_version').single.values.single;
      final provider = raw
          .select('PRAGMA cipher_provider')
          .single
          .values
          .single;
      print(
        'SQLCipher version=$version provider=$provider SQLite=${sqlite3.version}',
      );
      expect(version.toString(), startsWith('4.19.0 '));
      expect(provider.toString(), isNotEmpty);
    } finally {
      raw.close();
    }
  });
  test(
    'encrypted ledger survives restart, hides marker, and rejects keyless open',
    () async {
      var db = openEncrypted(file, key);
      try {
        await seed(db);
        await verify(db);
      } finally {
        await db.close();
      }
      encryptedBytes(file);
      db = openEncrypted(file, key);
      try {
        await verify(db);
      } finally {
        await db.close();
      }
    },
  );
  test('wrong key refuses open without changing encrypted bytes', () async {
    var db = openEncrypted(file, key);
    try {
      await seed(db);
    } finally {
      await db.close();
    }
    final before = file.readAsBytesSync();
    db = openEncrypted(file, StorageKey.random());
    try {
      await expectLater(
        db.customSelect('SELECT * FROM accounts').get(),
        throwsA(isA<EncryptedStorageUnavailable>()),
      );
    } finally {
      await db.close();
    }
    expect(file.readAsBytesSync(), before);
    db = openEncrypted(file, key);
    try {
      await verify(db);
    } finally {
      await db.close();
    }
  });
  test(
    'plaintext file is refused without silently encrypting or replacing it',
    () async {
      final raw = sqlite3.open(file.path);
      raw.execute('CREATE TABLE fixture (value TEXT)');
      raw.close();
      final before = file.readAsBytesSync();
      final db = openEncrypted(file, key);
      try {
        await expectLater(
          db.customSelect('SELECT * FROM accounts').get(),
          throwsA(isA<EncryptedStorageUnavailable>()),
        );
      } finally {
        await db.close();
      }
      expect(file.readAsBytesSync(), before);
    },
  );
  test(
    'encrypted transactions roll back and retry commits only once',
    () async {
      final db = openEncrypted(file, key);
      try {
        await seed(db);
        final flows = FinancialWorkflows(db);
        final proposed = income();
        await expectLater(
          flows.post(
            proposed,
            checkpoint: (point) {
              if (point == 'leg') throw StateError('injected');
            },
          ),
          throwsStateError,
        );
        await verify(db);
        expect((await flows.post(proposed)).replayed, isFalse);
        expect((await flows.post(proposed)).replayed, isTrue);
        expect(
          await flows.ledger.balance(postingAccount),
          Money.parse(account.currency, '140'),
        );
      } finally {
        await db.close();
      }
    },
  );
  for (final credential in ['password', 'recovery']) {
    test(
      '$credential restores snapshot into independently keyed encrypted stage',
      () async {
        final db = openEncrypted(file, key);
        late final List<int> expected;
        late final String envelope;
        late final String recoveryKey;
        final sourceStore = RestoreStore(work);
        try {
          await seed(db);
          expected = await SnapshotCodec().capture(db);
          final backup = await sourceStore.backup(db, password);
          envelope = backup.envelope;
          recoveryKey = backup.recoveryKey;
        } finally {
          await db.close();
        }
        final destinationKey = StorageKey.random();
        final destination = Directory('${work.path}/destination');
        final store = RestoreStore(
          destination,
          openDatabase: (f) => openEncrypted(f, destinationKey),
        );
        var checkedStage = false;
        await store.restore(
          envelope,
          password: credential == 'password' ? password : null,
          recoveryKey: credential == 'recovery' ? recoveryKey : null,
          checkpoint: (point) {
            if (point == 'validated') {
              encryptedBytes(File('${destination.path}/stage.db'));
              checkedStage = true;
            }
          },
        );
        expect(checkedStage, isTrue);
        encryptedBytes(store.current);
        final restored = openEncrypted(store.current, destinationKey);
        try {
          await verify(restored);
          expect(await SnapshotCodec().capture(restored), expected);
        } finally {
          await restored.close();
        }
        final wrong = openEncrypted(store.current, key);
        try {
          await expectLater(
            wrong.customSelect('SELECT * FROM accounts').get(),
            throwsA(isA<EncryptedStorageUnavailable>()),
          );
        } finally {
          await wrong.close();
        }
      },
    );
  }
  test('encrypted WAL does not contain fixture marker', () async {
    final db = openEncrypted(file, key);
    try {
      await db.customStatement('PRAGMA journal_mode = WAL');
      await db.customStatement('PRAGMA wal_autocheckpoint = 0');
      await seed(db);
      final wal = File('${file.path}-wal');
      expect(wal.existsSync(), isTrue);
      expect(wal.lengthSync(), greaterThan(0));
      expect(latin1.decode(wal.readAsBytesSync()), isNot(contains(marker)));
      await verify(db);
    } finally {
      await db.close();
    }
  });
  test(
    'encrypted first-page corruption rejects without overwriting the file',
    () async {
      var db = openEncrypted(file, key);
      try {
        await seed(db);
      } finally {
        await db.close();
      }
      final corrupt = file.readAsBytesSync();
      corrupt[80] ^= 1;
      file.writeAsBytesSync(corrupt, flush: true);
      db = openEncrypted(file, key);
      try {
        await expectLater(
          db.customSelect('SELECT * FROM accounts').get(),
          throwsA(isA<EncryptedStorageUnavailable>()),
        );
      } finally {
        await db.close();
      }
      expect(file.readAsBytesSync(), corrupt);
    },
  );
  test('frozen encrypted v1 migrates to v2 without losing history', () async {
    final raw = sqlite3.open(file.path);
    try {
      configureEncryption(raw, key);
      raw.execute(
        File('../modular_persistence/test/fixtures/v1.sql').readAsStringSync(),
      );
    } finally {
      raw.close();
    }
    encryptedBytes(file);
    final db = openEncrypted(file, key);
    try {
      expect(
        (await db.customSelect('PRAGMA user_version').getSingle())
            .data
            .values
            .single,
        2,
      );
      await SnapshotCodec().validate(db);
      expect(
        (await db
                .customSelect('SELECT SUM(amount) AS amount FROM legs')
                .getSingle())
            .read<int>('amount'),
        11500,
      );
    } finally {
      await db.close();
    }
  });
  test('failed encrypted promotion preserves both old database and encrypted stage', () async {
    final destination = Directory('${work.path}/destination');
    destination.createSync();
    final current = File('${destination.path}/current.db');
    final db = openEncrypted(current, key);
    final store = RestoreStore(
      destination,
      openDatabase: (f) => openEncrypted(f, key),
    );
    late final String envelope;
    late final String recovery;
    try {
      await seed(db);
      final backup = await store.backup(db, password);
      envelope = backup.envelope;
      recovery = backup.recoveryKey;
    } finally {
      await db.close();
    }
    final before = current.readAsBytesSync();
    await expectLater(
      store.restore(
        envelope,
        recoveryKey: recovery,
        checkpoint: (point) {
          if (point == 'newMoved') throw StateError('injected');
        },
      ),
      throwsStateError,
    );
    expect(current.readAsBytesSync(), before);
    final databases = destination
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.db'))
        .toList();
    expect(databases, hasLength(2));
    for (final target in databases) {
      encryptedBytes(target);
    }
  });
  test('key input is length checked and redacted', () {
    expect(() => StorageKey([1]), throwsArgumentError);
    expect(() => StorageKey(List.filled(32, 256)), throwsArgumentError);
    expect(key.toString(), 'StorageKey(redacted)');
  });
}
