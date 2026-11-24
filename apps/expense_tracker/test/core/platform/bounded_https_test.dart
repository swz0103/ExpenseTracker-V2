import 'dart:convert';
import 'dart:io';

import 'package:expense_tracker/src/core/platform/bounded_https.dart';
import 'package:flutter_test/flutter_test.dart';

/// Review 22 finding 5: the update feed and Drive follow a redirect only
/// to https and read a body only up to a limit.
void main() {
  late HttpServer server;
  late HttpClient client;
  late Directory directory;
  final asked = <String>[];

  /// What the server answers to a path.
  late void Function(HttpRequest request) answer;

  setUp(() async {
    asked.clear();
    directory = Directory.systemTemp.createTempSync('bounded-https-');
    client = HttpClient();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      asked.add('${request.method} ${request.uri.path}');
      await request.drain<void>();
      answer(request);
      await request.response.close();
    });
  });
  tearDown(() async {
    client.close(force: true);
    await server.close(force: true);
    directory.deleteSync(recursive: true);
  });

  Uri url(String path) =>
      Uri.parse('http://${server.address.host}:${server.port}$path');

  void redirectTo(HttpRequest request, String location, [int status = 302]) {
    request.response
      ..statusCode = status
      ..headers.set(HttpHeaders.locationHeader, location);
  }

  Future<HttpClientResponse> get(String path, {bool Function(Uri)? allowed}) =>
      BoundedHttps.open(
        client,
        'GET',
        url(path),
        allowed: allowed ?? (_) => true,
      );

  test('an answer within the limit is read', () async {
    answer = (request) => request.response.write('{"version":"1.0.0"}');
    final response = await get('/update.json');
    // 19 bytes, under a 64-byte limit.
    expect(
      await BoundedHttps.text(response, 64, uri: url('/update.json')),
      '{"version":"1.0.0"}',
    );
  });

  test('an answer past the limit is refused, with or without its length '
      'said first', () async {
    answer = (request) => request.response.write('x' * 100);
    await expectLater(
      BoundedHttps.text(await get('/big'), 64, uri: url('/big')),
      throwsA(isA<AnswerTooLarge>().having((e) => e.limit, 'limit', 64)),
    );
    answer = (request) {
      // Sent in parts, its length unsaid.
      request.response.bufferOutput = false;
      request.response.headers.chunkedTransferEncoding = true;
      for (var i = 0; i < 10; i++) {
        request.response.add(utf8.encode('x' * 10));
      }
    };
    await expectLater(
      BoundedHttps.text(await get('/chunked'), 64, uri: url('/chunked')),
      throwsA(isA<AnswerTooLarge>()),
    );
  });

  test(
    'a body saved to a file stops at the limit, saying what arrived',
    () async {
      answer = (request) => request.response.add(List.filled(100, 7));
      final into = File('${directory.path}/app.apk.part');
      final seen = <int>[];
      await BoundedHttps.save(
        await get('/ok.apk'),
        into,
        100,
        uri: url('/ok.apk'),
        progress: seen.add,
      );
      expect(into.lengthSync(), 100);
      expect(seen.last, 100);
      await expectLater(
        BoundedHttps.save(
          await get('/big.apk'),
          into,
          99,
          uri: url('/big.apk'),
        ),
        throwsA(isA<AnswerTooLarge>()),
      );
    },
  );

  test('a redirect to plain http is refused, and not asked', () async {
    answer = (request) => request.uri.path == '/start'
        ? redirectTo(request, url('/plain').toString())
        : request.response.write('plain');
    await expectLater(get('/start'), throwsA(isA<RedirectRefused>()));
    expect(asked, ['GET /start']);
  });

  test('a redirect to a host not allowed is refused', () async {
    answer = (request) =>
        redirectTo(request, 'https://elsewhere.example/update.json');
    await expectLater(
      get(
        '/start',
        allowed: (to) => to.host.endsWith('.githubusercontent.com'),
      ),
      throwsA(
        isA<RedirectRefused>().having(
          (e) => e.uri?.host,
          'to',
          'elsewhere.example',
        ),
      ),
    );
    expect(asked, ['GET /start']);
  });

  test('a redirect answering another method is handed back, not followed '
      '(Drive\'s 308 to a resumable upload)', () async {
    answer = (request) => redirectTo(request, url('/next').toString(), 308);
    final response = await BoundedHttps.open(
      client,
      'PUT',
      url('/upload'),
      allowed: (_) => true,
      send: (request) async => request.contentLength = 0,
    );
    expect(response.statusCode, 308);
    await response.drain<void>();
    expect(asked, ['PUT /upload']);
  });
}
