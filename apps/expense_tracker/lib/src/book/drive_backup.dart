import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// One HTTP exchange with Google Drive: the status, the headers (lower
/// case) and, unless it was saved to a file, the body.
final class DriveResponse {
  const DriveResponse(this.status, {this.headers = const {}, this.body = ''});

  final int status;
  final Map<String, String> headers;
  final String body;

  bool get ok => status >= 200 && status < 300;
}

/// Sends requests to Google; [IoDriveHttp] on the phone, a fake in tests.
abstract interface class DriveHttp {
  /// Sends [method] to [url]. The body is [text], or the bytes of [file];
  /// with [saveTo] a successful body is written there instead of returned.
  Future<DriveResponse> send(
    String method,
    Uri url, {
    Map<String, String> headers,
    String? text,
    File? file,
    File? saveTo,
  });
}

/// [DriveHttp] over dart:io.
final class IoDriveHttp implements DriveHttp {
  const IoDriveHttp();

  @override
  Future<DriveResponse> send(
    String method,
    Uri url, {
    Map<String, String> headers = const {},
    String? text,
    File? file,
    File? saveTo,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20)
      ..idleTimeout = const Duration(seconds: 20);
    try {
      final request = await client.openUrl(method, url);
      headers.forEach(request.headers.set);
      if (file != null) {
        request.contentLength = await file.length();
        await request.addStream(file.openRead());
      } else if (text != null) {
        final bytes = utf8.encode(text);
        request.contentLength = bytes.length;
        request.add(bytes);
      } else {
        request.contentLength = 0;
      }
      final response = await request.close().timeout(
        const Duration(minutes: 5),
      );
      final found = <String, String>{};
      response.headers.forEach((name, values) {
        found[name.toLowerCase()] = values.join(',');
      });
      final ok = response.statusCode >= 200 && response.statusCode < 300;
      if (saveTo != null && ok) {
        final sink = saveTo.openWrite();
        try {
          await sink.addStream(response);
          await sink.flush();
        } finally {
          await sink.close();
        }
        return DriveResponse(response.statusCode, headers: found);
      }
      final body = await response.transform(utf8.decoder).join();
      return DriveResponse(response.statusCode, headers: found, body: body);
    } finally {
      client.close(force: true);
    }
  }
}

/// A backup kept on Google Drive.
final class DriveFile {
  const DriveFile(this.id, this.name, this.modified, this.size);

  final String id;
  final String name;
  final DateTime modified;

  /// Bytes; 0 when Google did not say.
  final int size;
}

/// Why talking to Google Drive stopped.
enum DriveProblem {
  /// The person closed Google's sign-in or did not allow access.
  notAllowed,

  /// Google did not answer, or the phone is offline.
  offline,

  /// Drive refused or failed the request.
  refused,
}

final class DriveException implements Exception {
  const DriveException(this.problem, [this.detail]);

  final DriveProblem problem;
  final String? detail;

  /// What to tell the person.
  String get message => switch (problem) {
    DriveProblem.notAllowed => '沒有取得 Google 雲端硬碟的權限',
    DriveProblem.offline => '連不上 Google，請稍後再試',
    DriveProblem.refused => 'Google 雲端硬碟沒有接受（${detail ?? ''}）',
  };

  @override
  String toString() =>
      'DriveException(${problem.name}${detail == null ? '' : ', $detail'})';
}

/// The backups in the folder 記帳本備份 on the person's Google Drive,
/// through the Drive REST API with the `drive.file` scope: the app sees
/// only the files it made.
final class DriveBackup {
  DriveBackup(
    this._http, {
    required Future<String?> Function({required bool interactive}) token,
    required Future<void> Function(String token) forget,
  }) : _token = token,
       _forget = forget;

  final DriveHttp _http;
  final Future<String?> Function({required bool interactive}) _token;
  final Future<void> Function(String token) _forget;

  static const folderName = '記帳本備份';
  static const _folderType = 'application/vnd.google-apps.folder';
  static const _api = 'https://www.googleapis.com/drive/v3/files';
  static const _upload = 'https://www.googleapis.com/upload/drive/v3/files';

  String? _cached;
  String? _folder;

  /// Asks for access, showing Google's screens when [interactive]. False
  /// when it was not given.
  Future<bool> signIn({bool interactive = true}) async =>
      await _access(interactive: interactive) != null;

  /// Forgets the token this run holds, so the next request asks Google.
  Future<void> signOut() async {
    final token = _cached;
    _cached = null;
    _folder = null;
    if (token != null) await _forget(token);
  }

  Future<String?> _access({required bool interactive}) async {
    final cached = _cached;
    if (cached != null) return cached;
    final token = await _token(interactive: interactive);
    _cached = token;
    return token;
  }

  /// Sends a request with the access token; once more with a fresh token
  /// when Google says the old one ran out.
  Future<DriveResponse> _send(
    String method,
    Uri url, {
    required bool interactive,
    Map<String, String> headers = const {},
    String? text,
    File? file,
    File? saveTo,
  }) async {
    for (var attempt = 0; ; attempt++) {
      final token = await _access(interactive: interactive);
      if (token == null) throw const DriveException(DriveProblem.notAllowed);
      final DriveResponse response;
      try {
        response = await _http.send(
          method,
          url,
          headers: {...headers, 'authorization': 'Bearer $token'},
          text: text,
          file: file,
          saveTo: saveTo,
        );
      } on IOException catch (error) {
        throw DriveException(DriveProblem.offline, '$error');
      } on TimeoutException catch (error) {
        throw DriveException(DriveProblem.offline, '$error');
      }
      if (response.status == 401 && attempt == 0) {
        _cached = null;
        await _forget(token);
        continue;
      }
      if (!response.ok) {
        throw DriveException(
          DriveProblem.refused,
          '${response.status} ${_reason(response.body)}',
        );
      }
      return response;
    }
  }

  static String _reason(String body) {
    try {
      final json = jsonDecode(body) as Map<String, Object?>;
      final error = json['error'] as Map<String, Object?>?;
      return '${error?['message'] ?? ''}';
    } on Object {
      return '';
    }
  }

  static String _quote(String text) =>
      text.replaceAll(r'\', r'\\').replaceAll("'", r"\'");

  /// The folder's id, made when there is none.
  Future<String> _folderId({required bool interactive}) async {
    final known = _folder;
    if (known != null) return known;
    final found = await _send(
      'GET',
      Uri.parse(_api).replace(
        queryParameters: {
          'q':
              "name='${_quote(folderName)}' and mimeType='$_folderType' "
              'and trashed=false',
          'fields': 'files(id)',
          'spaces': 'drive',
        },
      ),
      interactive: interactive,
    );
    final files = (jsonDecode(found.body) as Map<String, Object?>)['files'];
    if (files is List && files.isNotEmpty) {
      return _folder = (files.first as Map<String, Object?>)['id']! as String;
    }
    final made = await _send(
      'POST',
      Uri.parse(_api).replace(queryParameters: {'fields': 'id'}),
      interactive: interactive,
      headers: {'content-type': 'application/json; charset=utf-8'},
      text: jsonEncode({'name': folderName, 'mimeType': _folderType}),
    );
    return _folder =
        (jsonDecode(made.body) as Map<String, Object?>)['id']! as String;
  }

  /// The backups in the folder, newest first.
  Future<List<DriveFile>> list({bool interactive = true}) async {
    final folder = await _folderId(interactive: interactive);
    final response = await _send(
      'GET',
      Uri.parse(_api).replace(
        queryParameters: {
          'q': "'${_quote(folder)}' in parents and trashed=false",
          'fields': 'files(id,name,size,modifiedTime)',
          'orderBy': 'modifiedTime desc',
          'pageSize': '100',
          'spaces': 'drive',
        },
      ),
      interactive: interactive,
    );
    final files =
        (jsonDecode(response.body) as Map<String, Object?>)['files']
            as List<Object?>? ??
        const [];
    return [
      for (final row in files.cast<Map<String, Object?>>())
        if ((row['name'] as String? ?? '').endsWith('.etbk'))
          DriveFile(
            row['id']! as String,
            row['name']! as String,
            DateTime.tryParse(row['modifiedTime'] as String? ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
            int.tryParse('${row['size'] ?? ''}') ?? 0,
          ),
    ]..sort((a, b) => b.modified.compareTo(a.modified));
  }

  /// Uploads [file] into the folder, then keeps only the newest [keep].
  Future<void> upload(
    File file, {
    bool interactive = true,
    int keep = 5,
  }) async {
    final folder = await _folderId(interactive: interactive);
    final name = file.uri.pathSegments.last;
    final start = await _send(
      'POST',
      Uri.parse(_upload).replace(
        queryParameters: {'uploadType': 'resumable', 'fields': 'id'},
      ),
      interactive: interactive,
      headers: {
        'content-type': 'application/json; charset=utf-8',
        'x-upload-content-type': 'application/octet-stream',
        'x-upload-content-length': '${await file.length()}',
      },
      text: jsonEncode({
        'name': name,
        'parents': [folder],
        'mimeType': 'application/octet-stream',
      }),
    );
    final location = start.headers['location'];
    if (location == null) {
      throw const DriveException(DriveProblem.refused, 'no upload address');
    }
    await _send(
      'PUT',
      Uri.parse(location),
      interactive: interactive,
      headers: {'content-type': 'application/octet-stream'},
      file: file,
    );
    final kept = await list(interactive: interactive);
    for (final old in kept.skip(keep)) {
      await _send(
        'DELETE',
        Uri.parse('$_api/${Uri.encodeComponent(old.id)}'),
        interactive: interactive,
      );
    }
  }

  /// Saves the backup [id] into [into].
  Future<void> download(
    String id,
    File into, {
    bool interactive = true,
  }) async {
    await into.parent.create(recursive: true);
    try {
      await _send(
        'GET',
        Uri.parse(
          '$_api/${Uri.encodeComponent(id)}',
        ).replace(queryParameters: {'alt': 'media'}),
        interactive: interactive,
        saveTo: into,
      );
    } on Object {
      if (into.existsSync()) await into.delete();
      rethrow;
    }
  }
}
