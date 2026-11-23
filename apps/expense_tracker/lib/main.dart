import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';

import 'src/features/backup/model/file_cleanup.dart';
import 'src/app/bootstrap.dart';
import 'src/core/diagnostics/performance_monitor.dart';
import 'src/app/platform.dart';
import 'src/core/platform/preferences.dart';
import 'src/core/platform/screen_privacy.dart';
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

/// The production entry: the encrypted ledger only. The web preview starts
/// from `main_preview.dart`.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  PerformanceMonitor.instance.watchFrames();
  final directory = await applicationDirectory();
  // Faults are kept on the phone, so 設定 can export them after a crash.
  ErrorLog.instance.keepIn(File('${directory.path}/diagnostics.log'));
  // A fault nothing catches is kept with its stack; a release build tells
  // the person once, any other shows it to the developer.
  UnhandledErrors(
    log: ErrorLog.instance,
    tell: () => showNoteAnywhere(DiagnosticsMessages.unforeseenNote),
  ).install();
  final device = Platform.isAndroid
      ? await androidDeviceUnlock(directory)
      : null;
  final privacy = Platform.isAndroid
      ? ScreenPrivacy(directory, androidSecureScreen)
      : null;
  // The phone's own taps, which it tunes for the hand.
  if (Platform.isAndroid) Haptics.perform = androidHaptic;
  // A recovery code copied is a secret: flagged sensitive for the phone,
  // and taken off the clipboard after a minute.
  copyRecoveryCode = SensitiveClipboard.copy;
  if (Platform.isAndroid) {
    SensitiveClipboard.platformCopy = androidCopySensitive;
  }
  try {
    await privacy?.apply();
  } on Object catch (error) {
    ErrorLog.instance.record(ErrorSteps.screenPrivacy, error);
  }
  final preferences = Preferences(
    file: File('${directory.path}/preferences.json'),
  );
  runApp(
    VaultRoot(
      startup: productionStartup(
        directory,
        device: device,
        uptime: Platform.isAndroid ? androidUptime : null,
      ),
      privacy: privacy,
      preferences: preferences,
      // Shortcuts, the widget and notifications go through the lock gate.
      quick: Platform.isAndroid ? quickAction : null,
      leave: Platform.isAndroid ? androidMoveToBack : null,
    ),
  );
  // After the first frame is asked for, so the opening is not kept
  // waiting: the phone keeps the shortcut the app was opened with until
  // it is taken, and nothing writes where the leftovers are cleared
  // before the ledger is open.
  if (Platform.isAndroid) unawaited(_listenForQuickActions());
  unawaited(_clearLeftovers(directory));
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
