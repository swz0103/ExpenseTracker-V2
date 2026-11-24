import 'dart:convert';
import 'dart:io';

import 'package:expense_tracker/src/core/platform/bounded_https.dart';
import 'package:expense_tracker/src/features/backup/model/drive_backup.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_drive.dart';

/// A request as the server took it.
typedef _Asked = ({
  String method,
  String path,
  String body,
  int size,
  Map<String, String> headers,
});

/// Answers every request with [reply], after keeping what was sent.
final class _Server {
  _Server._(this._server);

  final HttpServer _server;
  final asked = <_Asked>[];
  var reply = (status: 200, body: '{}', headers: const <String, String>{});

  static Future<_Server> start() async {
    final server = _Server._(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    server._server.listen((request) async {
      final bytes = await request.fold<List<int>>(
        [],
        (all, part) => all..addAll(part),
      );
      final body = utf8.decode(bytes, allowMalformed: true);
      final headers = <String, String>{};
      request.headers.forEach((name, values) => headers[name] = values.join());
      server.asked.add((
        method: request.method,
        path: request.uri.path,
        body: body,
        size: bytes.length,
        headers: headers,
      ));
      final reply = server.reply;
      request.response.statusCode = reply.status;
      reply.headers.forEach(request.response.headers.set);
      request.response.write(reply.body);
      await request.response.close();
    });
    return server;
  }

  Uri url(String path) =>
      Uri.parse('http://${_server.address.host}:${_server.port}$path');

  Future<void> close() => _server.close(force: true);
}

/// Fails every request as a phone with no connection does.
final class _Offline implements DriveHttp {
  @override
  Future<DriveResponse> send(
    String method,
    Uri url, {
    Map<String, String> headers = const {},
    String? text,
    File? file,
    File? saveTo,
  }) async => throw const SocketException('Network is unreachable');
}

void main() {
  late Directory directory;
  late _Server server;
  // 4 GiB, as the app gives it (LedgerBackup.maxBackupBytes).
  const http = IoDriveHttp(saveLimit: 4 * 1024 * 1024 * 1024);

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('drive-http-');
    server = await _Server.start();
  });
  tearDown(() async {
    await server.close();
    directory.deleteSync(recursive: true);
  });

  group('over the network', () {
    test('sends words with their length and reads the answer', () async {
      server.reply = (
        status: 200,
        body: '{"id":"f1"}',
        headers: {'X-Kind': 'a'},
      );
      final response = await http.send(
        'POST',
        server.url('/files'),
        headers: {'authorization': 'Bearer t'},
        text: '{"name":"記帳本"}',
      );
      expect(response.ok, isTrue);
      expect(jsonDecode(response.body), {'id': 'f1'});
      // Headers by lowercase name, as Drive's location is looked up.
      expect(response.headers['x-kind'], 'a');
      final asked = server.asked.single;
      expect(asked.method, 'POST');
      expect(asked.body, '{"name":"記帳本"}');
      expect(asked.headers['authorization'], 'Bearer t');
      expect(
        asked.headers['content-length'],
        '${utf8.encode('{"name":"記帳本"}').length}',
      );
    });

    test('an answer past the limit is refused (review 22 finding 5)', () async {
      server.reply = (status: 200, body: 'x' * 100, headers: const {});
      // 100 bytes against a 64-byte limit.
      await expectLater(
        const IoDriveHttp(
          saveLimit: 64,
          answerLimit: 64,
        ).send('GET', server.url('/files')),
        throwsA(isA<AnswerTooLarge>()),
      );
      final into = File('${directory.path}/download.etbk');
      await expectLater(
        const IoDriveHttp(saveLimit: 64)
            .send('GET', server.url('/files/f1'), saveTo: into),
        throwsA(isA<AnswerTooLarge>()),
      );
    });

    test('sends a file as it is', () async {
      final file = File('${directory.path}/backup.etbk')
        ..writeAsBytesSync(List.generate(5000, (i) => i % 251));
      await http.send('PUT', server.url('/upload'), file: file);
      expect(server.asked.single.headers['content-length'], '5000');
      expect(server.asked.single.size, 5000);
    });

    test('a request with nothing to send says so', () async {
      await http.send('PATCH', server.url('/files/f1'));
      expect(server.asked.single.headers['content-length'], '0');
    });

    test('a download is written to the file, an error is not', () async {
      final into = File('${directory.path}/restore.etbk');
      server.reply = (status: 200, body: 'the backup', headers: const {});
      final ok = await http.send('GET', server.url('/files/f1'), saveTo: into);
      expect(ok.ok, isTrue);
      expect(into.readAsStringSync(), 'the backup');

      into.deleteSync();
      server.reply = (status: 404, body: '{"error":{}}', headers: const {});
      final missing = await http.send(
        'GET',
        server.url('/files/f2'),
        saveTo: into,
      );
      expect(missing.ok, isFalse);
      expect(missing.body, '{"error":{}}');
      expect(into.existsSync(), isFalse);
    });
  });

  group('what the person is told', () {
    DriveBackup drive(DriveHttp http) => DriveBackup(
      http,
      token: ({required interactive}) async => 'token',
      forget: (_) async {},
    );

    test('no connection is said as offline', () async {
      await expectLater(
        drive(_Offline()).list(),
        throwsA(
          isA<DriveException>()
              .having((e) => e.problem, 'problem', DriveProblem.offline)
              .having((e) => e.message, 'message', '連不上 Google，請稍後再試'),
        ),
      );
    });

    test('a refusal carries Drive\'s own reason', () async {
      final refusing = _Refusing(403, '{"error":{"message":"Rate limit"}}');
      await expectLater(
        drive(refusing).list(),
        throwsA(
          isA<DriveException>()
              .having((e) => e.status, 'status', 403)
              .having(
                (e) => e.message,
                'message',
                'Google 雲端硬碟沒有接受（403 Rate limit）',
              ),
        ),
      );
    });

    test('an answer that is not Drive\'s is a refusal, not a crash', () async {
      // As a Wi-Fi sign-in page given in Drive's place, with a 200.
      await expectLater(
        drive(_Refusing(200, '<html>Sign in to the Wi-Fi</html>')).list(),
        throwsA(
          isA<DriveException>().having(
            (e) => e.problem,
            'problem',
            DriveProblem.refused,
          ),
        ),
      );
      await expectLater(
        drive(_Refusing(200, '{"files":[{"name":"記帳本.etbk"}]}')).list(),
        throwsA(isA<DriveException>()),
        reason: 'a file without its id',
      );
    });

    test('a refusal that is not JSON still says its status', () async {
      await expectLater(
        drive(_Refusing(500, 'Server Error')).list(),
        throwsA(
          isA<DriveException>().having(
            (e) => e.message,
            'message',
            'Google 雲端硬碟沒有接受（500 ）',
          ),
        ),
      );
    });

    test('no access is said plainly', () async {
      final refused = DriveBackup(
        FakeDrive(),
        token: ({required interactive}) async => null,
        forget: (_) async {},
      );
      await expectLater(
        refused.list(),
        throwsA(
          isA<DriveException>()
              .having((e) => e.problem, 'problem', DriveProblem.notAllowed)
              .having((e) => e.message, 'message', '沒有取得 Google 雲端硬碟的權限'),
        ),
      );
      expect(
        const DriveException(DriveProblem.refused, '403 x').toString(),
        'DriveException(refused, 403 x)',
      );
    });

    test('a download that fails leaves no file', () async {
      final into = File('${directory.path}/restore.etbk');
      await expectLater(
        drive(_Offline()).download('f1', into),
        throwsA(isA<DriveException>()),
      );
      expect(into.existsSync(), isFalse);
    });
  });
}

/// Answers every request with [status] and [body].
final class _Refusing implements DriveHttp {
  _Refusing(this.status, this.body);

  final int status;
  final String body;

  @override
  Future<DriveResponse> send(
    String method,
    Uri url, {
    Map<String, String> headers = const {},
    String? text,
    File? file,
    File? saveTo,
  }) async => DriveResponse(status, body: body);
}
