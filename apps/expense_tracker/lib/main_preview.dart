import 'package:flutter/widgets.dart';

import 'src/app.dart';
import 'src/charts/chart_gallery.dart';
import 'src/charts/demo_charts.dart';
import 'src/preview.dart';

/// The web preview: example data in memory, never the encrypted ledger.
/// Built with `flutter build web -t lib/main_preview.dart`.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final session = await previewSession();
  final today = session.today;
  final charts = demoCharts(today.year, today.month, today.day);
  runApp(
    ExpenseApp(
      session: session,
      home: ChartGallery(data: charts),
    ),
  );
}
