import 'package:expense_tracker/src/app/android/lock_adapter.dart';
import 'package:expense_tracker/src/app/android/platform_channel.dart';
import 'package:flutter_test/flutter_test.dart';

/// The lock gate's calls to the phone (`LockHandler.kt`), answered here
/// as the phone answers them.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<String> calls;
  Object? answer;

  setUp(() {
    calls = [];
    answer = null;
    messenger.setMockMethodCallHandler(platformChannel, (call) async {
      calls.add(call.method);
      return answer;
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(platformChannel, null));

  test('the uptime is read as the phone names its start and how long it '
      'has run', () async {
    answer = {'boot': 'boot-12', 'upMs': 90000};
    final uptime = await androidUptime();
    expect(calls, ['uptime']);
    // 90,000 ms = 90 s
    expect(uptime, (boot: 'boot-12', up: const Duration(seconds: 90)));
  });

  test('a phone that does not name its start gives no uptime', () async {
    answer = {'boot': null, 'upMs': 90000};
    expect(await androidUptime(), isNull);
    answer = null;
    expect(await androidUptime(), isNull);
    expect(uptimeOf(const {'boot': 'boot-1'}), isNull);
  });

  test(
    'back on the first screen asks the phone to put the app behind',
    () async {
      await androidMoveToBack();
      expect(calls, ['moveToBack']);
    },
  );
}
