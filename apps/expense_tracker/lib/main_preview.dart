import 'package:flutter/widgets.dart';

import 'src/app/app.dart';
import 'src/app/demo/launch.dart';
import 'src/core/look/phone_frame.dart';
import 'src/core/preferences.dart';

/// The web preview: the interface over made-up data in memory, never the
/// encrypted ledger, shown at phone size on a wide screen, from the
/// phone's home screen on (its icon and widgets, the opening, the lock).
/// Built with `flutter build web -t lib/main_preview.dart`.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Colours and taps are chosen in memory, for this visit only.
  final preferences = Preferences();
  runApp(
    ExpenseApp(
      preferences: preferences,
      home: PreviewLaunch(preferences: preferences),
      frame: (context, child) => PhoneFrame(child: child ?? const SizedBox()),
    ),
  );
}
