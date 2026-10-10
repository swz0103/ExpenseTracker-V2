import 'package:flutter/widgets.dart';

import 'src/app.dart';
import 'src/demo/seed.dart';
import 'src/look/phone_frame.dart';
import 'src/pages/shell.dart';
import 'src/preview.dart';

/// The web preview: the interface over made-up data in memory, never the
/// encrypted ledger, shown at phone size on a wide screen.
/// Built with `flutter build web -t lib/main_preview.dart`.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final session = await previewSession();
  runApp(
    ExpenseApp(
      session: session,
      home: AppShell(ledger: demoLedger()),
      frame: (context, child) => PhoneFrame(child: child ?? const SizedBox()),
    ),
  );
}
