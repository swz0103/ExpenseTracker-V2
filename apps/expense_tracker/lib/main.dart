import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/widgets.dart';

import 'src/features/backup/model/leftovers.dart';
import 'src/app/bootstrap.dart';
import 'src/core/perf.dart';
import 'src/app/platform.dart';
import 'src/core/preferences.dart';
import 'src/core/screen_privacy.dart';

/// The production entry: the encrypted ledger only. The web preview starts
/// from `main_preview.dart`.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Perf.instance.watchFrames();
  final directory = await applicationDirectory();
  // Faults are kept on the phone, so 設定 can export them after a crash.
  Perf.instance.keepIn(File('${directory.path}/diagnostics.log'));
  FlutterError.onError = (details) {
    // A release build only keeps the cleaned record (perf.dart): the full
    // report would go to the phone's system log, possibly with the
    // person's own words in it.
    if (!kReleaseMode) FlutterError.presentError(details);
    Perf.instance.problem('畫面錯誤', details.exception);
  };
  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    Perf.instance.problem('未預期的錯誤', error);
    return true;
  };
  final device = Platform.isAndroid
      ? await androidDeviceUnlock(directory)
      : null;
  final privacy = Platform.isAndroid
      ? ScreenPrivacy(directory, androidSecureScreen)
      : null;
  try {
    await privacy?.apply();
  } on Object catch (error) {
    Perf.instance.problem('螢幕隱私', error);
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
    Perf.instance.problem('捷徑', error);
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
      Perf.instance.problem('清除暫存檔', error);
    }
  }
  try {
    await clearLeftovers(directory, cache: cache);
  } on Object catch (error) {
    Perf.instance.problem('清除暫存檔', error);
  }
}
