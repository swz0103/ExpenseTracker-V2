import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';

import 'drive_http.dart';

/// The `format` app property marking this app's backup files on Drive.
const driveBackupFormat = 'ETV2BK2';

/// Supplies OAuth access tokens. Tokens are never stored by this package.
abstract interface class DriveTokens {
  /// A current access token. [refresh] is true after Drive refused the
  /// previous token, and asks for a new one (health check G8-22).
  Future<String> accessToken({required bool refresh});
}

enum DriveFailure {
  /// No usable token, or a freshly refreshed token was refused too.
  authenticationRequired,
  permissionDenied,
  quotaExceeded,
  throttled,
  unavailable,

  /// The resumable upload session is gone; start a new one.
  sessionExpired,

  /// The request may have been applied; read the state back before
  /// repeating it.
  uncertain,

  /// A download did not match the file's size or SHA-256, or the file is
  /// larger than allowed.
  damaged,
}

final class DriveException implements Exception {
  const DriveException(this.failure);

  final DriveFailure failure;

  @override
  String toString() => 'DriveException(${failure.name})';
}

/// A Drive file as this app sees it.
final class DriveFile {
  const DriveFile({
    required this.id,
    required this.name,
    required this.byteLength,
    required this.appProperties,
    required this.trashed,
    this.sha256,
  });

  final String id;
  final String name;
  final int byteLength;
  final Map<String, String> appProperties;
  final bool trashed;

  /// Drive's own SHA-256 of the content, lower-case hex, when reported.
  final String? sha256;

  String? get backupId => appProperties['backupId'];

  /// The creation time claimed by the file's properties. It is not
  /// authenticated; the backup header carries the authenticated one.
  DateTime? get createdAt {
    final text = appProperties['createdAt'];
    return text == null ? null : DateTime.tryParse(text)?.toUtc();
  }
}

/// Backups found on Drive, newest first. Entries that cannot be read are
/// counted in [skipped] instead of hiding every other backup (G8-14).
final class DriveListing {
  const DriveListing(this.files, this.skipped);

  final List<DriveFile> files;
  final int skipped;
}

/// How much of a resumable upload the server holds. [file] is set once
/// the upload is complete.
final class UploadStatus {
  const UploadStatus(this.received, [this.file]);

  final int received;
  final DriveFile? file;

  bool get complete => file != null;
}

/// Drive v3 calls for backup files, over a [DriveTransport]. A refused
/// token is refreshed once and the request repeated.
final class DriveClient {
  DriveClient({
    required this.transport,
    required this.tokens,
    this.timeout = const Duration(seconds: 60),
  });

  final DriveTransport transport;
  final DriveTokens tokens;
  final Duration timeout;

  static final _api = Uri.parse('https://www.googleapis.com/drive/v3/');
  static final _upload = Uri.parse(
    'https://www.googleapis.com/upload/drive/v3/',
  );
  static const _fields = 'id,name,size,appProperties,trashed,sha256Checksum';
  static const _json = 'application/json; charset=utf-8';
  static const _maxPages = 100;

  Future<String> generateId() async {
    final response = await _send(
      'GET',
      _api
          .resolve('files/generateIds')
          .replace(
            queryParameters: const {
              'count': '1',
              'space': 'drive',
              'type': 'files',
            },
          ),
    );
    final ids = _object(response)['ids'];
    if (ids is! List || ids.length != 1 || ids.single is! String) {
      throw const DriveException(DriveFailure.unavailable);
    }
    return ids.single as String;
  }

  /// The file, or null when Drive does not know it.
  Future<DriveFile?> file(String id) async {
    final response = await _send(
      'GET',
      _fileUri(id).replace(queryParameters: const {'fields': _fields}),
      accept: const {404},
    );
    if (response.statusCode == 404) return null;
    return _file(_object(response));
  }

  /// Every backup file not in the trash, newest first.
  Future<DriveListing> listBackups() async {
    final files = <DriveFile>[];
    var skipped = 0;
    final seen = <String>{};
    String? pageToken;
    for (var page = 0; page < _maxPages; page++) {
      final response = await _send(
        'GET',
        _api
            .resolve('files')
            .replace(
              queryParameters: {
                'q':
                    "appProperties has { key='format' and "
                    "value='$driveBackupFormat' } and trashed=false",
                'fields': 'nextPageToken,files($_fields)',
                'pageSize': '1000',
                if (pageToken != null) 'pageToken': pageToken,
              },
            ),
      );
      final json = _object(response);
      final rows = json['files'];
      if (rows is! List) throw const DriveException(DriveFailure.unavailable);
      for (final row in rows) {
        final file = _listed(row);
        if (file == null) {
          skipped++;
        } else {
          files.add(file);
        }
      }
      final next = json['nextPageToken'];
      if (next == null) {
        files.sort((a, b) => b.createdAt!.compareTo(a.createdAt!));
        return DriveListing(List.unmodifiable(files), skipped);
      }
      if (next is! String || next.isEmpty || !seen.add(next)) {
        throw const DriveException(DriveFailure.unavailable);
      }
      pageToken = next;
    }
    throw const DriveException(DriveFailure.unavailable);
  }

  /// Downloads [file] into [target] in ranged pieces of [chunkSize], so
  /// memory stays at one piece whatever the file size (health check H-02).
  /// The size and, when Drive reports it, the SHA-256 must match; on any
  /// failure [target] is deleted and nothing else is touched.
  Future<void> downloadTo(
    DriveFile file,
    File target, {
    int chunkSize = 8 << 20,
    int maxBytes = 512 << 20,
  }) async {
    if (chunkSize <= 0) throw ArgumentError.value(chunkSize, 'chunkSize');
    final length = file.byteLength;
    if (length <= 0 || length > maxBytes) {
      throw const DriveException(DriveFailure.damaged);
    }
    final uri = _fileUri(file.id).replace(
      queryParameters: const {'alt': 'media'},
    );
    final sink = Sha256().newHashSink();
    final out = await target.open(mode: FileMode.write);
    var completed = false;
    try {
      for (var offset = 0; offset < length; offset += chunkSize) {
        final end = offset + chunkSize < length ? offset + chunkSize : length;
        final response = await _send(
          'GET',
          uri,
          headers: {'range': 'bytes=$offset-${end - 1}'},
          maxResponseBytes: end - offset,
        );
        final whole = response.statusCode == 200 && offset == 0;
        if ((response.statusCode != 206 && !whole) ||
            response.body.length != end - offset) {
          throw const DriveException(DriveFailure.damaged);
        }
        sink.add(response.body);
        await out.writeFrom(response.body);
        if (whole) break;
      }
      await out.flush();
      sink.close();
      final hash = await sink.hash();
      final hex = [
        for (final byte in hash.bytes) byte.toRadixString(16).padLeft(2, '0'),
      ].join();
      final expected = file.sha256;
      if (await out.length() != length ||
          (expected != null && expected != hex)) {
        throw const DriveException(DriveFailure.damaged);
      }
      completed = true;
    } finally {
      await out.close();
      if (!completed && await target.exists()) await target.delete();
    }
  }

  /// Moves the file to the Drive trash.
  Future<void> trash(String id) async {
    await _send(
      'PATCH',
      _fileUri(id).replace(queryParameters: const {'fields': 'id'}),
      body: utf8.encode(jsonEncode(const {'trashed': true})),
      headers: const {'content-type': _json},
      mayCommit: true,
    );
  }

  /// Opens a resumable upload session for a new file with a reserved
  /// [fileId], so a lost reply can be checked with [file].
  Future<Uri> startUpload({
    required String fileId,
    required String name,
    required int length,
    required Map<String, String> appProperties,
  }) async {
    if (length <= 0) throw ArgumentError.value(length, 'length');
    const type = 'application/octet-stream';
    final response = await _send(
      'POST',
      _upload
          .resolve('files')
          .replace(
            queryParameters: const {
              'uploadType': 'resumable',
              'fields': _fields,
            },
          ),
      body: utf8.encode(
        jsonEncode({
          'id': fileId,
          'name': name,
          'mimeType': type,
          'appProperties': appProperties,
        }),
      ),
      headers: {
        'content-type': _json,
        'x-upload-content-type': type,
        'x-upload-content-length': '$length',
      },
    );
    final location = Uri.tryParse(response.headers['location'] ?? '');
    if (location == null || !trustedSession(location)) {
      throw const DriveException(DriveFailure.unavailable);
    }
    return location;
  }

  /// Asks how many bytes of [session] the server has.
  Future<UploadStatus> uploadStatus(Uri session, int length) async {
    final response = await _session(
      session,
      const [],
      'bytes */$length',
      mayCommit: false,
    );
    return _status(response);
  }

  /// Sends [bytes] at [offset]. Every chunk but the last must be a
  /// multiple of 256 KiB.
  Future<UploadStatus> putChunk(
    Uri session, {
    required int offset,
    required List<int> bytes,
    required int length,
  }) async {
    if (bytes.isEmpty || offset < 0 || offset + bytes.length > length) {
      throw ArgumentError('Chunk outside the upload.');
    }
    final last = offset + bytes.length - 1;
    final response = await _session(
      session,
      bytes,
      'bytes $offset-$last/$length',
      mayCommit: true,
    );
    return _status(response);
  }

  /// Only Google's upload hosts may receive a token with the upload body.
  static bool trustedSession(Uri uri) {
    final host = uri.host.toLowerCase();
    return uri.scheme == 'https' &&
        uri.userInfo.isEmpty &&
        uri.fragment.isEmpty &&
        (host == 'googleapis.com' || host.endsWith('.googleapis.com'));
  }

  Future<DriveResponse> _session(
    Uri session,
    List<int> body,
    String range, {
    required bool mayCommit,
  }) async {
    if (!trustedSession(session)) {
      throw const DriveException(DriveFailure.sessionExpired);
    }
    return _send(
      'PUT',
      session,
      body: body,
      headers: {'content-range': range},
      accept: const {308},
      mayCommit: mayCommit,
      session: true,
    );
  }

  UploadStatus _status(DriveResponse response) {
    if (response.statusCode != 308) {
      final file = _file(_object(response));
      return UploadStatus(file.byteLength, file);
    }
    final range = response.headers['range'];
    if (range == null) return const UploadStatus(0);
    final match = RegExp(r'^bytes=0-(\d{1,15})$').firstMatch(range);
    if (match == null) throw const DriveException(DriveFailure.unavailable);
    return UploadStatus(int.parse(match.group(1)!) + 1);
  }

  Future<DriveResponse> _send(
    String method,
    Uri uri, {
    List<int> body = const [],
    Map<String, String> headers = const {},
    int maxResponseBytes = 1 << 20,
    Set<int> accept = const {},
    bool mayCommit = false,
    bool session = false,
  }) async {
    for (var refresh = false; ; refresh = true) {
      final token = await _token(refresh: refresh);
      final DriveResponse response;
      try {
        response = await transport.send(
          DriveRequest(
            method: method,
            uri: uri,
            headers: {
              'authorization': 'Bearer $token',
              'accept': 'application/json',
              ...headers,
            },
            body: body,
            maxResponseBytes: maxResponseBytes,
          ),
          timeout: timeout,
        );
      } on DriveTransportException {
        throw DriveException(
          mayCommit ? DriveFailure.uncertain : DriveFailure.unavailable,
        );
      }
      final status = response.statusCode;
      if (status == 401 && !refresh) continue;
      if ((status >= 200 && status < 300) || accept.contains(status)) {
        return response;
      }
      // Drive answers 404 or 410 for an expired or lost upload session.
      if (session && (status == 404 || status == 410)) {
        throw const DriveException(DriveFailure.sessionExpired);
      }
      throw DriveException(_failure(response, mayCommit: mayCommit));
    }
  }

  Future<String> _token({required bool refresh}) async {
    final String token;
    try {
      token = await tokens.accessToken(refresh: refresh);
    } on Object {
      throw const DriveException(DriveFailure.authenticationRequired);
    }
    if (token.isEmpty ||
        token.length > 8192 ||
        !RegExp(r'^[\x21-\x7e]+$').hasMatch(token)) {
      throw const DriveException(DriveFailure.authenticationRequired);
    }
    return token;
  }

  static Uri _fileUri(String id) =>
      _api.resolve('files/${Uri.encodeComponent(id)}');
}

DriveFailure _failure(DriveResponse response, {required bool mayCommit}) {
  final status = response.statusCode;
  if (status == 401) return DriveFailure.authenticationRequired;
  if (status == 429) return DriveFailure.throttled;
  if (status >= 500 || status == 408) {
    return mayCommit ? DriveFailure.uncertain : DriveFailure.unavailable;
  }
  if (status == 403) {
    final reasons = _reasons(response.body);
    if (reasons.contains('storageQuotaExceeded')) {
      return DriveFailure.quotaExceeded;
    }
    if (reasons.any((r) => r.endsWith('RateLimitExceeded')) ||
        reasons.contains('rateLimitExceeded')) {
      return DriveFailure.throttled;
    }
    return DriveFailure.permissionDenied;
  }
  return DriveFailure.unavailable;
}

Set<String> _reasons(List<int> body) {
  try {
    final value = jsonDecode(utf8.decode(body));
    if (value is! Map<String, Object?>) return const {};
    final error = value['error'];
    if (error is! Map<String, Object?>) return const {};
    final errors = error['errors'];
    if (errors is! List) return const {};
    return {
      for (final item in errors)
        if (item is Map<String, Object?> && item['reason'] is String)
          item['reason']! as String,
    };
  } on FormatException {
    return const {};
  }
}

Map<String, Object?> _object(DriveResponse response) {
  try {
    final value = jsonDecode(utf8.decode(response.body));
    if (value is Map<String, Object?>) return value;
  } on FormatException {
    // Reported below without echoing provider data.
  }
  throw const DriveException(DriveFailure.unavailable);
}

DriveFile _file(Map<String, Object?> json) {
  final file = _parse(json);
  if (file == null) throw const DriveException(DriveFailure.unavailable);
  return file;
}

/// A listed backup, or null when the entry is malformed or incomplete.
DriveFile? _listed(Object? row) {
  if (row is! Map<String, Object?>) return null;
  final file = _parse(row);
  if (file == null ||
      file.trashed ||
      file.appProperties['format'] != driveBackupFormat ||
      (file.backupId ?? '').isEmpty ||
      file.createdAt == null) {
    return null;
  }
  return file;
}

DriveFile? _parse(Map<String, Object?> json) {
  final id = json['id'];
  final name = json['name'];
  final size = switch (json['size']) {
    final String text => int.tryParse(text),
    final int value => value,
    _ => null,
  };
  final properties = json['appProperties'] ?? const <String, Object?>{};
  final trashed = json['trashed'] ?? false;
  final sha = json['sha256Checksum'];
  if (id is! String ||
      id.isEmpty ||
      name is! String ||
      size == null ||
      size < 0 ||
      properties is! Map<String, Object?> ||
      trashed is! bool ||
      (sha != null && (sha is! String || !_hex.hasMatch(sha)))) {
    return null;
  }
  final strings = <String, String>{};
  for (final MapEntry(:key, :value) in properties.entries) {
    if (value is! String) return null;
    strings[key] = value;
  }
  return DriveFile(
    id: id,
    name: name,
    byteLength: size,
    appProperties: Map.unmodifiable(strings),
    trashed: trashed,
    sha256: (sha as String?)?.toLowerCase(),
  );
}

final _hex = RegExp(r'^[0-9a-fA-F]{64}$');
