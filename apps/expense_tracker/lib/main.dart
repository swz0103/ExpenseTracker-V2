import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/widgets.dart';

import 'src/features/backup/model/file_cleanup.dart';
import 'src/app/bootstrap.dart';
import 'src/core/diagnostics/performance_monitor.dart';
import 'src/app/platform.dart';
import 'src/core/platform/preferences.dart';
import 'src/core/platform/screen_privacy.dart';
import 'src/core/diagnostics/error_log.dart';
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
  FlutterError.onError = (details) {
    // A release build only keeps the cleaned record (perf.dart): the full
    // report would go to the phone's system log, possibly with the
    // person's own words in it.
    if (!kReleaseMode) FlutterError.presentError(details);
    ErrorLog.instance.record('畫面錯誤', details.exception);
  };
  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    ErrorLog.instance.record('未預期的錯誤', error);
    return true;
  };
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
    ErrorLog.instance.record('螢幕隱私', error);
  }
  final preferences = Preferences(
    file: File('${directory.path}/preferences.json'),
  );
  runApp(
    VaultRoot(
      startup: productionStartup(directory, device: device),
      privacy: privacy,
      preferences: preferences,
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
      ErrorLog.instance.record('清除暫存檔', error);
    }
  }
  try {
    await clearLeftovers(directory, cache: cache);
  } on Object catch (error) {
    ErrorLog.instance.record('清除暫存檔', error);
  }
}
