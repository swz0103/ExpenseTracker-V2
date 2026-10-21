import 'dart:io';

import 'package:flutter/widgets.dart';

import 'src/book/leftovers.dart';
import 'src/bootstrap.dart';
import 'src/perf.dart';
import 'src/platform.dart';
import 'src/preferences.dart';
import 'src/screen_privacy.dart';

/// The production entry: the encrypted ledger only. The web preview starts
/// from `main_preview.dart`.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Perf.instance.watchFrames();
  final directory = await applicationDirectory();
  // Faults are kept on the phone, so 設定 can export them after a crash.
  Perf.instance.keepIn(File('${directory.path}/diagnostics.log'));
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    Perf.instance.problem('畫面錯誤', details.exception);
  };
  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    Perf.instance.problem('未預期的錯誤', error);
    return true;
  };
  try {
    // Plain copies a run stopped part way may have left: exports waiting to
    // be handed over, camera photos, a chosen backup.
    await clearLeftovers(
      directory,
      cache: Platform.isAndroid ? await androidCacheDirectory() : null,
    );
  } on Object catch (error) {
    Perf.instance.problem('清除暫存檔', error);
  }
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
  if (Platform.isAndroid) {
    try {
      await listenForQuickActions();
    } on Object catch (error) {
      Perf.instance.problem('捷徑', error);
    }
  }
  runApp(
    VaultRoot(
      startup: productionStartup(directory, device: device),
      privacy: privacy,
      preferences: preferences,
    ),
  );
}
