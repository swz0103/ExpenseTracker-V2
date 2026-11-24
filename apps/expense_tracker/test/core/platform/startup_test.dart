import 'dart:io';

import 'package:expense_tracker/src/core/diagnostics/error_log.dart';
import 'package:expense_tracker/src/core/platform/startup.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storage/storage.dart';
import 'package:vault/backup_security.dart';
import 'package:vault/ledger_vault.dart';

import 'startup_gate.dart';
import 'startup_keys.dart';

const password = 'correct horse battery';

/// Stands in for an Android Keystore key; a blob opens only for the
/// context it was wrapped with, as the real key requires.
final class FakeDeviceKey implements DeviceKeyWrapper {
  final _secrets = <String, (List<int>, List<int>)>{};

  @override
  Future<List<int>> wrap(List<int> secret, List<int> context) async {
    final handle = 'blob-${_secrets.length}';
    _secrets[handle] = (List.of(secret), List.of(context));
    return handle.codeUnits;
  }

  @override
  Future<List<int>> unwrap(List<int> wrapped, List<int> context) async {
    final entry = _secrets[String.fromCharCodes(wrapped)];
    if (entry == null || !listEquals(entry.$2, context)) {
      throw StateError('not this device');
    }
    return entry.$1;
  }
}

void main() {
  group('keys', startupKeyTests);
  group('lock gate', startupGateTests);

  late Directory directory;
  late LedgerVault vault;
  final device = DeviceUnlock('phone-1', FakeDeviceKey());

  setUp(() {
    directory = Directory.systemTemp.createTempSync('startup-');
    vault = LedgerVault(
      directory,
      codec: KeyringCodec(kdf: PasswordKdf.insecureForTests),
    );
  });

  tearDown(() => directory.deleteSync(recursive: true));

  test('set up, lock, then unlock with the device key', () async {
    final startup = Startup(vault, device: device);
    expect(startup.state, isA<NeedsSetup>());
    final recovery = await startup.setUp(password);
    expect(recovery, isNotEmpty);
    final keyring = (startup.state as Ready).vault.keys.keyring.id;

    startup.lock();
    expect(startup.state, isA<Locked>());
    final reopened = Startup(vault, device: device);
    expect((reopened.state as Locked).deviceUnlock, isTrue);
    await reopened.unlockWithDevice();
    expect((reopened.state as Ready).vault.keys.keyring.id, keyring);
    reopened.lock();
  });

  test('a wrong password keeps the ledger locked', () async {
    final first = Startup(vault);
    await first.setUp(password);
    first.lock();
    final startup = Startup(vault);
    await expectLater(
      startup.unlockWithPassword('not the password'),
      throwsA(const KeyringException(KeyringError.wrongSecret)),
    );
    expect(startup.state, isA<Locked>());
    await startup.unlockWithPassword(password);
    expect(startup.state, isA<Ready>());
    startup.lock();
  });

  group('a damaged ledger file (D94)', () {
    Future<void> damage() async {
      final first = Startup(vault);
      await first.setUp(password);
      // As the book's first opening writes its first records (D102).
      (first.state as Ready).vault.store.write((w) => w.put('a', 'b', '{}'));
      first.lock();
      vault.databaseFile.writeAsBytesSync(const []);
    }

    test('is told apart from a wrong password, set aside, and '
        'restored over', () async {
      await damage();
      final startup = Startup(vault);
      var told = 0;
      startup.addListener(() => told++);
      await expectLater(
        startup.unlockWithPassword(password),
        throwsA(const StorageUnavailable(StorageProblem.damaged)),
      );
      expect(startup.state, isA<Damaged>());
      expect(told, 1);
      expect(vault.databaseFile.existsSync(), isFalse);
      expect(vault.damagedCopies(), hasLength(1));

      // Tried again: still damaged, never an empty book.
      startup.retryAfterDamage();
      expect(startup.state, isA<Locked>());
      await expectLater(
        startup.unlockWithPassword(password),
        throwsA(const StorageUnavailable(StorageProblem.damaged)),
      );
      expect(startup.state, isA<Damaged>());
      expect(vault.databaseFile.existsSync(), isFalse);

      // Restoring is offered from there: the lock screen's backup form.
      startup.lockToRestore();
      expect(startup.state, isA<Locked>());
      expect(startup.takeRestore(), isTrue);
    });

    test('a wrong password is said as before', () async {
      await damage();
      final startup = Startup(vault);
      await expectLater(
        startup.unlockWithPassword('not the password'),
        throwsA(const KeyringException(KeyringError.wrongSecret)),
      );
      expect(startup.state, isA<Locked>());
      expect(vault.damagedCopies(), isEmpty);
    });

    /// Set up, its records then spoiled on disk where they start (as a bad
    /// sector would), and opened again: the opening reads none of them.
    Future<Startup> spoiledRecords() async {
      final first = Startup(vault);
      await first.setUp(password);
      first.lock();
      // The records' table is the file's first after its schema: page 2.
      const root = 2;
      final bytes = vault.databaseFile.readAsBytesSync();
      // Inside the page, past its header: 4096 x (page - 1) + 200.
      for (var i = 0; i < 64; i++) {
        bytes[EncryptedDatabase.pageSize * (root - 1) + 200 + i] ^= 0x5a;
      }
      vault.databaseFile.writeAsBytesSync(bytes);
      final startup = Startup(vault);
      await startup.unlockWithPassword(password);
      return startup;
    }

    test('reading the book passes on what it gives, and any other '
        'failure as it is', () async {
      final startup = await spoiledRecords();
      expect(await startup.readingBook(Future.value(7)), 7);
      await expectLater(
        startup.readingBook<int>(Future.error(StateError('other'))),
        throwsStateError,
      );
      await expectLater(
        startup.readingBook<int>(
          Future.error(const StorageUnavailable(StorageProblem.inUse)),
        ),
        throwsA(const StorageUnavailable(StorageProblem.inUse)),
      );
      expect(startup.state, isA<Ready>());
      await expectLater(
        startup.readingBook<int>(
          Future.error(const StorageUnavailable(StorageProblem.damaged)),
        ),
        throwsA(const StorageUnavailable(StorageProblem.damaged)),
      );
      expect(startup.state, isA<Damaged>());
      expect(vault.damagedCopies(), hasLength(1));
    });

    test('found as the book is read, its records spoiled, it is closed and '
        'set aside', () async {
      final startup = await spoiledRecords();
      final open = (startup.state as Ready).vault;
      await startup.bookDamaged(
        const StorageUnavailable(StorageProblem.damaged),
      );
      expect(startup.state, isA<Damaged>());
      expect(open.store.isOpen, isFalse);
      expect(vault.databaseFile.existsSync(), isFalse);
      expect(vault.damagedCopies(), hasLength(1));
    });

    test('found where the records read whole (the journal\'s tables), the '
        'book is made again from them and opens at once (D102)', () async {
      final startup = Startup(vault);
      await startup.setUp(password);
      final open = (startup.state as Ready).vault;
      open.store.write((w) => w.put('account', 'cash', '{}'));
      var told = 0;
      startup.addListener(() => told++);
      expect(
        await startup.journalDamaged(
          const StorageUnavailable(StorageProblem.damaged),
        ),
        isTrue,
      );
      final again = startup.state as Ready;
      expect(told, 1);
      expect(open.store.isOpen, isFalse);
      expect(identical(again.vault, open), isFalse);
      expect(again.vault.store.rows().single.id, 'cash');
      // The old file kept aside to send for a look (review 18).
      expect(vault.damagedCopies(), hasLength(1));
      startup.lock();
    });

    test('two reports of damage at once make the book again once; it '
        'opens with nothing left over (review 18)', () async {
      final startup = Startup(vault);
      await startup.setUp(password);
      (startup.state as Ready).vault.store.write(
        (w) => w.put('account', 'cash', '{}'),
      );
      const error = StorageUnavailable(StorageProblem.damaged);
      final journal = startup.journalDamaged(error);
      final book = startup.bookDamaged(error);
      await Future.wait([journal, book]);
      expect(await journal, isTrue);
      final again = startup.state as Ready;
      expect(again.vault.store.rows().single.id, 'cash');
      expect(vault.databaseFile.existsSync(), isTrue);
      expect(vault.damagedCopies(), hasLength(1), reason: 'made again once');
      final names = [
        for (final f in directory.listSync()) f.uri.pathSegments.last,
      ];
      for (final leftover in [
        'keyring.json.new',
        'journal.damaged',
        'ledger.db.restore',
        'files.restore',
      ]) {
        expect(names, isNot(contains(leftover)));
      }
      startup.lock();
    });

    test('journal damage told with no book open is not acted on', () async {
      final startup = Startup(vault);
      await startup.setUp(password);
      startup.lock();
      expect(
        await startup.journalDamaged(
          const StorageUnavailable(StorageProblem.damaged),
        ),
        isFalse,
      );
      expect(startup.state, isA<Locked>());
      expect(File('${directory.path}/journal.damaged').existsSync(), isFalse);
    });

    const damagedError = StorageUnavailable(StorageProblem.damaged);

    /// The vault here, its clock [at] asked as a file is set aside: the
    /// moment, in a book made again, between its check and its keys
    /// named in place.
    LedgerVault vaultWithClock(DateTime Function() at) => vault = LedgerVault(
      directory,
      codec: KeyringCodec(kdf: PasswordKdf.insecureForTests),
      now: at,
    );

    /// Set up with one record, open.
    Future<Startup> withRecord() async {
      final startup = Startup(vault);
      await startup.setUp(password);
      (startup.state as Ready).vault.store.write(
        (w) => w.put('account', 'cash', '{}'),
      );
      return startup;
    }

    test('a book made again that does not open just then is kept, never '
        'set aside, and the lock screen opens it (review 25)', () async {
      var spoilKeys = false;
      vaultWithClock(() {
        // The keys about to be named in place, spoiled: the opening
        // after fails, as a full disk would make it.
        if (spoilKeys) {
          File('${directory.path}/keyring.json.new').writeAsStringSync('x');
        }
        return DateTime.utc(2026, 11, 24);
      });
      final startup = await withRecord();
      final keyring = vault.keyringFile.readAsStringSync();
      spoilKeys = true;
      expect(await startup.journalDamaged(damagedError), isTrue);
      spoilKeys = false;
      expect(startup.state, isA<Locked>());
      expect(vault.databaseFile.existsSync(), isTrue);
      expect(vault.damagedCopies(), hasLength(1), reason: 'the old file only');
      // Tried again from the lock screen: the book made again opens.
      vault.keyringFile.writeAsStringSync(keyring);
      await startup.unlockWithPassword(password);
      expect((startup.state as Ready).vault.store.rows().single.id, 'cash');
      startup.lock();
    });

    test('making the book again that fails before the copy is in place '
        'keeps the file, goes back to the lock screen, and does not spend '
        'the launch\'s one (D113)', () async {
      final startup = await withRecord();
      // The new keys cannot be written, as on a full disk: a folder in
      // their place.
      final full = Directory('${directory.path}/keyring.json.new')
        ..createSync();
      await startup.bookDamaged(damagedError);
      expect(startup.state, isA<Locked>());
      expect(ErrorLog.instance.entries.first.$2, contains('重建帳本未完成'));
      // Kept where it was (the vault test compares its bytes).
      expect(vault.databaseFile.existsSync(), isTrue);
      expect(vault.damagedCopies(), isEmpty, reason: 'nothing set aside');
      // Room again: opened from the lock screen, then found damaged
      // again, it is made again, the first try not counted.
      full.deleteSync();
      await startup.unlockWithPassword(password);
      expect(startup.state, isA<Ready>());
      await startup.bookDamaged(damagedError);
      expect((startup.state as Ready).vault.store.rows().single.id, 'cash');
      expect(vault.damagedCopies(), hasLength(1));
      // That one counted: damage found again is set aside.
      await startup.bookDamaged(damagedError);
      expect(startup.state, isA<Damaged>());
    });

    test('a book made again found damaged as it opens is Damaged, its old '
        'file still kept (review 25)', () async {
      var spoilBook = false;
      vaultWithClock(() {
        // The book made again, checked, cut to no bytes before it is put
        // in place.
        if (spoilBook) {
          File('${directory.path}/ledger.db.restore').writeAsBytesSync([]);
        }
        return DateTime.utc(2026, 11, 24);
      });
      final startup = await withRecord();
      spoilBook = true;
      expect(await startup.journalDamaged(damagedError), isTrue);
      expect(startup.state, isA<Damaged>());
      expect(vault.databaseFile.existsSync(), isFalse);
      expect(vault.damagedCopies(), hasLength(2));
    });

    test('damage found again in the same launch is set aside, not made '
        'again, the first old file kept (review 25)', () async {
      final startup = await withRecord();
      expect(await startup.journalDamaged(damagedError), isTrue);
      expect(startup.state, isA<Ready>());
      final first = vault.damagedCopies().single.path;
      expect(await startup.journalDamaged(damagedError), isTrue);
      expect(startup.state, isA<Damaged>());
      expect(vault.databaseFile.existsSync(), isFalse);
      expect(
        [for (final f in vault.damagedCopies()) f.path],
        [first, isNot(first)],
      );
    });

    test('a set-aside that fails still shows Damaged, is not handled '
        'again, and reading passes on the damage (review 25)', () async {
      var readOnly = false;
      vaultWithClock(() {
        if (readOnly) throw const FileSystemException('read-only');
        return DateTime.utc(2026, 11, 24);
      });
      final startup = await spoiledRecords();
      readOnly = true;
      await expectLater(
        startup.readingBook<int>(Future.error(damagedError)),
        throwsA(damagedError),
      );
      expect(startup.state, isA<Damaged>());
      expect(vault.databaseFile.existsSync(), isTrue, reason: 'not moved');
      // No book open: a fault after it is not handled again.
      expect(await startup.journalDamaged(damagedError), isFalse);
    });
  });

  test('a cancelled fingerprint does not stop the password unlock', () async {
    final first = Startup(vault);
    await first.setUp(password);
    first.lock();
    final startup = Startup(
      vault,
      device: DeviceUnlock('phone-2', _CancelledDeviceKey()),
    );
    await startup.unlockWithPassword(password);
    expect(startup.state, isA<Ready>());
    final keys = (startup.state as Ready).vault.keys.keyring;
    expect(keys.deviceIds, isNot(contains('phone-2')));
    startup.lock();
  });

  test('a ledger without a password opens by itself', () async {
    final startup = Startup(vault);
    await startup.setUpWithoutPassword();
    expect(startup.state, isA<Ready>());
    expect(startup.passwordless, isTrue);
    // Shown once: the copy Android takes to Google opens with it.
    expect(startup.takeRecoveryCode(), isNotNull);
    expect(startup.takeRecoveryCode(), isNull);
    expect(startup.recoveryGiven.existsSync(), isTrue);

    startup.lock();
    final again = Startup(vault);
    expect(again.state, isA<Locked>());
    expect(again.passwordless, isTrue);
    await again.openQuietly();
    expect(again.state, isA<Ready>());
  });

  test('a set-up without a password that stopped part way leaves no key '
      'for a ledger never made, and keeps the one for a ledger made', () async {
    final key = File('${directory.path}/quick-open.sealed');
    final pending = File('${key.path}.new');
    pending.writeAsStringSync('left over');
    final none = Startup(vault);
    expect(none.state, isA<NeedsSetup>());
    expect(none.passwordless, isFalse);
    expect(pending.existsSync(), isFalse);

    final made = Startup(vault);
    await made.setUpWithoutPassword();
    made.lock();
    key.renameSync(pending.path);
    final again = Startup(vault);
    expect(again.state, isA<Locked>());
    expect(again.passwordless, isTrue);
    await again.openQuietly();
    expect(again.state, isA<Ready>());
  });

  test('a password set-up drops a key left from an earlier try', () async {
    File('${directory.path}/quick-open.key').writeAsStringSync('old');
    final startup = Startup(vault);
    await startup.setUp(password);
    expect(startup.passwordless, isFalse);
  });

  test('a new ledger sets aside the copy Android brought back', () async {
    final startup = Startup(vault);
    final copy = startup.cloudCopy;
    await copy.parent.create(recursive: true);
    await copy.writeAsString('not a backup');
    expect(await startup.broughtBack(), isNull, reason: 'unreadable');
    await startup.setUpWithoutPassword();
    expect(copy.existsSync(), isFalse);
    expect(
      startup.beforeRestore.listSync().whereType<File>().single.path,
      contains('brought-back-'),
    );
    startup.lock();
  });

  test('a ledger without a password that never showed its code shows a '
      'new one once, as it opens', () async {
    final startup = Startup(vault);
    await startup.setUpWithoutPassword();
    startup
      ..takeRecoveryCode()
      ..lock();
    // As a ledger from before 0.5.1: no code was shown.
    startup.recoveryGiven.deleteSync();
    final again = Startup(vault);
    await again.openQuietly();
    final code = again.takeRecoveryCode();
    expect(code, isNotNull);
    again.lock();
    final third = Startup(vault);
    await third.openQuietly();
    expect(third.takeRecoveryCode(), isNull, reason: 'once');
    third.lock();
    // The new code opens it.
    final fourth = Startup(vault);
    await fourth.unlockWithRecovery(code!);
    expect(fourth.state, isA<Ready>());
    fourth.lock();
  });
}

/// A device key whose fingerprint prompt is always cancelled.
final class _CancelledDeviceKey implements DeviceKeyWrapper {
  @override
  Future<List<int>> wrap(List<int> secret, List<int> context) =>
      Future.error(StateError('cancelled'));

  @override
  Future<List<int>> unwrap(List<int> wrapped, List<int> context) =>
      Future.error(StateError('cancelled'));
}
