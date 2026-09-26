import 'package:android_foundation/probe_runner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android secure slots, encrypted reopen and paired Ledger restores',
    (tester) async {
      expect(await ProbeRunner().run(), hasLength(3));
      // Reuses persisted source key, target pairs and receipts with fresh objects.
      expect(await ProbeRunner().run(), hasLength(3));
    },
  );
}
