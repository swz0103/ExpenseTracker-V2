import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';

import 'src/features/backup/model/file_cleanup.dart';
import 'src/app/bootstrap.dart';
import 'src/app/production_startup.dart';
import 'src/app/first_screen.dart';
import 'src/core/diagnostics/performance_monitor.dart';
import 'src/app/platform.dart';
import 'src/core/platform/preferences.dart';
import 'src/core/platform/screen_privacy.dart';
import 'src/core/platform/store_threading.dart';
import 'src/core/diagnostics/error_log.dart';
import 'src/core/diagnostics/error_steps.dart';
import 'src/core/diagnostics/unhandled_errors.dart';
import 'src/core/messages/diagnostics_messages.dart';
import 'src/core/design_system/feedback.dart';
import 'src/app/android/clipboard_adapter.dart';
import 'src/app/android/haptics_adapter.dart';
import 'src/core/design_system/haptics.dart';
import 'src/core/design_system/recovery_code.dart';
import 'src/core/platform/sensitive_clipboard.dart';
import 'src/core/platform/app_files.dart';

/// The production entry: the encrypted ledger only. The web preview starts
/// from `main_preview.dart`. Every wait before the first screen is
/// guarded (first_screen.dart): a step that fails shows what happened and
/// a way out, never a blank app.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  PerformanceMonitor.instance.watchFrames();
  // A fault nothing caught is kept with its stack; a release build tells
  // the person once, any other shows it to the developer. Before any
  // step, so a fault of one is kept too.
  UnhandledErrors(
    log: ErrorLog.instance,
    tell: () => showNoteAnywhere(DiagnosticsMessages.unforeseenNote),
  ).install();
  // The phone's own taps, which it tunes for the hand.
  if (Platform.isAndroid) Haptics.perform = androidHaptic;
  // A recovery code copied is a secret: flagged sensitive for the phone,
  // and taken off the clipboard after a minute.
  copyRecoveryCode = SensitiveClipboard.copy;
  if (Platform.isAndroid) {
    SensitiveClipboard.platformCopy = androidCopySensitive;
  }
  await _start();
}

/// Puts the first screen up: the app, or what kept it from starting with
/// a way to try again.
Future<void> _start() async =>
    runApp(await firstScreen(_steps, retry: () => unawaited(_start())));

final _steps = StartSteps(
  folder: applicationDirectory,
  // Faults are kept on the phone, so 設定 can export them after a crash.
  keepLog: (folder) =>
      ErrorLog.instance.keepIn(File('${folder.path}/diagnostics.log')),
  device: Platform.isAndroid ? androidDeviceUnlock : null,
  privacy: Platform.isAndroid ? _privacy : null,
  // What could name the person is sealed by the Keystore key that needs
  // no fingerprint, so the settings hold from the lock screen on.
  preferences: (folder) => Preferences.open(
    File('${folder.path}/${AppFiles.preferences}'),
    keystore: Platform.isAndroid ? const KeystoreQuickKey() : null,
  ),
  compose: (folder, device, privacy, preferences) => VaultRoot(
    startup: productionStartup(
      folder,
      device: device,
      uptime: Platform.isAndroid ? androidUptime : null,
    ),
    privacy: privacy,
    preferences: preferences,
    // Shortcuts, the widget and notifications go through the lock gate.
    quick: Platform.isAndroid ? quickAction : null,
    leave: Platform.isAndroid ? androidMoveToBack : null,
  ),
  // Beside the first frame, so the opening is not kept waiting: the phone
  // keeps the shortcut the app was opened with until it is taken, and
  // nothing writes where the leftovers are cleared before the ledger is
  // open.
  started: (folder) {
    noteStoreThreading();
    if (Platform.isAndroid) unawaited(_listenForQuickActions());
    unawaited(_clearLeftovers(folder));
  },
);

/// Keeps the screens out of screenshots as the person chose; a phone
/// that cannot be told keeps them out as it started.
Future<ScreenPrivacy> _privacy(Directory folder) async {
  final privacy = ScreenPrivacy(folder, androidSecureScreen);
  try {
    await privacy.apply();
  } on Object catch (error) {
    ErrorLog.instance.record(ErrorSteps.screenPrivacy, error);
  }
  return privacy;
}

Future<void> _listenForQuickActions() async {
  try {
    await listenForQuickActions();
  } on Object catch (error) {
    ErrorLog.instance.record('捷徑', error);
  }
}

/// Plain copies a run stopped part way may have left: exports waiting to
/// be handed over, camera photos, a chosen backup. The cache folder is
/// asked for on its own, so exports are still cleared without it.
Future<void> _clearLeftovers(Directory directory) async {
  Directory? cache;
  if (Platform.isAndroid) {
    try {
      cache = await androidCacheDirectory();
    } on Object catch (error) {
      ErrorLog.instance.record(ErrorSteps.cleanup, error);
    }
  }
  try {
    await clearLeftovers(directory, cache: cache);
  } on Object catch (error) {
    ErrorLog.instance.record(ErrorSteps.cleanup, error);
  }
}
