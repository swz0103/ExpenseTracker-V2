import 'dart:io';

import 'package:core/app_core.dart';
import 'package:core/foundation_values.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/ledger/persistence/sql_ledger_data_source.dart';
import 'package:expense_tracker/src/core/platform/startup.dart';
import 'package:expense_tracker/src/core/time/app_clock.dart';
import 'package:expense_tracker/src/features/backup/model/encrypted_backup_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault/backup_security.dart';
import 'package:vault/ledger_backup.dart';
import 'package:vault/ledger_vault.dart';

/// When the weekly backup is taken, how many are kept, and what is kept
/// before a restore, on the days the app's clock is set to.
void main() {
  late Directory directory;
  late Startup startup;
  late Ledger ledger;
  late EncryptedBackupManager backups;
  late FixedClock clock;

  setUp(() async {
    clock = FixedClock(UtcInstant(DateTime.utc(2026, 10, 3, 4)));
    AppClock.use(clock);
    directory = Directory.systemTemp.createTempSync('backup-schedule-');
    startup = Startup(
      LedgerVault(
        directory,
        codec: KeyringCodec(kdf: PasswordKdf.insecureForTests),
      ),
      check: SqlLedgerDataSource.check,
    );
    await startup.setUp('correct horse battery');
    final vault = switch (startup.state) {
      Ready(:final vault) => vault,
      _ => throw StateError('Not open'),
    };
    ledger = await SqlLedgerDataSource(vault.store, clock: clock).load();
    backups = EncryptedBackupManager(startup, vault);
  });

  tearDown(() {
    AppClock.reset();
    if (startup.state is Ready) startup.lock();
    directory.deleteSync(recursive: true);
  });

  /// Some change to the book, so a backup has something new to keep.
  Future<void> change() async {
    ledger.accountCommands.addAccount(
      Account(ledger.newId(), '錢包', AccountKind.cash, 0),
    );
    await ledger.settled;
  }

  List<String> kept() => [
    for (final f in Directory(backups.backupFolder).listSync())
      f.uri.pathSegments.last,
  ]..sort();

  test('the weekly backup waits a week and for a change', () async {
    expect(await backups.backUpIfDue(), isNotNull, reason: 'none yet');
    await change();
    clock.advance(const Duration(days: 6));
    expect(await backups.backUpIfDue(), isNull, reason: 'six days on');
    clock.advance(const Duration(days: 2));
    expect(await backups.backUpIfDue(), isNotNull, reason: 'eight, changed');
    clock.advance(const Duration(days: 8));
    expect(await backups.backUpIfDue(), isNull, reason: 'nothing changed');
    expect(kept(), hasLength(2));
  });

  test('only the newest five are kept, by the day they were taken', () async {
    for (var week = 0; week < 7; week++) {
      await change();
      clock.advance(const Duration(days: 8));
      await backups.backUpIfDue();
    }
    final names = kept();
    expect(names, hasLength(5));
    // Named by when they were taken: the two first ones are gone.
    expect(names.first, contains('20261027'));
    expect(names.last, contains('20261128'));
  });

  test(
    'a newest backup that cannot be read is replaced by a good one',
    () async {
      final first = await backups.backUpIfDue();
      File(first!).writeAsStringSync('cut short');
      // Not due by its age, unknown by its header: written again.
      expect(await backups.backUpIfDue(), isNotNull);
    },
  );

  test('two taken in the same instant keep apart', () async {
    final a = await backups.backUp();
    final b = await backups.backUp();
    expect(a, isNot(b));
    expect(b, endsWith('-2.etbk'));
  });

  test('before a restore the two kept last stay, and what Android brought '
      'back is never let go', () async {
    final folder = startup.beforeRestore..createSync(recursive: true);
    final brought = File('${folder.path}/brought-back-1.etbk')
      ..writeAsStringSync('from Android');
    brought.setLastModifiedSync(DateTime(2020));
    final kept = <String>[];
    for (var i = 0; i < 3; i++) {
      clock.advance(const Duration(minutes: 1));
      final path = await backups.restoreAnother();
      // Each kept one written a little later than the one before.
      File(path).setLastModifiedSync(DateTime(2026, 1, 1, 0, i));
      kept.add(path);
      await startup.unlockWithPassword('correct horse battery');
      backups = EncryptedBackupManager(startup, switch (startup.state) {
        Ready(:final vault) => vault,
        _ => throw StateError('Not open'),
      });
    }
    final left = [for (final f in folder.listSync()) f.path]..sort();
    expect(left, [brought.path, kept[1], kept[2]]..sort());
    // The lock screen opens on restoring once, then no more.
    expect(startup.takeRestore(), isTrue);
    expect(startup.takeRestore(), isFalse);
  });

  group('a restore that fails leaves the book as it was', () {
    Future<void> failsAndKeeps(String path, String secret, Matcher why) async {
      await change();
      final accounts = ledger.accounts.all.length;
      await backups.restoreAnother();
      await expectLater(startup.restore(path, secret), throwsA(why));
      // The book in place opens as before, with all it held.
      await startup.unlockWithPassword('correct horse battery');
      final vault = switch (startup.state) {
        Ready(:final vault) => vault,
        _ => throw StateError('Not open'),
      };
      final after = await SqlLedgerDataSource(vault.store, clock: clock).load();
      expect(after.accounts.all, hasLength(accounts));
    }

    test('a backup cut short', () async {
      final path = await backups.backUp();
      final bytes = File(path).readAsBytesSync();
      File(path).writeAsBytesSync(bytes.sublist(0, bytes.length ~/ 2));
      await failsAndKeeps(
        path,
        'correct horse battery',
        isA<BackupException>().having(
          (e) => e.problem,
          'problem',
          BackupProblem.invalidFormat,
        ),
      );
    });

    test('a wrong password', () async {
      final path = await backups.backUp();
      await failsAndKeeps(
        path,
        'not the password at all',
        equals(const KeyringException(KeyringError.wrongSecret)),
      );
    });

    test('a backup from a newer app', () async {
      final path = await backups.backUp();
      final bytes = File(path).readAsBytesSync();
      // The header names its version after the magic and frame length.
      final text = String.fromCharCodes(bytes);
      final at = text.indexOf('"version":3');
      expect(at, greaterThan(0));
      bytes[at + '"version":'.length] = '9'.codeUnitAt(0);
      File(path).writeAsBytesSync(bytes);
      await failsAndKeeps(
        path,
        'correct horse battery',
        isA<BackupException>().having(
          (e) => e.problem,
          'problem',
          BackupProblem.unsupportedVersion,
        ),
      );
    });
  });
}
