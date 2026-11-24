import 'dart:io';

import 'package:core/app_core.dart' show FixedClock;
import 'package:expense_tracker/src/app/first_screen.dart';
import 'package:expense_tracker/src/app/load_failed_page.dart';
import 'package:expense_tracker/src/app/quarantine_notices.dart';
import 'package:expense_tracker/src/app/upgrade_held_page.dart';
import 'package:expense_tracker/src/core/design_system/keys.dart';
import 'package:expense_tracker/src/core/ledger/persistence/quarantine.dart';
import 'package:expense_tracker/src/core/ledger/persistence/upgrade_backup.dart';
import 'package:expense_tracker/src/core/platform/preferences.dart';
import 'package:expense_tracker/src/core/platform/startup.dart';
import 'package:expense_tracker/src/core/time/app_clock.dart';
import 'package:expense_tracker/src/features/backup/model/drive_backup.dart';
import 'package:expense_tracker/src/features/backup/model/old_key_backups.dart';
import 'package:expense_tracker/src/features/backup/ui/old_key_backups_offer.dart';
import 'package:expense_tracker/src/features/lock/ui/lock_screen.dart';
import 'package:expense_tracker/src/features/lock/ui/security_section.dart';
import 'package:expense_tracker/src/features/lock/ui/views/new_password_view.dart';
import 'package:expense_tracker/src/features/reminders/model/calendar_sync.dart';
import 'package:expense_tracker/src/features/reminders/model/reminder_alerts.dart';
import 'package:expense_tracker/src/features/reminders/ui/reminders_section.dart';
import 'package:core/foundation_values.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault/backup_security.dart';
import 'package:vault/ledger_vault.dart';

import 'fake_calendar.dart';
import 'place.dart';
import 'review_book.dart';

/// The password of the ledgers below.
const _password = 'correct horse battery';

/// The screens the shell never shows, and the panels over them, each
/// built where it stands (a lock screen on a ledger in a folder of its
/// own, a dialog opened from a button): the pages before the ledger is
/// open, what is told as it opens, and the cards of 安全 and 通知與提醒
/// with a password, a fingerprint, a phone short of what is allowed and a
/// calendar to link. Not reached by taps from the tabs, so places.dart's
/// paths cannot name them.
final builtPlaces = <Place>[
  // The pages before the ledger is open.
  for (final (name, page) in <(String, Widget Function())>[
    (
      'ledger load failed',
      () => LoadFailedPage(onRetry: () {}, onRestore: () {}, onExport: () {}),
    ),
    (
      'ledger load failed, no restore',
      () => LoadFailedPage(onRetry: () {}, onRestore: null, onExport: () {}),
    ),
    ('ledger damaged', () => DamagedBookPage(onRetry: () {}, onRestore: () {})),
    (
      'upgrade held, no space',
      () => UpgradeHeldPage(
        failure: UpgradeBackupFailed(
          UpgradeBackupProblem.noSpace,
          StateError('x'),
        ),
        onRetry: () {},
        onExport: () {},
        onWithoutBackup: () {},
      ),
    ),
    (
      'upgrade held, other',
      () => UpgradeHeldPage(
        failure: UpgradeBackupFailed(
          UpgradeBackupProblem.other,
          StateError('x'),
        ),
        onRetry: () {},
        onExport: () {},
        onWithoutBackup: () {},
      ),
    ),
    (
      'new password',
      () => Scaffold(
        body: NewPasswordView(onSet: (_) async {}, onNoPassword: () async {}),
      ),
    ),
  ])
    Place(name, (tester, look) => showScene(tester, look, page(), height: 800)),

  Place(
    'start failed',
    (tester, look) => _standalone(tester, look, StartFailedApp(retry: () {})),
  ),

  // The lock screens, on a ledger with a password.
  Place('welcome', (tester, look) async {
    final startup = Startup(_vault());
    await showScene(tester, look, LockScreen(startup: startup), height: 800);
  }),
  Place('restore form', (tester, look) async {
    final startup = Startup(_vault());
    await showScene(tester, look, LockScreen(startup: startup), height: 800);
    await tester.tap(find.byKey(Keys.restore));
    await tester.pump(const Duration(seconds: 2));
  }),
  Place('unlock', (tester, look) async {
    final startup = await _locked(tester);
    await showScene(tester, look, LockScreen(startup: startup), height: 800);
  }),
  Place('unlock, wrong password', (tester, look) async {
    final startup = await _locked(tester);
    await showScene(tester, look, LockScreen(startup: startup), height: 800);
    await tester.enterText(find.byType(TextField), 'not the password');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }),
  Place('unlock, waiting', (tester, look) async {
    AppClock.use(FixedClock(UtcInstant(DateTime.utc(2026, 11, 23, 9))));
    addTearDown(AppClock.reset);
    final startup = await _locked(tester);
    await tester.runAsync(() async {
      for (var i = 0; i < 5; i++) {
        try {
          await startup.unlockWithPassword('wrong $i');
        } on KeyringException {
          // Refused, and counted.
        }
      }
    });
    await showScene(tester, look, LockScreen(startup: startup), height: 800);
  }),
  Place('recovery code', (tester, look) async {
    final startup = await _locked(tester);
    await showScene(tester, look, LockScreen(startup: startup), height: 800);
    await tester.tap(find.byKey(Keys.forgot));
    await tester.pump(const Duration(seconds: 2));
  }),

  // What is told as the book opens.
  for (final (name, rows) in <(String, List<QuarantinedRow>)>[
    (
      'quarantine notice',
      [
        QuarantinedRow('entry', 'a', QuarantineReason.unreadable),
        QuarantinedRow('entry', 'b', QuarantineReason.unreadable),
      ],
    ),
    (
      'quarantine notice, newer',
      [QuarantinedRow('entry', 'a', QuarantineReason.newer, version: 9)],
    ),
  ])
    Place(name, (tester, look) async {
      await showScene(
        tester,
        look,
        _opener(
          (context) => showQuarantineNotice(context, rows, onExport: () {}),
        ),
        height: 800,
      );
      await tester.tap(find.byKey(_openKey));
      await tester.pumpAndSettle();
    }),
  Place('old key backups', (tester, look) async {
    final old = OldKeyBackups(
      epoch: 2,
      localBackups: () async => [],
      driveFiles: () async => [
        DriveFile('a', 'a.etbk', DateTime(2026, 11, 20, 12), 1, epoch: '1'),
        DriveFile('b', 'b.etbk', DateTime(2026, 11, 13, 12), 1),
      ],
      trashOnDrive: (_) async {},
    );
    await showScene(
      tester,
      look,
      _opener((context) => offerToRemoveOldKeyBackups(context, old)),
      height: 800,
    );
    await tester.tap(find.byKey(_openKey));
    await tester.pumpAndSettle();
  }),
  Place('upgrade held, go on without a backup', (tester, look) async {
    await showScene(
      tester,
      look,
      UpgradeHeldPage(
        failure: UpgradeBackupFailed(
          UpgradeBackupProblem.noSpace,
          StateError('x'),
        ),
        onRetry: () {},
        onExport: () {},
        onWithoutBackup: () {},
      ),
      height: 800,
    );
    final skip = find.byKey(Keys.upgradeHeld('skip'));
    await tester.ensureVisible(skip);
    await tester.tap(skip);
    await tester.pumpAndSettle();
  }),

  // 通知與提醒: the phone allowing everything, short of the battery
  // setting, short of notifications; with a calendar to link.
  for (final (name, status) in <(String, ReminderStatus)>[
    (
      'reminders, all allowed',
      (notifications: true, exact: true, battery: true),
    ),
    ('reminders, battery', (notifications: true, exact: true, battery: false)),
    (
      'reminders, no notifications',
      (notifications: false, exact: true, battery: true),
    ),
  ])
    Place(name, (tester, look) async {
      final preferences = Preferences()
        ..update(
          dueAlerts: true,
          budgetAlerts: true,
          dailyNudge: true,
          exactReminders: true,
        );
      final dir = Directory.systemTemp.createTempSync('places-');
      addTearDown(() => dir.deleteSync(recursive: true));
      await showScene(
        tester,
        look,
        Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ListenableBuilder(
                listenable: preferences,
                builder: (context, _) => RemindersSection(
                  ledger: reviewLedger(),
                  notifier: Notifier(ReviewPhone(status), preferences),
                  calendar: CalendarSync(FakeCalendars(), dir),
                  onBudgets: () {},
                ),
              ),
            ],
          ),
        ),
      );
    }),

  // 安全 of a ledger with a password and a fingerprint, and its panels.
  Place('security', (tester, look) => _security(tester, look)),
  Place(
    'security, auto-lock',
    (tester, look) => _security(tester, look, panel: Keys.autoLock),
  ),
  Place(
    'security, new password',
    (tester, look) => _security(tester, look, panel: Keys.password),
  ),
];

/// A ledger with a password, opened and locked again, to be unlocked.
Future<Startup> _locked(WidgetTester tester) async {
  final startup = Startup(_vault());
  await tester.runAsync(() => startup.setUp(_password));
  startup.lock();
  return startup;
}

/// A ledger folder of its own, removed after the test.
LedgerVault _vault() {
  final dir = Directory.systemTemp.createTempSync('places-');
  addTearDown(() => dir.deleteSync(recursive: true));
  return LedgerVault(
    dir,
    codec: KeyringCodec(kdf: PasswordKdf.insecureForTests),
  );
}

Future<void> _security(WidgetTester tester, Look look, {Key? panel}) async {
  await showScene(
    tester,
    look,
    Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SecuritySection(
            backupManager: ReviewKeys(),
            preferences: Preferences(),
            privacy: null,
          ),
        ],
      ),
    ),
    height: 1800,
  );
  if (panel != null) {
    await tester.tap(find.byKey(panel));
    await tester.pumpAndSettle();
  }
}

/// [home] drawn as the app itself, with no theme of the page's own, as
/// before the ledger is open.
Future<void> _standalone(WidgetTester tester, Look look, Widget home) async {
  tester.view.physicalSize = Size(look.width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(
        size: Size(look.width, 800),
        textScaler: look.scaler ?? TextScaler.linear(look.text),
        disableAnimations: look.still,
      ),
      child: home,
    ),
  );
  await tester.pumpAndSettle();
}

const _openKey = ValueKey('places:open');

/// A page with a button that runs [open], for a panel in the middle of
/// the screen.
Widget _opener(Future<void> Function(BuildContext context) open) => Scaffold(
  body: Builder(
    builder: (context) => Center(
      child: TextButton(
        key: _openKey,
        onPressed: () => open(context),
        child: const Text('open'),
      ),
    ),
  ),
);
