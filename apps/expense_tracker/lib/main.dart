import 'package:flutter/widgets.dart';

import 'src/bootstrap.dart';

/// The production entry: the encrypted ledger only. The web preview starts
/// from `main_preview.dart`.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(VaultRoot(startup: productionStartup(applicationDirectory())));
}
