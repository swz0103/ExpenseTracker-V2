import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_backup_probe/google_drive_adapter.dart';
import 'package:cloud_backup_probe/google_drive_http.dart';
import 'package:test/test.dart';

void main() {
  test('generateIds uses bearer auth and least-scope Drive endpoint', () async {
    final transport = _Transport([
      _json(HttpStatus.ok, {
        'ids': ['generated_1'],
      }),
    ]);
    final api = _api(transport);
    expect(await api.generateFileId(), 'generated_1');
    final request = transport.requests.single;
    expect(request.method, 'GET');
    expect(request.uri.path, '/drive/v3/files/generateIds');
    expect(request.uri.queryParameters, {
      'count': '1',
      'space': 'drive',
      'type': 'files',
    });
    expect(request.headers[HttpHeaders.authorizationHeader], 'Bearer token');
  });

  test('resumable upload pins trusted location and exact bytes', () async {
    final properties = _properties('backup-1', 3);
    final transport = _Transport([
      DriveHttpResponse(
        statusCode: HttpStatus.ok,
        headers: {
          'Location':
              'https://www.googleapis.com/upload/drive/v3/files?upload_id=abc',
        },
      ),
      _json(HttpStatus.ok, _file('generated_1', 3, properties)),
    ]);
    final result = await _api(transport).createFile(
      fileId: 'generated_1',
      name: 'backup.etv2backup',
      mimeType: 'application/vnd.expensetracker.backup+json',
      bytes: const [1, 2, 3],
      appProperties: properties,
    );
    expect(result.id, 'generated_1');
    expect(transport.requests, hasLength(2));
    final initiate = transport.requests.first;
    expect(initiate.method, 'POST');
    expect(initiate.uri.queryParameters['uploadType'], 'resumable');
    expect(
      jsonDecode(utf8.decode(initiate.body)),
      containsPair('id', 'generated_1'),
    );
    final upload = transport.requests.last;
    expect(upload.method, 'PUT');
    expect(upload.uri.host, 'www.googleapis.com');
    expect(upload.body, [1, 2, 3]);
  });

  test(
    'untrusted resumable location is rejected before bytes are sent',
    () async {
      final transport = _Transport([
        DriveHttpResponse(
          statusCode: HttpStatus.ok,
          headers: {'location': 'https://example.test/steal'},
        ),
      ]);
      await expectLater(
        _api(transport).createFile(
          fileId: 'generated_1',
          name: 'backup.etv2backup',
          mimeType: 'application/octet-stream',
          bytes: const [1],
          appProperties: const {},
        ),
        throwsA(_driveFailure(DriveApiFailure.unavailable)),
      );
      expect(transport.requests, hasLength(1));
    },
  );

  test('history follows every page and keeps the filtered query', () async {
    final properties = _properties('backup-1', 3);
    final transport = _Transport([
      _json(HttpStatus.ok, {
        'files': [_file('one', 3, properties)],
        'nextPageToken': 'next-token',
      }),
      _json(HttpStatus.ok, {
        'files': [_file('two', 3, properties)],
      }),
    ]);
    final files = await _api(transport).listBackupFiles();
    expect(files.map((file) => file.id), ['one', 'two']);
    expect(
      transport.requests.first.uri.queryParameters['q'],
      contains('trashed=false'),
    );
    expect(
      transport.requests.last.uri.queryParameters['pageToken'],
      'next-token',
    );
  });

  test('get, download and recoverable trash use exact object routes', () async {
    final properties = _properties('backup-1', 3);
    final transport = _Transport([
      _json(HttpStatus.ok, _file('one', 3, properties)),
      DriveHttpResponse(statusCode: HttpStatus.ok, body: const [1, 2, 3]),
      DriveHttpResponse(statusCode: HttpStatus.ok),
      DriveHttpResponse(statusCode: HttpStatus.notFound),
    ]);
    final api = _api(transport);
    expect((await api.getFile('one'))!.id, 'one');
    expect(await api.downloadFile('one'), [1, 2, 3]);
    await api.trashFile('one');
    expect(await api.getFile('missing'), isNull);
    expect(transport.requests[1].uri.queryParameters['alt'], 'media');
    expect(transport.requests[2].method, 'PATCH');
    expect(jsonDecode(utf8.decode(transport.requests[2].body)), {
      'trashed': true,
    });
    expect(
      transport.requests[2].headers[HttpHeaders.contentTypeHeader],
      'application/json; charset=utf-8',
    );
  });

  test('Drive HTTP failures retain actionable meanings', () async {
    final cases = <DriveHttpResponse, DriveApiFailure>{
      DriveHttpResponse(statusCode: HttpStatus.unauthorized):
          DriveApiFailure.authenticationRequired,
      _error(HttpStatus.forbidden, 'storageQuotaExceeded'):
          DriveApiFailure.quotaExceeded,
      _error(HttpStatus.forbidden, 'userRateLimitExceeded'):
          DriveApiFailure.throttled,
      _error(HttpStatus.forbidden, 'insufficientFilePermissions'):
          DriveApiFailure.permissionDenied,
      DriveHttpResponse(statusCode: HttpStatus.tooManyRequests):
          DriveApiFailure.throttled,
      DriveHttpResponse(statusCode: HttpStatus.internalServerError):
          DriveApiFailure.unavailable,
    };
    for (final entry in cases.entries) {
      await expectLater(
        _api(_Transport([entry.key])).generateFileId(),
        throwsA(_driveFailure(entry.value)),
      );
    }
  });

  test('lost trash response is reported as an uncertain result', () async {
    await expectLater(
      _api(_Transport([const DriveHttpTransportException()])).trashFile('one'),
      throwsA(_driveFailure(DriveApiFailure.uncertainResult)),
    );
  });

  test(
    'lost upload response is uncertain but initiation failure is unavailable',
    () async {
      final location = DriveHttpResponse(
        statusCode: HttpStatus.ok,
        headers: {
          'location':
              'https://www.googleapis.com/upload/drive/v3/files?upload_id=abc',
        },
      );
      final uploadFailure = _Transport([
        location,
        const DriveHttpTransportException(),
      ]);
      await expectLater(
        _api(uploadFailure).createFile(
          fileId: 'one',
          name: 'backup',
          mimeType: 'application/octet-stream',
          bytes: const [1],
          appProperties: const {},
        ),
        throwsA(_driveFailure(DriveApiFailure.uncertainResult)),
      );
      await expectLater(
        _api(_Transport([const DriveHttpTransportException()]))
            .generateFileId(),
        throwsA(_driveFailure(DriveApiFailure.unavailable)),
      );
    },
  );

  test(
    'invalid or header-injected token is rejected before transport',
    () async {
      for (final token in ['', 'token\r\ninjected: true']) {
        final transport = _Transport([]);
        await expectLater(
          GoogleDriveRestApi(
            transport: transport,
            tokens: _Token(token),
          ).generateFileId(),
          throwsA(_driveFailure(DriveApiFailure.authenticationRequired)),
        );
        expect(transport.requests, isEmpty);
      }
    },
  );
}

GoogleDriveRestApi _api(_Transport transport) =>
    GoogleDriveRestApi(transport: transport, tokens: const _Token('token'));

Matcher _driveFailure(DriveApiFailure failure) => isA<DriveApiException>()
    .having((error) => error.failure, 'failure', failure);

Map<String, String> _properties(String backupId, int length) => {
  'format': 'ExpenseTracker-V2-backup',
  'formatVersion': '1',
  'backupId': backupId,
  'sha256': 'a' * 64,
  'byteLength': '$length',
  'createdAt': DateTime.utc(2026, 10, 1).toIso8601String(),
};

Map<String, Object?> _file(
  String id,
  int length,
  Map<String, String> properties,
) => {
  'id': id,
  'mimeType': 'application/vnd.expensetracker.backup+json',
  'size': '$length',
  'appProperties': properties,
  'trashed': false,
};

DriveHttpResponse _json(int status, Object value) => DriveHttpResponse(
  statusCode: status,
  headers: const {'content-type': 'application/json'},
  body: utf8.encode(jsonEncode(value)),
);

DriveHttpResponse _error(int status, String reason) => _json(status, {
  'error': {
    'errors': [
      {'reason': reason},
    ],
  },
});

final class _Token implements DriveAccessTokenSource {
  const _Token(this.value);
  final String value;

  @override
  Future<String> accessToken() async => value;
}

final class _Transport implements DriveHttpTransport {
  _Transport(Iterable<Object> responses) : responses = Queue.of(responses);

  final Queue<Object> responses;
  final List<DriveHttpRequest> requests = [];

  @override
  Future<DriveHttpResponse> send(
    DriveHttpRequest request, {
    required Duration timeout,
  }) async {
    requests.add(request);
    final next = responses.removeFirst();
    if (next is DriveHttpTransportException) throw next;
    return next as DriveHttpResponse;
  }
}
