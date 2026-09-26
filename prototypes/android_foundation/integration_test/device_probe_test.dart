import 'package:android_foundation/probe_runner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android secure storage, encrypted restart and two restore paths',
    (tester) async {
      expect(await ProbeRunner().run(), hasLength(3));
      // Reuses the persisted key and operation receipts, with fresh Dart objects.
      expect(await ProbeRunner().run(), hasLength(3));
    },
  );
}
