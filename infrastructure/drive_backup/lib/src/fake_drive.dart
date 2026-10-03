import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'drive_client.dart';
import 'drive_http.dart';

/// Tokens that turn into a new token on refresh.
final class FakeTokens implements DriveTokens {
  int issued = 0;
  bool signedOut = false;

  @override
  Future<String> accessToken({required bool refresh}) async {
    if (signedOut) throw StateError('signed out');
    if (refresh || issued == 0) issued++;
    return 'token-$issued';
  }
}

enum FaultKind {
  /// The request never reaches the server.
  dropBefore,

  /// The server applies the request but the reply is lost.
  dropAfter,

  /// The server answers with [Fault.status] without applying anything.
  status,
}

final class Fault {
  Fault(this.kind, this.matches, {this.status = 503, this.times = 1});

  final FaultKind kind;
  final bool Function(DriveRequest request) matches;
  final int status;
  int times;
}

final class FakeFile {
  FakeFile(this.id, this.name, this.properties, this.bytes, this.sha256);

  final String id;
  final String name;
  final Map<String, String> properties;
  final List<int> bytes;
  final String sha256;
  bool trashed = false;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'size': '${bytes.length}',
    'appProperties': properties,
    'trashed': trashed,
    'sha256Checksum': sha256,
  };
}

final class _Session {
  _Session(this.fileId, this.name, this.properties, this.length);

  final String fileId;
  final String name;
  final Map<String, String> properties;
  final int length;
  final BytesBuilder received = BytesBuilder();
  FakeFile? done;
}

/// An in-memory Google Drive that speaks the resumable upload protocol.
final class FakeDrive implements DriveTransport {
  final files = <String, FakeFile>{};
  final _sessions = <String, _Session>{};
  final faults = <Fault>[];
  final requests = <DriveRequest>[];

  /// Raw rows added to every listing, for malformed entries.
  final extraRows = <Object?>[];

  /// Tokens Drive accepts; the first refresh makes `token-2` valid.
  Set<String> validTokens = {'token-1', 'token-2'};
  int _ids = 0;
  int _sessionIds = 0;

  int get uploadedBytes => [
    for (final r in requests)
      if (r.method == 'PUT') r.body.length,
  ].fold(0, (a, b) => a + b);

  int get sessionsStarted => _sessionIds;

  void expireSessions() => _sessions.clear();

  @override
  Future<DriveResponse> send(
    DriveRequest request, {
    required Duration timeout,
  }) async {
    requests.add(request);
    final fault = _fault(request);
    if (fault?.kind == FaultKind.dropBefore) {
      throw const DriveTransportException();
    }
    if (fault != null && fault.kind == FaultKind.status) {
      return _json(fault.status, {
        'error': {'code': fault.status},
      });
    }
    final token = request.headers['authorization']?.substring(7);
    final DriveResponse response;
    if (!validTokens.contains(token)) {
      response = _json(401, {'error': 'expired'});
    } else {
      response = await _handle(request);
    }
    if (fault?.kind == FaultKind.dropAfter) {
      throw const DriveTransportException();
    }
    return response;
  }

  Fault? _fault(DriveRequest request) {
    for (final fault in faults) {
      if (fault.times > 0 && fault.matches(request)) {
        fault.times--;
        return fault;
      }
    }
    return null;
  }

  Future<DriveResponse> _handle(DriveRequest request) async {
    final uri = request.uri;
    final path = uri.path;
    if (path == '/upload/drive/v3/files') {
      if (request.method == 'POST') return _start(request);
      return _put(request);
    }
    if (path == '/drive/v3/files/generateIds') {
      return _json(200, {
        'ids': ['file-${++_ids}'],
      });
    }
    if (path == '/drive/v3/files') {
      return _json(200, {
        'files': [
          for (final file in files.values)
            if (!file.trashed) file.toJson(),
          ...extraRows,
        ],
      });
    }
    final id = Uri.decodeComponent(path.substring('/drive/v3/files/'.length));
    final file = files[id];
    if (file == null) return _json(404, {'error': 'not found'});
    if (request.method == 'PATCH') {
      file.trashed = true;
      return _json(200, {'id': id});
    }
    if (uri.queryParameters['alt'] == 'media') {
      return DriveResponse(statusCode: 200, body: file.bytes);
    }
    return _json(200, file.toJson());
  }

  DriveResponse _start(DriveRequest request) {
    final meta = jsonDecode(utf8.decode(request.body)) as Map<String, Object?>;
    final id = 'session-${++_sessionIds}';
    _sessions[id] = _Session(
      meta['id']! as String,
      meta['name']! as String,
      (meta['appProperties']! as Map<String, Object?>).cast<String, String>(),
      int.parse(request.headers['x-upload-content-length']!),
    );
    return DriveResponse(
      statusCode: 200,
      headers: {
        'location':
            'https://www.googleapis.com/upload/drive/v3/files'
            '?uploadType=resumable&upload_id=$id',
      },
    );
  }

  Future<DriveResponse> _put(DriveRequest request) async {
    final session = _sessions[request.uri.queryParameters['upload_id']];
    if (session == null) return _json(404, {'error': 'no session'});
    final range = request.headers['content-range']!;
    if (session.done != null) return _json(200, session.done!.toJson());
    if (!range.startsWith('bytes */')) {
      final match = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$').firstMatch(range)!;
      final start = int.parse(match.group(1)!);
      final end = int.parse(match.group(2)!);
      final last = end + 1 == session.length;
      if (start == session.received.length &&
          end - start + 1 == request.body.length &&
          (last || request.body.length % (256 * 1024) == 0)) {
        session.received.add(request.body);
      }
    }
    final received = session.received.length;
    if (received == session.length) {
      final bytes = session.received.toBytes();
      final hash = await Sha256().hash(bytes);
      final hex = [
        for (final b in hash.bytes) b.toRadixString(16).padLeft(2, '0'),
      ].join();
      final file = FakeFile(
        session.fileId,
        session.name,
        session.properties,
        bytes,
        hex,
      );
      files[file.id] = file;
      session.done = file;
      return _json(200, file.toJson());
    }
    return DriveResponse(
      statusCode: 308,
      headers: {if (received > 0) 'range': 'bytes=0-${received - 1}'},
    );
  }

  static DriveResponse _json(int status, Object? body) => DriveResponse(
    statusCode: status,
    headers: const {'content-type': 'application/json'},
    body: utf8.encode(jsonEncode(body)),
  );
}

bool isChunk(DriveRequest r) =>
    r.method == 'PUT' && !r.headers['content-range']!.startsWith('bytes */');
