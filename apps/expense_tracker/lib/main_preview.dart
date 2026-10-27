import 'package:flutter/widgets.dart';

import 'src/app/app.dart';
import 'src/app/demo/seed.dart';
import 'src/core/look/phone_frame.dart';
import 'src/app/shell.dart';
import 'src/core/preferences.dart';
import 'src/features/settings/model/services.dart';

/// The web preview: the interface over made-up data in memory, never the
/// encrypted ledger, shown at phone size on a wide screen.
/// Built with `flutter build web -t lib/main_preview.dart`.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Colours and taps are chosen in memory, for this visit only.
  final preferences = Preferences();
  runApp(
    ExpenseApp(
      preferences: preferences,
      home: AppShell(
        ledger: demoLedger(),
        services: Services(preferences: preferences, sample: demoLedger),
      ),
      frame: (context, child) => PhoneFrame(child: child ?? const SizedBox()),
    ),
  );
}
