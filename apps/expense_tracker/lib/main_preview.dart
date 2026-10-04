import 'package:flutter/widgets.dart';

import 'src/app.dart';
import 'src/charts/chart_gallery.dart';
import 'src/charts/demo_charts.dart';
import 'src/home/home_data.dart';
import 'src/home/home_demo.dart';
import 'src/home/home_page.dart';
import 'src/preview.dart';
import 'src/shell.dart';

/// The web preview: example data in memory, never the encrypted ledger.
/// Built with `flutter build web -t lib/main_preview.dart`.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final session = await previewSession();
  final today = session.today;
  final (year, month, day) = (today.year, today.month, today.day);
  final charts = demoCharts(year, month, day);
  final home = demoHome(charts, year, month, day);
  runApp(
    ExpenseApp(
      session: session,
      home: AppShell(
        title: dayLabel(home.today),
        home: HomePage(data: home),
        reports: ChartGallery(data: charts),
      ),
    ),
  );
}
