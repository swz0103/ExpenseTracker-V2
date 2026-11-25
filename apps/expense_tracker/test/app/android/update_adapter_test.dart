/// Review 31 finding 1: stopping an update's download closes its
/// connection, so a transfer waiting on a stalled network ends at once
/// (not at its stall's minute) and leaves no part file behind.
library;

import 'dart:async';
import 'dart:io';

import 'package:expense_tracker/src/app/android/update_adapter.dart';
import 'package:expense_tracker/src/features/settings/model/app_update.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer server;
  late Directory directory;

  /// Released at the end of each test: the server's answer, stalled.
  late Completer<void> stalled;

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('update-adapter-');
    stalled = Completer<void>();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      // A piece of the APK, then nothing: the network stalls.
      request.response
        ..bufferOutput = false
        ..contentLength = 100
        ..add(List.filled(10, 1));
      await request.response.flush();
      await stalled.future;
      try {
        await request.response.close();
      } on Object {
        // The client went away.
      }
    });
  });
  tearDown(() async {
    if (!stalled.isCompleted) stalled.complete();
    await server.close(force: true);
    directory.deleteSync(recursive: true);
  });

  test('a download stopped while the network stalls ends at once, its '
      'part deleted', () async {
    final into = File('${directory.path}/ExpenseTracker-190.apk');
    final cancel = DownloadCancel();
    final arrived = Completer<void>();
    final download = const AndroidUpdatePort().download(
      Uri.parse('http://${server.address.host}:${server.port}/a.apk'),
      into,
      (received) {
        if (!arrived.isCompleted) arrived.complete();
      },
      cancel: cancel,
    );
    // Caught here, so a failure before the cancel is not unhandled.
    final ended = download.then<Object?>((_) => null, onError: (Object e) => e);
    await arrived.future;
    expect(File('${into.path}.part').existsSync(), isTrue);
    cancel.ask();
    // Well inside the minute a stall is given.
    final error = await ended.timeout(const Duration(seconds: 10));
    expect(error, isNotNull, reason: 'a stopped download is not saved');
    expect(File('${into.path}.part').existsSync(), isFalse);
    expect(into.existsSync(), isFalse);
  });

  test('a download asked to stop before it starts does not start', () async {
    final into = File('${directory.path}/ExpenseTracker-190.apk');
    final cancel = DownloadCancel()..ask();
    await expectLater(
      const AndroidUpdatePort().download(
        Uri.parse('http://${server.address.host}:${server.port}/a.apk'),
        into,
        (_) => fail('nothing arrives'),
        cancel: cancel,
      ),
      throwsA(isA<HttpException>()),
    );
    expect(File('${into.path}.part').existsSync(), isFalse);
  });
}
