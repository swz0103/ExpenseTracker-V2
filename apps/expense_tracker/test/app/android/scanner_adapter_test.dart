import 'package:expense_tracker/src/app/android/scanner_adapter.dart';
import 'package:expense_tracker/src/core/diagnostics/error_log.dart';
import 'package:expense_tracker/src/core/platform/scan.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// F66: what the phone answers a scan with becomes an outcome the form
/// words, and a failure is kept in the error log with the phone's reason
/// instead of being thrown away.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('expense_tracker/platform');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// The phone, answering each method with [answers]' value or throwing
  /// its exception; the methods asked are kept in the list returned.
  List<String> phone(Map<String, Object?> answers) {
    final asked = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      asked.add(call.method);
      if (!answers.containsKey(call.method)) {
        throw MissingPluginException();
      }
      final answer = answers[call.method];
      if (answer is Exception) throw answer;
      return answer;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    return asked;
  }

  /// What the error log gained while [body] ran, newest first.
  Future<List<String>> logged(Future<void> Function() body) async {
    final before = ErrorLog.instance.count;
    await body();
    final all = ErrorLog.instance.entries;
    return [for (final (_, words) in all.take(all.length - before)) words];
  }

  test('a scanner that is on the phone opens at once and gives the '
      'code', () async {
    final asked = phone({'scanReady': true, 'scanQr': 'AB12345678'});
    var prepared = 0;
    final outcome = await androidScanQr(preparing: () => prepared++);
    expect((outcome as ScanRead).text, 'AB12345678');
    expect(asked, ['scanReady', 'scanQr']);
    expect(prepared, 0);
  });

  test('a scanner to be fetched says so before the wait', () async {
    phone({'scanReady': false, 'scanQr': null});
    var prepared = 0;
    final outcome = await androidScanQr(preparing: () => prepared++);
    expect(prepared, 1);
    // Closed without a code.
    expect(outcome, isA<ScanClosed>());
  });

  test('a download that fails is unavailable, and kept with its '
      'reason', () async {
    phone({
      'scanReady': false,
      'scanQr': PlatformException(
        code: 'install',
        message: 'Download failed for /data/user/0/x',
        details: 'NETWORK_ERROR',
      ),
    });
    late ScanOutcome outcome;
    final kept = await logged(() async => outcome = await androidScanQr());
    expect((outcome as ScanFailed).failure, ScanFailure.unavailable);
    expect(kept, ['掃發票：ScanFault: install NETWORK_ERROR']);
  });

  test('Play services that cannot even be asked is unavailable too', () async {
    phone({
      'scanReady': PlatformException(
        code: 'install',
        details: 'API_UNAVAILABLE',
      ),
    });
    late ScanOutcome outcome;
    final kept = await logged(() async => outcome = await androidScanQr());
    expect((outcome as ScanFailed).failure, ScanFailure.unavailable);
    expect(kept, ['掃發票：ScanFault: install API_UNAVAILABLE']);
  });

  test('a scanner that opens and fails is kept, without what is not a '
      'reason name', () async {
    phone({
      'scanReady': true,
      'scanQr': PlatformException(code: 'scan', details: 'camera 3 of 王小明'),
    });
    late ScanOutcome outcome;
    final kept = await logged(() async => outcome = await androidScanQr());
    expect((outcome as ScanFailed).failure, ScanFailure.failed);
    expect(kept, ['掃發票：ScanFault: scan']);
  });

  test('a scan already open is said, and is no fault to keep', () async {
    phone({'scanReady': true, 'scanQr': PlatformException(code: 'busy')});
    late ScanOutcome outcome;
    final kept = await logged(() async => outcome = await androidScanQr());
    expect((outcome as ScanFailed).failure, ScanFailure.busy);
    expect(kept, isEmpty);
  });

  test('a phone with no scanner part at all fails, and is kept', () async {
    phone({});
    late ScanOutcome outcome;
    final kept = await logged(() async => outcome = await androidScanQr());
    expect((outcome as ScanFailed).failure, ScanFailure.failed);
    expect(kept.single, startsWith('掃發票：MissingPluginException'));
  });
}
