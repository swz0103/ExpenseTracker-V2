import 'dart:io';

import 'package:expense_tracker/src/core/design_system/components/cards.dart';
import 'package:expense_tracker/src/core/design_system/keys.dart';
import 'package:expense_tracker/src/core/diagnostics/error_log.dart';
import 'package:expense_tracker/src/core/platform/preferences.dart';
import 'package:expense_tracker/src/core/platform/screen_privacy.dart';
import 'package:expense_tracker/src/features/backup/model/backup_manager.dart';
import 'package:expense_tracker/src/features/lock/ui/security_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/src/core/messages/key_failures.dart';
import 'package:vault/backup_security.dart';

import '../../../support/places.dart';

/// A ledger's keys without a ledger: remembers what it was asked, and
/// refuses as the vault does, by the error's type.
final class _StubBackupManager implements BackupManager {
  var password = '';
  var locked = false;
  var passphrase = '';
  var resets = <String?>[];

  @override
  var passwordBelowRule = false;

  /// What changing the password, or making a new code, fails with.
  Object? fails;
  Object? codeFails;
  var codes = 0;

  /// The calls that reached the keys.
  var calls = 0;

  @override
  Future<bool> exportBackup() async => true;

  @override
  Future<bool> exportFile(String name, String text) async => true;

  @override
  Future<String?> readFile() async => null;

  @override
  Future<bool> exportBytes(String name, List<int> bytes) async => true;

  @override
  DateTime? get cloudCopyAt => null;

  @override
  DateTime? get googleTakenAt => null;

  @override
  DateTime? get exportedAt => null;

  @override
  bool get hasPassword => password.isNotEmpty;

  @override
  String get passwordRule => passwordRuleWords;

  @override
  String? refusePassword(String password) => passwordRefusal(password);

  @override
  Future<void> setPassword(String next) async {
    calls++;
    password = next;
  }

  @override
  Future<void> changePassword(String current, String next) async {
    calls++;
    if (fails case final error?) {
      Error.throwWithStackTrace(error, StackTrace.current);
    }
    if (current != password) throw _wrong;
    password = next;
  }

  @override
  Future<String> newRecoveryCode() async {
    if (codeFails case final error?) {
      Error.throwWithStackTrace(error, StackTrace.current);
    }
    codes++;
    return 'ABCD-EFGH-IJKL';
  }

  @override
  bool get recoveryGiven => true;

  @override
  bool get hasBackupPassphrase => passphrase.isNotEmpty;

  @override
  Future<void> setBackupPassphrase(String next) async => passphrase = next;

  @override
  Future<void> removeBackupPassphrase() async => passphrase = '';

  @override
  Future<void> resetKeys(String? currentPassword) async {
    if (hasPassword && currentPassword != password) throw _wrong;
    resets.add(currentPassword);
  }

  @override
  Future<void> lock() async => locked = true;

  @override
  Future<String> restoreAnother() async => '';

  /// Whether the phone can confirm a fingerprint.
  var phoneHasFingerprint = false;

  @override
  bool get canUseFingerprint => hasPassword && phoneHasFingerprint;

  @override
  var fingerprintOn = false;

  /// What the phone's prompt ends with: confirmed, turned down, or a
  /// failure thrown.
  var promptConfirmed = true;
  Object? promptFails;

  /// Each turn asked of the keys.
  final turns = <bool>[];

  @override
  Future<bool> turnFingerprint({required bool on}) async {
    turns.add(on);
    if (promptFails case final error?) {
      Error.throwWithStackTrace(error, StackTrace.current);
    }
    if (on && !promptConfirmed) return false;
    fingerprintOn = on;
    return true;
  }
}

/// A wrong current password, as EncryptedBackupManager says it.
final _wrong = KeyRefused(
  keyRefusal(const KeyringException(KeyringError.wrongSecret))!,
);

/// The rule's words, as the app says them.
final passwordRuleWords = passwordRule;

void main() {
  Future<void> show(
    WidgetTester tester,
    BackupManager? backupManager, {
    ScreenPrivacy? privacy,
    Preferences? preferences,
  }) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              SecuritySection(
                backupManager: backupManager,
                privacy: privacy,
                preferences: preferences,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Types [fields] into the open panel's fields, then its main button.
  Future<void> type(WidgetTester tester, List<String> fields) async {
    for (final (i, text) in fields.indexed) {
      await tester.enterText(find.byType(TextField).at(i), text);
    }
    await tester.tap(find.byKey(Keys.changePassword));
    await tester.pumpAndSettle();
  }

  /// Opens 密碼 and types [fields] into its fields, then 變更.
  Future<void> change(WidgetTester tester, List<String> fields) async {
    await tester.tap(find.byKey(Keys.password));
    await tester.pumpAndSettle();
    await type(tester, fields);
  }

  /// What the panel's fields hold now.
  List<String> typed(WidgetTester tester) => [
    for (final field in tester.widgetList<TextField>(find.byType(TextField)))
      field.controller!.text,
  ];

  testWidgets('new passwords that differ are said in the panel, with what '
      'was typed kept (F97)', (tester) async {
    final backupManager = _StubBackupManager();
    await show(tester, backupManager);
    expect(find.text('還沒設定 · 點了設定'), findsOneWidget);
    expect(find.text('現在鎖上'), findsNothing);
    await tester.tap(find.byKey(Keys.password));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.textContaining('至少 8 個字，不能全是數字'), findsOneWidget);
    await type(tester, ['apple pie 1', 'apple pie 2']);
    expect(find.text('兩次輸入的新密碼不一樣'), findsOneWidget);
    expect(typed(tester), ['apple pie 1', 'apple pie 2']);
    expect(backupManager.calls, 0);
  });

  testWidgets('a new password against the rule is said in the panel '
      '(SEC-02, F97)', (tester) async {
    final backupManager = _StubBackupManager()..password = 'old secret';
    await show(tester, backupManager);
    await change(tester, ['old secret', 'abc', 'abc']);
    expect(find.text('至少要 8 個字'), findsOneWidget);
    expect(typed(tester), ['old secret', 'abc', 'abc']);
    // Six digits, the lock screen's old suggestion, are refused too.
    await type(tester, ['old secret', '12345678', '12345678']);
    expect(find.text('不能全是數字，請加上文字或符號'), findsOneWidget);
    expect(backupManager.calls, 0);
    expect(backupManager.password, 'old secret');
  });

  testWidgets('a wrong current password is said in the panel, which stays '
      'open with what was typed; then it goes through (F97, SEC-13)', (
    tester,
  ) async {
    final backupManager = _StubBackupManager()..password = 'old secret';
    await show(tester, backupManager);
    expect(find.text('現在鎖上'), findsOneWidget);
    await change(tester, ['wrong one', 'new secret', 'new secret']);
    expect(find.text('目前的密碼不正確'), findsOneWidget);
    expect(typed(tester), ['wrong one', 'new secret', 'new secret']);
    expect(backupManager.password, 'old secret');

    await type(tester, ['old secret']);
    expect(find.byType(TextField), findsNothing, reason: 'closed');
    expect(backupManager.password, 'new secret');
    expect(find.text('密碼已變更'), findsOneWidget);

    await tester.tap(find.byKey(Keys.lockNow));
    await tester.pump();
    expect(backupManager.locked, isTrue);
  });

  testWidgets('the first password set shows the recovery code once, then '
      'says it is set', (tester) async {
    final backupManager = _StubBackupManager();
    await show(tester, backupManager);
    await change(tester, ['apple pie 1', 'apple pie 1']);
    expect(backupManager.password, 'apple pie 1');
    expect(find.text('新的救援碼'), findsOneWidget);
    expect(find.text('密碼設好了。忘記密碼時，只有它能打開帳本'), findsOneWidget);
    await go(tester, ['存好了']);
    expect(find.text('新的救援碼'), findsNothing);
    expect(find.text('已設定密碼'), findsOneWidget);
    expect(find.text('已設定 · 點了變更'), findsOneWidget);
    expect(find.text('現在鎖上'), findsOneWidget);
  });

  testWidgets('changing the password says what it does not change', (
    tester,
  ) async {
    final backupManager = _StubBackupManager()..password = 'old secret';
    await show(tester, backupManager);
    await tester.tap(find.byKey(Keys.password));
    await tester.pumpAndSettle();
    expect(find.textContaining('已經存在的舊備份不會改變，仍可用當時的密碼或救援碼打開'), findsOneWidget);
    await type(tester, ['old secret', 'new secret', 'new secret']);
    expect(backupManager.password, 'new secret');
    expect(backupManager.codes, 0, reason: 'the code stays');
  });

  testWidgets('a failure not foreseen is said in the panel', (tester) async {
    final backupManager = _StubBackupManager()
      ..password = 'old secret'
      ..fails = const FileSystemException('disk full');
    await show(tester, backupManager);
    await change(tester, ['old secret', 'new secret', 'new secret']);
    expect(find.text('沒有完成，請再試一次'), findsOneWidget);
    expect(backupManager.password, 'old secret');
  });

  testWidgets('a password in use below the rule is pointed out, not '
      'refused', (tester) async {
    final backupManager = _StubBackupManager()
      ..password = '123456'
      ..passwordBelowRule = true;
    await show(tester, backupManager);
    expect(find.text('目前的密碼比現在的規定短或太簡單，仍可使用，建議變更'), findsOneWidget);
  });

  testWidgets('救援碼 makes a new code only once agreed, saying what old '
      'backups still open with, and shows it', (tester) async {
    final backupManager = _StubBackupManager()..password = 'old secret';
    await show(tester, backupManager);
    await go(tester, ['忘記密碼、換手機用']);
    expect(find.textContaining('已經存在的舊備份仍可用舊的救援碼打開'), findsOneWidget);
    await go(tester, ['取消']);
    expect(backupManager.codes, 0);

    await go(tester, ['忘記密碼、換手機用']);
    await tester.tap(find.byKey(Keys.confirm));
    await tester.pumpAndSettle();
    expect(backupManager.codes, 1);
    expect(find.text('新的救援碼'), findsOneWidget);
    expect(find.text('忘記密碼時，只有它能打開帳本'), findsOneWidget);
  });

  testWidgets('a new code that cannot be made says so', (tester) async {
    final backupManager = _StubBackupManager()
      ..codeFails = StateError('keystore');
    await show(tester, backupManager);
    await go(tester, ['忘記密碼、換手機用']);
    await tester.tap(find.byKey(Keys.confirm));
    await tester.pumpAndSettle();
    expect(find.textContaining('沒有換成：'), findsOneWidget);
    expect(find.text('新的救援碼'), findsNothing);
  });

  testWidgets('a backup passphrase is set under the rule, and can be '
      'dropped', (tester) async {
    final backupManager = _StubBackupManager()..password = 'old secret';
    await show(tester, backupManager);
    expect(find.text('沒有設定 · 備份只能用救援碼打開'), findsOneWidget);
    await tester.tap(find.byKey(Keys.passphrase));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(2));
    await tester.enterText(find.byType(TextField).at(0), 'short');
    await tester.enterText(find.byType(TextField).at(1), 'short');
    await go(tester, ['設定']);
    expect(find.text('至少要 8 個字'), findsOneWidget);
    expect(backupManager.passphrase, '');
    await tester.enterText(
      find.byType(TextField).at(0),
      'a long backup phrase',
    );
    await tester.enterText(
      find.byType(TextField).at(1),
      'a long backup phrase',
    );
    await go(tester, ['設定']);
    expect(backupManager.passphrase, 'a long backup phrase');
    expect(find.text('已設定 · 備份可用它或救援碼打開'), findsOneWidget);

    await tester.tap(find.byKey(Keys.passphrase));
    await tester.pumpAndSettle();
    await go(tester, ['停用']);
    expect(find.textContaining('之後的備份只能用救援碼還原'), findsOneWidget);
    await tester.tap(find.byKey(Keys.confirm));
    await tester.pumpAndSettle();
    expect(backupManager.passphrase, '');
  });

  testWidgets('重設金鑰 says what it does, asks for the password, and says a '
      'wrong one in the panel (SEC-06)', (tester) async {
    final backupManager = _StubBackupManager()..password = 'old secret';
    await show(tester, backupManager);
    await tester.tap(find.byKey(Keys.resetKeys));
    await tester.pumpAndSettle();
    expect(find.textContaining('資料庫與收據照片重新加密'), findsOneWidget);
    expect(find.textContaining('已經存在的舊備份'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'wrong one');
    await tester.tap(find.byKey(Keys.resetGo));
    await tester.pumpAndSettle();
    expect(find.text('目前的密碼不正確'), findsOneWidget);
    expect(backupManager.resets, isEmpty);
    await tester.enterText(find.byType(TextField), 'old secret');
    await tester.tap(find.byKey(Keys.resetGo));
    await tester.pumpAndSettle();
    expect(backupManager.resets, ['old secret']);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('重設金鑰 without a password asks for none', (tester) async {
    final backupManager = _StubBackupManager();
    await show(tester, backupManager);
    await tester.tap(find.byKey(Keys.resetKeys));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.byKey(Keys.resetGo));
    await tester.pumpAndSettle();
    expect(backupManager.resets, [null]);
  });

  testWidgets('禁止截圖 is turned on and off, and the card says what it '
      'does', (tester) async {
    final privacy = ScreenPrivacy.inMemory();
    await show(tester, null, privacy: privacy);
    expect(find.text('密碼'), findsNothing, reason: 'no keys to show');
    // Off, the lock screen is still kept out of screenshots (SEC-08).
    expect(find.text('只有解鎖畫面擋下截圖'), findsOneWidget);
    await go(tester, ['禁止截圖']);
    expect(privacy.on, isTrue);
    expect(find.text('截圖、錄影都擋下'), findsOneWidget);
    await go(tester, ['截圖、錄影都擋下']);
    expect(privacy.on, isFalse);
  });

  group('生物辨識解鎖 (F39, F40)', () {
    _StubBackupManager keys({bool on = false}) => _StubBackupManager()
      ..password = 'a password'
      ..phoneHasFingerprint = true
      ..fingerprintOn = on;

    bool switchOn(WidgetTester tester) =>
        tester.widget<SettingCard>(find.byKey(Keys.fingerprintSwitch)).value!;

    int noted() => ErrorLog.instance.entries.length;

    testWidgets('a phone with a fingerprint and a ledger with a password '
        'has the switch, off until turned on', (tester) async {
      final backupManager = keys();
      await show(tester, backupManager);
      expect(find.byKey(Keys.fingerprintSwitch), findsOneWidget);
      expect(switchOn(tester), isFalse);
      expect(find.text('已關閉 · 只用密碼打開帳本'), findsOneWidget);
    });

    testWidgets('turning it on asks the phone once, and says it is on', (
      tester,
    ) async {
      final backupManager = keys();
      await show(tester, backupManager);
      await tester.tap(find.byKey(Keys.fingerprintSwitch));
      await tester.pumpAndSettle();
      expect(backupManager.turns, [true]);
      expect(switchOn(tester), isTrue);
      expect(find.text('已開啟 · 可用生物辨識打開帳本'), findsOneWidget);
      expect(find.text('已開啟生物辨識解鎖'), findsOneWidget);
    });

    testWidgets('turning it off needs no prompt, and says it is off', (
      tester,
    ) async {
      final backupManager = keys(on: true);
      await show(tester, backupManager);
      expect(switchOn(tester), isTrue);
      await tester.tap(find.byKey(Keys.fingerprintSwitch));
      await tester.pumpAndSettle();
      expect(backupManager.turns, [false]);
      expect(switchOn(tester), isFalse);
      expect(find.text('已關閉生物辨識解鎖'), findsOneWidget);
    });

    testWidgets('turning the phone\'s prompt down leaves it off with no '
        'error said and none noted', (tester) async {
      final backupManager = keys()..promptConfirmed = false;
      final before = noted();
      await show(tester, backupManager);
      await tester.tap(find.byKey(Keys.fingerprintSwitch));
      await tester.pumpAndSettle();
      expect(backupManager.turns, [true]);
      expect(switchOn(tester), isFalse);
      expect(find.text('沒有完成，請再試一次'), findsNothing);
      expect(find.text('已開啟生物辨識解鎖'), findsNothing);
      expect(noted(), before);
    });

    testWidgets('a failure to turn it on is said and noted', (tester) async {
      final backupManager = keys()..promptFails = StateError('keystore');
      final before = noted();
      await show(tester, backupManager);
      await tester.tap(find.byKey(Keys.fingerprintSwitch));
      await tester.pumpAndSettle();
      expect(switchOn(tester), isFalse);
      expect(find.text('沒有完成，請再試一次'), findsOneWidget);
      expect(noted(), before + 1);
    });

    testWidgets('without a fingerprint on the phone, or without a password, '
        'there is no switch', (tester) async {
      await show(tester, _StubBackupManager()..password = 'a password');
      expect(find.byKey(Keys.fingerprintSwitch), findsNothing);
      await show(tester, _StubBackupManager()..phoneHasFingerprint = true);
      await tester.pump();
      expect(find.byKey(Keys.fingerprintSwitch), findsNothing);
    });
  });

  group('自動上鎖 (SEC-07)', () {
    testWidgets('a ledger with a password says the time in force, 5 分鐘 '
        'until chosen', (tester) async {
      final preferences = Preferences();
      await show(
        tester,
        _StubBackupManager()..password = 'a password',
        preferences: preferences,
      );
      expect(find.byKey(Keys.autoLock), findsOneWidget);
      expect(find.text('離開 5 分鐘後上鎖'), findsOneWidget);
    });

    testWidgets('the card offers every choice; the one picked is kept and '
        'said', (tester) async {
      final preferences = Preferences();
      await show(
        tester,
        _StubBackupManager()..password = 'a password',
        preferences: preferences,
      );
      await tester.tap(find.byKey(Keys.autoLock));
      await tester.pumpAndSettle();
      for (final name in [
        'immediately',
        'oneMinute',
        'fiveMinutes',
        'fifteenMinutes',
        'never',
      ]) {
        expect(find.byKey(Keys.autoLockChoice(name)), findsOneWidget);
      }
      await tester.tap(find.byKey(Keys.autoLockChoice('immediately')));
      await tester.pumpAndSettle();
      expect(preferences.autoLock, AutoLock.immediately);
      expect(find.text('一離開 App 就上鎖'), findsOneWidget);
      await tester.tap(find.byKey(Keys.autoLockChoice('never')));
      await tester.pumpAndSettle();
      expect(preferences.autoLock, AutoLock.never);
      expect(find.text('只有關閉 App 後才需要解鎖'), findsOneWidget);
    });

    testWidgets('a ledger without a password, which never locks, has no '
        'such card', (tester) async {
      await show(tester, _StubBackupManager(), preferences: Preferences());
      expect(find.byKey(Keys.autoLock), findsNothing);
    });
  });

  testWidgets('a phone that cannot hide its screen says so', (tester) async {
    final directory = Directory.systemTemp.createTempSync('privacy-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final privacy = ScreenPrivacy(
      directory,
      (on) async => throw StateError('no window'),
    );
    await show(tester, null, privacy: privacy);
    await go(tester, ['禁止截圖']);
    for (var i = 0; i < 50; i++) {
      if (find.text('這支手機無法切換截圖設定').evaluate().isNotEmpty) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
    }
    expect(find.text('這支手機無法切換截圖設定'), findsOneWidget);
  });
}
