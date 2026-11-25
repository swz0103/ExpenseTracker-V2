import 'dart:io';

import 'package:core/app_core.dart' show FixedClock;
import 'package:expense_tracker/src/core/design_system/keys.dart';
import 'package:core/foundation_values.dart';
import 'package:expense_tracker/src/core/diagnostics/error_log.dart';
import 'package:expense_tracker/src/core/time/app_clock.dart';
import 'package:expense_tracker/src/features/lock/ui/views/lock_parts.dart';
import 'package:expense_tracker/src/core/platform/startup.dart';
import 'package:expense_tracker/src/core/messages/lock_messages.dart';
import 'package:expense_tracker/src/features/backup/model/drive_backup.dart';
import 'package:expense_tracker/src/features/backup/model/restore_sources.dart';
import 'package:expense_tracker/src/features/lock/ui/lock_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:storage/storage.dart' show StorageProblem, StorageUnavailable;
import 'package:vault/backup_security.dart';
import 'package:vault/ledger_backup.dart';
import 'package:vault/ledger_vault.dart';

import '../../../support/fake_drive.dart';
import '../../../support/no_room.dart';
import '../../../support/places.dart';

const password = 'correct horse battery';

void main() {
  late Directory directory;
  late LedgerVault vault;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('lock-screen-');
    vault = LedgerVault(
      directory,
      codec: KeyringCodec(kdf: PasswordKdf.insecureForTests),
    );
  });

  tearDown(() => directory.deleteSync(recursive: true));

  /// A ledger with a password, set up and opened.
  Future<Startup> opened(WidgetTester tester) async {
    final startup = Startup(vault);
    await tester.runAsync(() => startup.setUp(password));
    return startup;
  }

  Future<void> show(WidgetTester tester, Startup startup) async {
    await tester.pumpWidget(MaterialApp(home: LockScreen(startup: startup)));
    await tester.pump();
  }

  /// Lets the real work behind a tap (files, key derivation) finish.
  Future<void> settle(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 50 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
  }

  /// Presses what a screen reader calls [label], then draws.
  Future<void> press(WidgetTester tester, Pattern label) async {
    await tester.tap(find.bySemanticsLabel(label).last);
    await tester.pump();
  }

  testWidgets('a wrong password says so, keeps the ledger locked and '
      'notes no fault', (tester) async {
    final startup = await opened(tester);
    startup.lock();
    await show(tester, startup);
    expect(find.text('忘記密碼？'), findsOneWidget);
    final noted = ErrorLog.instance.entries.length;
    await tester.enterText(find.byType(TextField), 'not the password');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await settle(tester, () => find.text('密碼不正確').evaluate().isNotEmpty);
    expect(find.text('密碼不正確'), findsOneWidget);
    expect(startup.state, isA<Locked>());
    // A wrong password is expected: nothing for the diagnostics log.
    expect(ErrorLog.instance.entries.length, noted);

    await tester.enterText(find.byType(TextField), password);
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await settle(tester, () => startup.state is Ready);
    expect(startup.state, isA<Ready>());
    startup.lock();
  });

  testWidgets('back on the lock screen for a full phone, it says to free '
      'space first (review 29)', (tester) async {
    final startup = await opened(tester);
    await tester.runAsync(
      () => IOOverrides.runWithIOOverrides(
        () => startup.journalDamaged(
          const StorageUnavailable(StorageProblem.damaged),
        ),
        NoRoom(),
      ),
    );
    expect(startup.state, isA<Locked>());
    await show(tester, startup);
    expect(find.text(LockWords.noSpace), findsOneWidget);
  });

  testWidgets('restoring from settings opens on the backup form, and back '
      'reopens this ledger without asking for the password (F92)', (
    tester,
  ) async {
    final startup = await opened(tester);
    startup.lockToRestore();
    await show(tester, startup);
    expect(find.text('從備份還原'), findsOneWidget);
    expect(startup.takeRestore(), isFalse, reason: 'asked once');
    await tester.tap(find.byKey(Keys.back));
    await settle(tester, () => startup.state is Ready);
    expect(startup.state, isA<Ready>());
    expect(startup.takeResumed(), isTrue);
    startup.lock();
  });

  testWidgets('the system back from that form reopens the ledger too', (
    tester,
  ) async {
    final startup = await opened(tester);
    startup.lockToRestore();
    await show(tester, startup);
    await tester.binding.handlePopRoute();
    await settle(tester, () => startup.state is Ready);
    expect(startup.state, isA<Ready>());
    startup.lock();
  });

  testWidgets('once the app locked while the backup form was up, back asks '
      'for the password', (tester) async {
    final startup = await opened(tester);
    startup.lockToRestore();
    await show(tester, startup);
    // As the lock gate does after too long away.
    startup.lock();
    await tester.pump();
    expect(find.text('從備份還原'), findsOneWidget);
    await tester.tap(find.byKey(Keys.back));
    await tester.pump();
    expect(startup.state, isA<Locked>());
    expect(find.text('忘記密碼？'), findsOneWidget);
  });

  group('too many wrong tries (SEC-03)', () {
    late FixedClock clock;

    setUp(() {
      clock = FixedClock(UtcInstant(DateTime.utc(2026, 11, 23, 9)));
      AppClock.use(clock);
    });

    tearDown(AppClock.reset);

    /// A ledger locked after [wrong] wrong passwords in a row.
    Future<Startup> lockedAfter(WidgetTester tester, int wrong) async {
      final startup = await opened(tester);
      startup.lock();
      await tester.runAsync(() async {
        for (var i = 0; i < wrong; i++) {
          try {
            await startup.unlockWithPassword('wrong password $i');
          } on KeyringException {
            // Refused, and counted.
          }
        }
      });
      return startup;
    }

    final wait = find.byKey(Keys.unlockWait);
    String waitWords(WidgetTester tester) => switch (tester.widget(wait)) {
      Text(:final data) => data!,
      final other => (other as ProblemLine).problem!,
    };
    TextField field(WidgetTester tester) =>
        tester.widget<TextField>(find.byType(TextField));

    testWidgets('the screen says how long to wait, counts it down, takes no '
        'password meanwhile, and opens up by itself', (tester) async {
      final startup = await lockedAfter(tester, 5);
      await show(tester, startup);
      expect(waitWords(tester), '輸入錯誤太多次，請等 30 秒再試');
      expect(field(tester).readOnly, isTrue);
      // Sending what is typed does nothing while waiting.
      await tester.testTextInput.receiveAction(TextInputAction.go);
      await tester.pump();
      expect(startup.state, isA<Locked>());

      clock.advance(const Duration(seconds: 12));
      await tester.pump(const Duration(seconds: 1));
      // 30 s - 12 s
      expect(waitWords(tester), '輸入錯誤太多次，請等 18 秒再試');

      clock.advance(const Duration(seconds: 18));
      await tester.pump(const Duration(seconds: 1));
      expect(wait, findsNothing);
      expect(field(tester).readOnly, isFalse);

      await tester.enterText(find.byType(TextField), password);
      await tester.testTextInput.receiveAction(TextInputAction.go);
      await settle(tester, () => startup.state is Ready);
      expect(startup.state, isA<Ready>());
      startup.lock();
    });

    testWidgets('the fifth wrong password typed starts the wait on screen', (
      tester,
    ) async {
      final startup = await lockedAfter(tester, 4);
      await show(tester, startup);
      expect(wait, findsNothing);
      await tester.enterText(find.byType(TextField), 'not the password');
      await tester.testTextInput.receiveAction(TextInputAction.go);
      await settle(tester, () => wait.evaluate().isNotEmpty);
      expect(waitWords(tester), '輸入錯誤太多次，請等 30 秒再試');
      // The wait says why; 密碼不正確 is not left beside it or after it.
      expect(find.text('密碼不正確'), findsNothing);
      clock.advance(const Duration(seconds: 30));
      await tester.pump(const Duration(seconds: 1));
      expect(wait, findsNothing);
      expect(find.text('密碼不正確'), findsNothing);
    });

    testWidgets('the recovery code waits the same wait: its field and '
        'button are off', (tester) async {
      final startup = await lockedAfter(tester, 5);
      await show(tester, startup);
      final semantics = tester.ensureSemantics();
      await press(tester, '忘記密碼？');
      await tester.pump(const Duration(milliseconds: 500));
      expect(waitWords(tester), '輸入錯誤太多次，請等 30 秒再試');
      expect(field(tester).enabled, isFalse);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '打開'))
            .onPressed,
        isNull,
      );
      clock.advance(const Duration(seconds: 30));
      await tester.pump(const Duration(seconds: 1));
      expect(wait, findsNothing);
      expect(field(tester).enabled, isTrue);
      semantics.dispose();
    });

    testWidgets('a backup being restored is not held up by it', (tester) async {
      final startup = await lockedAfter(tester, 5);
      startup.lockToRestore();
      await show(tester, startup);
      expect(find.text('從備份還原'), findsOneWidget);
      expect(wait, findsNothing);
    });
  });

  testWidgets('what was wrong is no longer said once the person types '
      'again (F38)', (tester) async {
    final startup = await opened(tester);
    startup.lock();
    await show(tester, startup);
    await tester.enterText(find.byType(TextField), 'not the password');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await settle(tester, () => find.text('密碼不正確').evaluate().isNotEmpty);
    expect(find.text('密碼不正確'), findsOneWidget);
    // Still said while nothing is typed.
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('密碼不正確'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'c');
    await tester.pump();
    expect(find.text('密碼不正確'), findsNothing);
  });

  testWidgets('a wrong recovery code is said until the code is changed, '
      'not when the field is only touched (F38)', (tester) async {
    final startup = await opened(tester);
    startup.lock();
    await show(tester, startup);
    final semantics = tester.ensureSemantics();
    await press(tester, '忘記密碼？');
    await tester.pump(const Duration(milliseconds: 500));
    const typed = 'not the code';
    await tester.enterText(find.byType(TextField), typed);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    String? said() =>
        tester.widget<ProblemLine>(find.byType(ProblemLine)).problem;
    await settle(tester, () => said() != null);
    final words = said();
    expect(words, isNotNull);
    // The cursor moved, the code as it was.
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: typed,
        selection: TextSelection.collapsed(offset: 3),
      ),
    );
    await tester.pump();
    expect(said(), words);
    await tester.enterText(find.byType(TextField), 'another');
    await tester.pump();
    expect(said(), isNull);
    semantics.dispose();
  });

  /// Draws the first frame, plays the opening and the choices coming in.
  Future<void> settleIn(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump(const Duration(milliseconds: 700));
  }

  testWidgets('with a password, the opening plays as the app starts, then '
      'the password is asked for', (tester) async {
    final first = await opened(tester);
    first.lock();
    // The app started again on the locked ledger.
    final startup = Startup(vault);
    await show(tester, startup);
    expect(find.text('忘記密碼？'), findsNothing);
    await settleIn(tester);
    expect(find.text('忘記密碼？'), findsOneWidget);
    expect(startup.takeOpening(), isFalse, reason: 'once per start');
  });

  testWidgets('a new ledger opens on the welcome and starts without a '
      'password', (tester) async {
    final startup = Startup(vault);
    expect(startup.state, isA<NeedsSetup>());
    await show(tester, startup);
    await settleIn(tester);
    expect(find.text('記帳本'), findsOneWidget);
    expect(find.text('還原備份'), findsOneWidget);
    expect(find.text('先設定密碼'), findsNothing);

    await tester.tap(find.byKey(Keys.newBook));
    await tester.pump();
    await settle(tester, () => startup.state is Ready);
    expect(startup.state, isA<Ready>());
    expect(startup.passwordless, isTrue);
    expect(startup.takeFresh(), isTrue, reason: 'the tour comes next');
    expect(startup.takeFresh(), isFalse, reason: 'once');
    startup.lock();
  });

  testWidgets('還原備份 opens the backup form, and back returns to the '
      'choices', (tester) async {
    final startup = Startup(vault);
    await show(tester, startup);
    await settleIn(tester);
    await tester.tap(find.byKey(Keys.restore));
    await tester.pump();
    expect(find.text('從備份還原'), findsOneWidget);

    await tester.tap(find.byKey(Keys.back));
    await tester.pump();
    expect(find.text('建立新帳本'), findsOneWidget);
    expect(startup.state, isA<NeedsSetup>());
  });

  testWidgets('a backup Android brought back is offered on the welcome, '
      'and asks for its password', (tester) async {
    final first = await opened(tester);
    final open = (first.state as Ready).vault;
    final elsewhere = Directory.systemTemp.createTempSync('lock-screen-new-');
    addTearDown(() => elsewhere.deleteSync(recursive: true));
    final phone = Startup(
      LedgerVault(
        elsewhere,
        codec: KeyringCodec(kdf: PasswordKdf.insecureForTests),
      ),
    );
    await tester.runAsync(() async {
      await phone.cloudCopy.parent.create(recursive: true);
      await LedgerBackup.write(
        store: open.store,
        keys: open.keys,
        file: phone.cloudCopy,
        backupId: PublicId.generate().value,
        createdAt: DateTime(2026, 11, 3, 21, 3),
        files: const {},
      );
    });
    first.lock();

    await show(tester, phone);
    await settleIn(tester);
    await settle(
      tester,
      () => find.text('還原 11 月 3 日的備份').evaluate().isNotEmpty,
    );
    expect(find.text('還原 11 月 3 日的備份'), findsOneWidget);
    expect(find.text('建立新帳本'), findsOneWidget);
    expect(find.text('還原備份'), findsNothing);

    await tester.tap(find.byKey(Keys.restoreFound));
    await tester.pump();
    expect(find.text('從備份還原'), findsOneWidget);
    expect(phone.state, isA<NeedsSetup>());
  });

  // What follows: the ways in once the ledger is made (no password, the
  // recovery code, the fingerprint), and the backup form's ways to find
  // a backup (the file picker, Google Drive, the ledger kept before an
  // earlier restore) and back out of it.

  /// Writes a backup of [startup]'s open ledger to [file].
  Future<void> backUp(WidgetTester tester, Startup startup, File file) =>
      tester.runAsync(() async {
        final open = (startup.state as Ready).vault;
        await file.parent.create(recursive: true);
        await LedgerBackup.write(
          store: open.store,
          keys: open.keys,
          file: file,
          backupId: PublicId.generate().value,
          createdAt: DateTime(2026, 11, 3, 21, 3),
          files: const {},
        );
      });

  testWidgets('a ledger without a password opens by itself after the '
      'opening', (tester) async {
    final first = Startup(vault);
    await tester.runAsync(first.setUpWithoutPassword);
    first.lock();
    final startup = Startup(vault);
    await show(tester, startup);
    expect(find.text('忘記密碼？'), findsNothing, reason: 'nothing asked');
    await settleIn(tester);
    await settle(tester, () => startup.state is Ready);
    expect(startup.state, isA<Ready>());
    startup.lock();
  });

  testWidgets('a ledger without a password opens while the opening plays, '
      'not after it (ARC-06)', (tester) async {
    final first = Startup(vault);
    await tester.runAsync(first.setUpWithoutPassword);
    first.lock();
    final startup = Startup(vault);
    await show(tester, startup);
    // Frames drawn with no time passing: the opening (1.4 s) cannot have
    // played, so only an unlock begun beside it opens the ledger.
    await settle(tester, () => startup.state is Ready);
    expect(startup.state, isA<Ready>());
    expect(find.byType(LockSplash), findsOneWidget);
    startup.lock();
  });

  testWidgets('a ledger without a password whose key cannot open it says '
      'so and asks for the password', (tester) async {
    final first = Startup(vault);
    await tester.runAsync(first.setUpWithoutPassword);
    first.lock();
    File('${directory.path}/quick-open.sealed').writeAsStringSync('not sealed');
    final startup = Startup(vault);
    await show(tester, startup);
    await settleIn(tester);
    await settle(
      tester,
      () => find.textContaining('無法打開帳本').evaluate().isNotEmpty,
    );
    expect(find.text('無法打開帳本，可在診斷匯出詳細資料'), findsOneWidget);
    expect(find.text('忘記密碼？'), findsOneWidget);
    expect(startup.state, isA<Locked>());
  });

  testWidgets('忘記密碼？ asks for the recovery code, which opens the ledger '
      'and keeps its password until a new one is set (SEC-04)', (tester) async {
    final startup = Startup(vault);
    late String code;
    await tester.runAsync(() async => code = await startup.setUp(password));
    startup.lock();
    await show(tester, startup);
    final semantics = tester.ensureSemantics();
    await press(tester, '忘記密碼？');
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('忘記密碼？'), findsNothing);
    expect(find.text('救援碼'), findsWidgets);

    await tester.enterText(find.byType(TextField), '  $code  ');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await settle(tester, () => startup.state is Ready);
    expect(startup.state, isA<Ready>());
    expect(startup.passwordless, isFalse);
    expect(startup.needsNewPassword, isTrue);
    startup.lock();
    semantics.dispose();
  });

  testWidgets('a wrong recovery code says so; 改用密碼 goes back to the '
      'password', (tester) async {
    final startup = await opened(tester);
    startup.lock();
    await show(tester, startup);
    final semantics = tester.ensureSemantics();
    await press(tester, '忘記密碼？');
    await tester.pump(const Duration(milliseconds: 500));
    // Another ledger's code: well formed, but not this one's.
    final other = Directory.systemTemp.createTempSync('lock-screen-other-');
    addTearDown(() => other.deleteSync(recursive: true));
    final another = Startup(
      LedgerVault(
        other,
        codec: KeyringCodec(kdf: PasswordKdf.insecureForTests),
      ),
    );
    late String code;
    await tester.runAsync(() async => code = await another.setUp(password));
    another.lock();
    await tester.enterText(find.byType(TextField), code);
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await settle(tester, () => find.text('救援碼不正確').evaluate().isNotEmpty);
    expect(find.text('救援碼不正確'), findsOneWidget);
    expect(startup.state, isA<Locked>());

    await press(tester, '改用密碼');
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('忘記密碼？'), findsOneWidget);
    semantics.dispose();
  });

  group('with a fingerprint', () {
    late _DeviceKey key;

    setUp(() => key = _DeviceKey());

    testWidgets('before a password unlock enrolled it, the fingerprint '
        'asked for as the screen opens says to use the password once', (
      tester,
    ) async {
      final first = await opened(tester);
      first.lock();
      final startup = Startup(vault, device: DeviceUnlock('phone', key));
      startup.takeOpening();
      await show(tester, startup);
      await settle(
        tester,
        () => find.text('先用密碼打開一次，之後就能用生物辨識解鎖').evaluate().isNotEmpty,
      );
      expect(find.text('先用密碼打開一次，之後就能用生物辨識解鎖'), findsOneWidget);
      expect(startup.state, isA<Locked>());
    });

    testWidgets('once enrolled, the fingerprint asked for as the opening '
        'begins opens the ledger while it plays (ARC-06)', (tester) async {
      final enrol = Startup(vault, device: DeviceUnlock('phone', key));
      await tester.runAsync(() => enrol.setUp(password));
      enrol.lock();
      final startup = Startup(vault, device: DeviceUnlock('phone', key));
      await show(tester, startup);
      // No time passes: the opening is still playing when it opens.
      await settle(tester, () => startup.state is Ready);
      expect(startup.state, isA<Ready>());
      expect(find.byType(LockSplash), findsOneWidget);
      startup.lock();
    });

    testWidgets('a fingerprint that does not open the ledger says to use '
        'the password, and the fingerprint can be tried again', (tester) async {
      final enrol = Startup(vault, device: DeviceUnlock('phone', key));
      await tester.runAsync(() => enrol.setUp(password));
      enrol.lock();
      // Another phone's key: the one kept does not open with it.
      final startup = Startup(
        vault,
        device: DeviceUnlock('phone', _DeviceKey()),
      );
      startup.takeOpening();
      await show(tester, startup);
      await settle(
        tester,
        () => find.textContaining('改用密碼').evaluate().isNotEmpty,
      );
      expect(find.text('生物辨識解鎖失敗，請改用密碼'), findsOneWidget);
      expect(startup.state, isA<Locked>());
      // A key that does not open the ledger is a fault worth keeping.
      expect(ErrorLog.instance.entries.first.$2, contains('生物辨識解鎖'));

      final semantics = tester.ensureSemantics();
      await press(tester, '用生物辨識解鎖');
      await settle(
        tester,
        () => find.textContaining('改用密碼').evaluate().isNotEmpty,
      );
      expect(startup.state, isA<Locked>());
      semantics.dispose();
    });

    testWidgets('choosing the password on the fingerprint prompt says '
        'nothing is wrong and notes no fault (F52)', (tester) async {
      final enrol = Startup(vault, device: DeviceUnlock('phone', key));
      await tester.runAsync(() => enrol.setUp(password));
      enrol.lock();
      final startup = Startup(
        vault,
        device: DeviceUnlock('phone', _TurnedDown(key)),
      );
      startup.takeOpening();
      final noted = ErrorLog.instance.entries.length;
      await show(tester, startup);
      // The prompt, asked as the screen opens, is turned down.
      await settle(
        tester,
        () => find.byKey(Keys.fingerprint).evaluate().isNotEmpty,
      );
      expect(find.byKey(Keys.fingerprint), findsOneWidget, reason: 'not busy');
      expect(find.text('生物辨識解鎖失敗，請改用密碼'), findsNothing);
      expect(find.text('生物辨識解鎖已取消，可以改用密碼'), findsNothing);
      expect(startup.state, isA<Locked>());
      expect(ErrorLog.instance.entries.length, noted);
      // And the password then opens the ledger.
      await tester.enterText(find.byType(TextField), password);
      await tester.testTextInput.receiveAction(TextInputAction.go);
      await settle(tester, () => startup.state is Ready);
      expect(startup.state, isA<Ready>());
      startup.lock();
    });

    testWidgets('a fingerprint failure said is gone when the fingerprint is '
        'tried again (F38)', (tester) async {
      final enrol = Startup(vault, device: DeviceUnlock('phone', key));
      await tester.runAsync(() => enrol.setUp(password));
      enrol.lock();
      final turned = _TurnedDown(_DeviceKey())..declines = false;
      final startup = Startup(vault, device: DeviceUnlock('phone', turned));
      startup.takeOpening();
      await show(tester, startup);
      await settle(
        tester,
        () => find.text('生物辨識解鎖失敗，請改用密碼').evaluate().isNotEmpty,
      );
      expect(find.text('生物辨識解鎖失敗，請改用密碼'), findsOneWidget);
      // Tried again, and this time turned down: the old words are gone.
      turned.declines = true;
      await tester.tap(find.byKey(Keys.fingerprint));
      await tester.pump();
      expect(find.text('生物辨識解鎖失敗，請改用密碼'), findsNothing);
      // The prompt is turned down: still nothing said, and not busy.
      await settle(tester, () => turned.turnedDown > 0);
      await settle(
        tester,
        () => find.byKey(Keys.fingerprint).evaluate().isNotEmpty,
      );
      expect(find.byKey(Keys.fingerprint), findsOneWidget);
      expect(find.text('生物辨識解鎖失敗，請改用密碼'), findsNothing);
    });

    testWidgets('a fingerprint turned off in settings is not offered on the '
        'lock screen (F39)', (tester) async {
      final enrol = Startup(vault, device: DeviceUnlock('phone', key));
      await tester.runAsync(() => enrol.setUp(password));
      await tester.runAsync(enrol.removeDevice);
      enrol.lock();
      final startup = Startup(vault, device: DeviceUnlock('phone', key));
      startup.takeOpening();
      await show(tester, startup);
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(Keys.fingerprint), findsNothing);
    });

    testWidgets('a fingerprint prompt that is cancelled says so', (
      tester,
    ) async {
      final enrol = Startup(vault, device: DeviceUnlock('phone', key));
      await tester.runAsync(() => enrol.setUp(password));
      enrol.lock();
      final startup = Startup(
        vault,
        device: DeviceUnlock(
          'phone',
          key,
          hasKey: () async => throw StateError('cancelled'),
        ),
      );
      startup.takeOpening();
      await show(tester, startup);
      await settle(
        tester,
        () => find.text('生物辨識解鎖已取消，可以改用密碼').evaluate().isNotEmpty,
      );
      expect(find.text('生物辨識解鎖已取消，可以改用密碼'), findsOneWidget);
      expect(startup.state, isA<Locked>());
    });

    testWidgets('a fingerprint whose key the phone dropped asks for the '
        'password once more', (tester) async {
      final enrol = Startup(vault, device: DeviceUnlock('phone', key));
      await tester.runAsync(() => enrol.setUp(password));
      enrol.lock();
      final startup = Startup(
        vault,
        device: DeviceUnlock('phone', key, hasKey: () async => false),
      );
      startup.takeOpening();
      await show(tester, startup);
      await settle(
        tester,
        () => find.text('先用密碼打開一次，之後就能用生物辨識解鎖').evaluate().isNotEmpty,
      );
      expect(find.text('先用密碼打開一次，之後就能用生物辨識解鎖'), findsOneWidget);
    });
  });

  group('restoring a backup', () {
    late Directory elsewhere;
    late File backup;

    setUp(() {
      elsewhere = Directory.systemTemp.createTempSync('lock-screen-backup-');
      backup = File('${elsewhere.path}/記帳本.etbk');
    });

    tearDown(() => elsewhere.deleteSync(recursive: true));

    /// The recovery code of the ledger [backedUp] made.
    late String code;

    /// A ledger with a password backed up to [backup], then locked.
    Future<Startup> backedUp(WidgetTester tester) async {
      final startup = Startup(vault);
      await tester.runAsync(() async => code = await startup.setUp(password));
      await backUp(tester, startup, backup);
      startup.lock();
      return startup;
    }

    Future<void> showWith(
      WidgetTester tester,
      Startup startup,
      RestoreSources sources,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: LockScreen(startup: startup, sources: sources),
        ),
      );
      await tester.pump();
    }

    testWidgets('from settings, a backup whose path is typed is restored '
        'with its recovery code, not the app password (SEC-02)', (
      tester,
    ) async {
      final startup = await backedUp(tester);
      startup.lockToRestore();
      await show(tester, startup);
      await tester.enterText(find.byType(TextField).first, backup.path);
      await tester.enterText(find.byType(TextField).last, password);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(
        tester,
        () => find.text('救援碼的格式不對，請檢查是否少打或打錯字').evaluate().isNotEmpty,
      );
      expect(startup.state, isA<Locked>());
      await tester.enterText(find.byType(TextField).last, code);
      // 完成 on the keyboard under the code restores.
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester, () => startup.state is Ready);
      expect(startup.state, isA<Ready>());
      expect(startup.needsNewPassword, isTrue);
      startup.lock();
    });

    testWidgets('a backup restored goes on from above the revision the app '
        'knows delivered (review 28)', (tester) async {
      final startup = await backedUp(tester);
      startup.lockToRestore();
      var asked = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: LockScreen(
            startup: startup,
            sources: RestoreSources(
              deliveredRevision: () {
                asked++;
                return 57;
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.enterText(find.byType(TextField).first, backup.path);
      await tester.enterText(find.byType(TextField).last, code);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester, () => startup.state is Ready);
      // The book and its backup hold a few writes; 57 was delivered:
      // 57 + 1.
      expect((startup.state as Ready).vault.store.revision, 58);
      expect(asked, 1);
      startup.lock();
    });

    testWidgets('a backup chosen says it opens with its recovery code; one '
        'older than the ledger it replaces is restored only once confirmed, '
        'both shown (SEC-10)', (tester) async {
      final startup = await backedUp(tester);
      // The ledger has grown since: kept just now with two records more.
      final open = await tester.runAsync(
        () => vault.unlockWithPassword(password),
      );
      open!.store.write((w) {
        w.put('entry', 'e1', '{"amount":1}');
        w.put('entry', 'e2', '{"amount":2}');
      });
      final keptFile = File('${elsewhere.path}/kept.etbk');
      await tester.runAsync(
        () => LedgerBackup.write(
          store: open.store,
          keys: open.keys,
          file: keptFile,
          backupId: 'kept',
          createdAt: DateTime(2026, 11, 20, 9, 30),
        ),
      );
      open.close();
      final kept = await tester.runAsync(
        () => LedgerBackup.readHeader(keptFile),
      );
      startup.lockToRestore(kept);
      var next = backup.path;
      await showWith(
        tester,
        startup,
        RestoreSources(pickFile: () async => next),
      );
      final semantics = tester.ensureSemantics();
      await press(tester, '選擇備份檔');
      await settle(
        tester,
        () => find.textContaining('的備份 · ').evaluate().isNotEmpty,
      );
      expect(find.text('這份備份要用救援碼打開（不是 App 的密碼）'), findsOneWidget);
      expect(find.text('忘記密碼？用救援碼'), findsNothing);
      await tester.enterText(find.byType(TextField).last, code);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('備份比較舊'), findsOneWidget);
      expect(
        find.textContaining('目前的帳本：2 筆（2026/11/20 09:30 留下一份）'),
        findsOneWidget,
      );
      expect(
        find.textContaining('要還原的備份：0 筆（2026/11/3 21:03）'),
        findsOneWidget,
      );
      await go(tester, ['取消']);
      expect(startup.state, isA<Locked>());

      await tester.tap(find.byKey(Keys.restoreGo));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Keys.confirm));
      await tester.pump();
      await settle(tester, () => startup.state is Ready);
      expect(startup.state, isA<Ready>());
      startup.lock();
      next = '';
      semantics.dispose();
    });

    testWidgets('the file picked says when it was taken and how much it '
        'holds; a file that is not a backup is said so', (tester) async {
      final startup = await backedUp(tester);
      final other = File('${elsewhere.path}/notes.txt')
        ..writeAsStringSync('hello');
      var next = other.path;
      startup.lockToRestore();
      await showWith(
        tester,
        startup,
        RestoreSources(pickFile: () async => next),
      );
      final semantics = tester.ensureSemantics();
      expect(find.text('選擇備份檔'), findsOneWidget);
      await press(tester, '選擇備份檔');
      await settle(
        tester,
        () => find.text('這個檔案不是記帳本的備份').evaluate().isNotEmpty,
      );
      expect(find.text('這個檔案不是記帳本的備份'), findsOneWidget);
      expect(find.text('已選好備份檔'), findsOneWidget);
      // Why it could not be read is kept for the diagnostics log.
      expect(ErrorLog.instance.entries.first.$2, contains('讀取備份檔'));

      next = backup.path;
      await press(tester, '已選好備份檔');
      await settle(
        tester,
        () => find.textContaining('的備份 · ').evaluate().isNotEmpty,
      );
      expect(find.textContaining('2026/11/3 21:03 的備份 · '), findsOneWidget);
      // The picked copy is the app's own: left behind, it goes.
      await tester.pumpWidget(const SizedBox());
      expect(backup.existsSync(), isFalse);
      expect(other.existsSync(), isFalse);
      semantics.dispose();
    });

    testWidgets('a backup on Google Drive is listed, downloaded and '
        'described', (tester) async {
      final startup = await backedUp(tester);
      final http = FakeDrive()..folder = 'folder';
      http.files['b1'] = DriveRow(
        '記帳本 2026-11-03.etbk',
        backup.readAsBytesSync(),
        DateTime.utc(2026, 11, 3, 13, 3),
        null,
      );
      final cache = Directory('${elsewhere.path}/cache')..createSync();
      startup.lockToRestore();
      await showWith(
        tester,
        startup,
        RestoreSources(
          drive: () => DriveBackup(
            http,
            token: ({required interactive}) async => 'token',
            forget: (_) async {},
          ),
          cacheDirectory: () async => cache,
        ),
      );
      final semantics = tester.ensureSemantics();
      await press(tester, '從 Google 雲端硬碟選擇');
      await settle(
        tester,
        () => find.text('記帳本 2026-11-03.etbk').evaluate().isNotEmpty,
      );
      expect(find.text('記帳本 2026-11-03.etbk'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 500));
      await press(tester, RegExp('記帳本 2026-11-03.etbk'));
      await settle(
        tester,
        () => find.textContaining('的備份 · ').evaluate().isNotEmpty,
      );
      expect(find.textContaining('的備份 · '), findsOneWidget);
      expect(File('${cache.path}/restore.etbk').existsSync(), isTrue);
      semantics.dispose();
    });

    testWidgets('Google Drive with no backups says so', (tester) async {
      final startup = await backedUp(tester);
      final cache = Directory('${elsewhere.path}/cache')..createSync();
      startup.lockToRestore();
      await showWith(
        tester,
        startup,
        RestoreSources(
          drive: () => DriveBackup(
            FakeDrive()..folder = 'folder',
            token: ({required interactive}) async => 'token',
            forget: (_) async {},
          ),
          cacheDirectory: () async => cache,
        ),
      );
      final semantics = tester.ensureSemantics();
      await press(tester, '從 Google 雲端硬碟選擇');
      await settle(
        tester,
        () => find.textContaining('裡沒有備份').evaluate().isNotEmpty,
      );
      expect(find.text('Google 雲端硬碟的「記帳本備份」裡沒有備份'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('Google Drive that cannot be reached says why', (tester) async {
      final startup = await backedUp(tester);
      final cache = Directory('${elsewhere.path}/cache')..createSync();
      startup.lockToRestore();
      await showWith(
        tester,
        startup,
        RestoreSources(
          drive: () => DriveBackup(
            FakeDrive(),
            // Signing in to Google is turned down.
            token: ({required interactive}) async => null,
            forget: (_) async {},
          ),
          cacheDirectory: () async => cache,
        ),
      );
      final semantics = tester.ensureSemantics();
      await press(tester, '從 Google 雲端硬碟選擇');
      await settle(
        tester,
        () => find.text('沒有取得 Google 雲端硬碟的權限').evaluate().isNotEmpty,
      );
      expect(find.text('沒有取得 Google 雲端硬碟的權限'), findsOneWidget);
      expect(startup.state, isA<Locked>());
      semantics.dispose();
    });

    testWidgets('a backup from Google Drive that cannot be kept on the '
        'phone says why', (tester) async {
      final startup = await backedUp(tester);
      final http = FakeDrive()..folder = 'folder';
      http.files['b1'] = DriveRow(
        '記帳本 2026-11-03.etbk',
        backup.readAsBytesSync(),
        DateTime.utc(2026, 11, 3, 13, 3),
        null,
      );
      startup.lockToRestore();
      await showWith(
        tester,
        startup,
        RestoreSources(
          drive: () => DriveBackup(
            http,
            token: ({required interactive}) async => 'token',
            forget: (_) async {},
          ),
          cacheDirectory: () async =>
              throw const FileSystemException('No space left'),
        ),
      );
      final semantics = tester.ensureSemantics();
      await press(tester, '從 Google 雲端硬碟選擇');
      await settle(
        tester,
        () => find.text('記帳本 2026-11-03.etbk').evaluate().isNotEmpty,
      );
      await tester.pump(const Duration(milliseconds: 500));
      await press(tester, RegExp('記帳本 2026-11-03.etbk'));
      await settle(
        tester,
        () => find.textContaining('無法下載備份').evaluate().isNotEmpty,
      );
      expect(find.text('無法下載備份，可在診斷匯出詳細資料'), findsOneWidget);
      expect(find.textContaining('No space left'), findsNothing);
      semantics.dispose();
    });

    testWidgets('the ledger kept before an earlier restore can be chosen '
        'to go back to it', (tester) async {
      final startup = await backedUp(tester);
      startup.beforeRestore.createSync(recursive: true);
      final kept = backup.copySync('${startup.beforeRestore.path}/1.etbk');
      startup.lockToRestore();
      await show(tester, startup);
      final semantics = tester.ensureSemantics();
      await press(tester, '還原前自動留下的帳本');
      // Each kept backup's header is read first.
      await settle(
        tester,
        () => find.text('還原前自動留下的帳本').evaluate().length == 2,
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('還原前自動留下的帳本'), findsNWidgets(2));
      // Named by when its backup was taken, as its header says (F91).
      expect(find.text('2026/11/3 21:03 的帳本 · 0 筆'), findsOneWidget);
      await press(tester, RegExp('的帳本 · '));
      await settle(
        tester,
        () => find.textContaining('的備份 · ').evaluate().isNotEmpty,
      );
      expect(find.textContaining('的備份 · '), findsOneWidget);
      final path = tester
          .widgetList<TextField>(find.byType(TextField))
          .first
          .controller!
          .text;
      expect(path, kept.path);
      semantics.dispose();
    });

    testWidgets('the system back from the backup form returns to the '
        'ledger, and on a new phone to the choices', (tester) async {
      final startup = await backedUp(tester);
      startup.lockToRestore();
      await show(tester, startup);
      expect(find.text('從備份還原'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('忘記密碼？'), findsOneWidget);

      final fresh = Startup(
        LedgerVault(
          elsewhere,
          codec: KeyringCodec(kdf: PasswordKdf.insecureForTests),
        ),
      );
      await show(tester, fresh);
      await settleIn(tester);
      await tester.tap(find.byKey(Keys.restore));
      await tester.pump();
      expect(find.text('從備份還原'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('建立新帳本'), findsOneWidget);
    });
  });
}

/// A fingerprint key whose prompt the person turns down while [declines]:
/// 改用密碼, or back, as `DeviceKeyBlob.refusal` names it.
final class _TurnedDown implements DeviceKeyWrapper {
  _TurnedDown(this._key);

  final DeviceKeyWrapper _key;
  var declines = true;

  /// How many prompts were turned down.
  var turnedDown = 0;

  @override
  Future<List<int>> wrap(List<int> secret, List<int> context) =>
      _key.wrap(secret, context);

  @override
  Future<List<int>> unwrap(List<int> wrapped, List<int> context) async {
    if (declines) {
      turnedDown++;
      throw PlatformException(code: 'declined');
    }
    return _key.unwrap(wrapped, context);
  }
}

/// Stands in for an Android Keystore key: a blob opens only with the key
/// that wrapped it.
final class _DeviceKey implements DeviceKeyWrapper {
  final _secrets = <String, List<int>>{};

  @override
  Future<List<int>> wrap(List<int> secret, List<int> context) async {
    final handle = 'blob-${_secrets.length}';
    _secrets[handle] = List.of(secret);
    return handle.codeUnits;
  }

  @override
  Future<List<int>> unwrap(List<int> wrapped, List<int> context) async {
    final secret = _secrets[String.fromCharCodes(wrapped)];
    if (secret == null) throw StateError('not this device');
    return secret;
  }
}
