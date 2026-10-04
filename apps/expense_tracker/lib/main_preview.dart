import 'package:flutter/widgets.dart';

import 'src/app.dart';
import 'src/preview.dart';

/// The web preview: example data in memory, never the encrypted ledger.
/// Built with `flutter build web -t lib/main_preview.dart`.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(ExpenseApp(session: await previewSession()));
}
