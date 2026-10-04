import 'dart:async';
import 'dart:io';

import 'package:drive_backup/drive_backup.dart';
import 'package:test/test.dart';

/// The real HTTP transport against a server on this machine (health check
/// G5-09, G8-16): no redirects, capped responses, every failure the same
/// exception.
void main() {
  late HttpServer server;
  late Uri base;
  late Completer<void> release;
  const transport = IoDriveTransport();
  const timeout = Duration(seconds: 2);

  setUp(() async {
    release = Completer<void>();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = Uri.parse('http://${server.address.host}:${server.port}');
    server.listen((request) async {
      try {
        final body = <int>[];
        await for (final part in request) {
          body.addAll(part);
        }
        final response = request.response;
        switch (request.uri.path) {
          case '/echo':
            response.headers.set('X-Echo', request.headers.value('x-test')!);
            response.add(body);
          case '/moved':
            response.statusCode = HttpStatus.found;
            response.headers.set('Location', '$base/echo');
          case '/large':
            response.add(List.filled(4096, 1));
          case '/silent':
            // Answers only when the test ends.
            await release.future;
        }
        await response.close();
      } on Object {
        // The client gave up first.
      }
    });
  });

  tearDown(() async {
    release.complete();
    await server.close(force: true);
  });

  DriveRequest request(String path, {List<int> body = const []}) =>
      DriveRequest(
        method: 'PUT',
        uri: Uri.parse('$base$path'),
        headers: {'X-Test': 'yes'},
        body: body,
        maxResponseBytes: 1024,
      );

  test('a request and its response pass through intact', () async {
    final response = await transport.send(
      request('/echo', body: [1, 2, 3]),
      timeout: timeout,
    );
    expect(response.statusCode, 200);
    expect(response.headers['x-echo'], 'yes');
    expect(response.body, [1, 2, 3]);
  });

  test('a redirect is returned, not followed', () async {
    final response = await transport.send(request('/moved'), timeout: timeout);
    expect(response.statusCode, HttpStatus.found);
    expect(response.headers['location'], '$base/echo');
  });

  test('oversized, silent and unreachable servers all fail alike', () async {
    final failure = throwsA(isA<DriveTransportException>());
    await expectLater(
      transport.send(request('/large'), timeout: timeout),
      failure,
    );
    await expectLater(
      transport.send(
        request('/silent'),
        timeout: const Duration(milliseconds: 200),
      ),
      failure,
    );
    final closed = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = closed.port;
    await closed.close();
    await expectLater(
      transport.send(
        DriveRequest(method: 'GET', uri: Uri.parse('http://127.0.0.1:$port/')),
        timeout: timeout,
      ),
      failure,
    );
  });
}
