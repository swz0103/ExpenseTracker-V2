import 'dart:io';

import 'package:expense_tracker/src/core/design_system/keys.dart';
import 'package:core/foundation_values.dart';
import 'package:expense_tracker/src/core/platform/startup.dart';
import 'package:expense_tracker/src/features/backup/model/drive_backup.dart';
import 'package:expense_tracker/src/features/backup/model/restore_sources.dart';
import 'package:expense_tracker/src/features/lock/ui/lock_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault/backup_security.dart';
import 'package:vault/ledger_backup.dart';
import 'package:vault/ledger_vault.dart';

import '../../../support/fake_drive.dart';

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

  testWidgets('a wrong password says so and keeps the ledger locked', (
    tester,
  ) async {
    final startup = await opened(tester);
    startup.lock();
    await show(tester, startup);
    expect(find.text('忘記密碼？'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'not the password');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await settle(tester, () => find.text('密碼不正確').evaluate().isNotEmpty);
    expect(find.text('密碼不正確'), findsOneWidget);
    expect(startup.state, isA<Locked>());

    await tester.enterText(find.byType(TextField), password);
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await settle(tester, () => startup.state is Ready);
    expect(startup.state, isA<Ready>());
    startup.lock();
  });

  testWidgets('restoring from settings opens on the backup form, and back '
      'returns to this ledger', (tester) async {
    final startup = await opened(tester);
    startup.lockToRestore();
    await show(tester, startup);
    expect(find.text('從備份還原'), findsOneWidget);
    expect(startup.takeRestore(), isFalse, reason: 'asked once');
    await tester.tap(find.byKey(Keys.back));
    await tester.pump();
    expect(find.text('忘記密碼？'), findsOneWidget);
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

  /// Presses what a screen reader calls [label], then draws.
  Future<void> press(WidgetTester tester, Pattern label) async {
    await tester.tap(find.bySemanticsLabel(label).last);
    await tester.pump();
  }

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
      () => find.textContaining('無法開啟帳本').evaluate().isNotEmpty,
    );
    expect(find.textContaining('無法開啟帳本（'), findsOneWidget);
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
        () => find.text('先用密碼打開一次，之後就能用指紋解鎖').evaluate().isNotEmpty,
      );
      expect(find.text('先用密碼打開一次，之後就能用指紋解鎖'), findsOneWidget);
      expect(startup.state, isA<Locked>());
    });

    testWidgets('once enrolled, the fingerprint asked for after the opening '
        'opens the ledger', (tester) async {
      final enrol = Startup(vault, device: DeviceUnlock('phone', key));
      await tester.runAsync(() => enrol.setUp(password));
      enrol.lock();
      final startup = Startup(vault, device: DeviceUnlock('phone', key));
      await show(tester, startup);
      await settleIn(tester);
      await settle(tester, () => startup.state is Ready);
      expect(startup.state, isA<Ready>());
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
      expect(find.text('指紋解鎖失敗，請改用密碼'), findsOneWidget);
      expect(startup.state, isA<Locked>());

      final semantics = tester.ensureSemantics();
      await press(tester, '用指紋或臉部解鎖');
      await settle(
        tester,
        () => find.textContaining('改用密碼').evaluate().isNotEmpty,
      );
      expect(startup.state, isA<Locked>());
      semantics.dispose();
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
        () => find.text('指紋解鎖已取消，可以改用密碼').evaluate().isNotEmpty,
      );
      expect(find.text('指紋解鎖已取消，可以改用密碼'), findsOneWidget);
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
        () => find.text('先用密碼打開一次，之後就能用指紋解鎖').evaluate().isNotEmpty,
      );
      expect(find.text('先用密碼打開一次，之後就能用指紋解鎖'), findsOneWidget);
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
      expect(find.text('這份備份要用救援碼打開（不是 App 的密碼）。'), findsOneWidget);
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
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(startup.state, isA<Locked>());

      await tester.tap(find.widgetWithText(FilledButton, '還原'));
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
        () => find.textContaining('無法下載備份（').evaluate().isNotEmpty,
      );
      expect(find.textContaining('No space left'), findsOneWidget);
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
