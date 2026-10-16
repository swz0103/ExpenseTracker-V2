import 'dart:io';

import 'package:flutter/widgets.dart';

import 'src/bootstrap.dart';
import 'src/platform.dart';

/// The production entry: the encrypted ledger only. The web preview starts
/// from `main_preview.dart`.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final directory = await applicationDirectory();
  final device = Platform.isAndroid
      ? await androidDeviceUnlock(directory)
      : null;
  runApp(VaultRoot(startup: productionStartup(directory, device: device)));
}
