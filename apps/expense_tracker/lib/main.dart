import 'dart:io';

import 'package:flutter/widgets.dart';

import 'src/bootstrap.dart';
import 'src/perf.dart';
import 'src/platform.dart';
import 'src/screen_privacy.dart';

/// The production entry: the encrypted ledger only. The web preview starts
/// from `main_preview.dart`.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Perf.instance.watchFrames();
  final directory = await applicationDirectory();
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
  runApp(
    VaultRoot(
      startup: productionStartup(directory, device: device),
      privacy: privacy,
    ),
  );
}
