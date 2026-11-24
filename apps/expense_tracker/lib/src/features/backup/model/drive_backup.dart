import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../core/diagnostics/error_log.dart';
import '../../../core/platform/bounded_https.dart';
import '../../../core/formatting/json_fields.dart';
import '../../../core/diagnostics/error_steps.dart';

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
  /// with [saveTo] a successful body is written there instead of returned,
  /// refused past [saveLimit] bytes (required with [saveTo]).
  Future<DriveResponse> send(
    String method,
    Uri url, {
    Map<String, String> headers,
    String? text,
    File? file,
    File? saveTo,
    int? saveLimit,
  });
}

/// [DriveHttp] over dart:io, through [BoundedHttps]: a redirect is
/// followed only to `https`, an answer's words are read up to
/// [answerLimit] and a saved body up to the limit its request gives,
/// which may not pass [saveLimit].
final class IoDriveHttp implements DriveHttp {
  const IoDriveHttp({
    required this.saveLimit,
    this.answerLimit = maxAnswerBytes,
  });

  /// The most any body saved to a file may weigh: no backup is larger
  /// (`LedgerBackup.maxBackupBytes`, given by the app). A request that
  /// allows more is refused before it is sent.
  final int saveLimit;

  /// The most a JSON answer from Drive may weigh: a page of
  /// [DriveBackup.pageSize] backups is some tens of kilobytes.
  static const maxAnswerBytes = 1024 * 1024;

  /// The most an answer read as words may weigh, in bytes.
  final int answerLimit;

  /// Any `https` address: Drive's own hosts move; the token goes only to
  /// the origin first asked ([BoundedHttps.open]).
  static bool _https(Uri to) => true;

  @override
  Future<DriveResponse> send(
    String method,
    Uri url, {
    Map<String, String> headers = const {},
    String? text,
    File? file,
    File? saveTo,
    int? saveLimit,
  }) async {
    if (saveTo != null) {
      final allowed = saveLimit ?? (throw ArgumentError.notNull('saveLimit'));
      if (allowed > this.saveLimit) throw AnswerTooLarge(this.saveLimit, url);
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20)
      ..idleTimeout = const Duration(seconds: 20);
    try {
      final response = await BoundedHttps.open(
        client,
        method,
        url,
        allowed: _https,
        headers: headers,
        wait: const Duration(minutes: 5),
        send: (request) async {
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
        },
      );
      final found = <String, String>{};
      response.headers.forEach((name, values) {
        found[name.toLowerCase()] = values.join(',');
      });
      final ok = response.statusCode >= 200 && response.statusCode < 300;
      if (saveTo != null && ok) {
        // A body that stops arriving for a minute is given up on.
        await BoundedHttps.save(
          response,
          saveTo,
          saveLimit!,
          uri: url,
          stall: const Duration(minutes: 1),
        );
        return DriveResponse(response.statusCode, headers: found);
      }
      final body = await BoundedHttps.text(
        response,
        answerLimit,
        uri: url,
        stall: const Duration(minutes: 1),
      );
      return DriveResponse(response.statusCode, headers: found, body: body);
    } finally {
      client.close(force: true);
    }
  }
}

/// A backup kept on Google Drive.
final class DriveFile {
  const DriveFile(this.id, this.name, this.modified, this.size, {this.epoch});

  final String id;
  final String name;
  final DateTime modified;

  /// Bytes; 0 when Google did not say.
  final int size;

  /// The backup key epoch it was sealed with, as marked when it went up
  /// (its digits, as Drive keeps them); null for one sent before backups
  /// were so marked.
  final String? epoch;
}

/// Why talking to Google Drive stopped.
enum DriveProblem {
  /// The person closed Google's sign-in or did not allow access.
  notAllowed,

  /// Google did not answer, or the phone is offline.
  offline,

  /// Google's sign-in gave no answer at all within [DriveBackup.signInWait]
  /// (its screen closed without a word, or Android paused the app).
  noAnswer,

  /// Drive refused or failed the request.
  refused,
}

final class DriveException implements Exception {
  const DriveException(this.problem, [this.detail, this.status]);

  final DriveProblem problem;
  final String? detail;

  /// Drive's HTTP status, when it answered.
  final int? status;

  /// What to tell the person.
  String get message => switch (problem) {
    DriveProblem.notAllowed => '沒有取得 Google 雲端硬碟的權限',
    DriveProblem.offline => '連不上 Google，請稍後再試',
    DriveProblem.noAnswer => 'Google 沒有回應，請再試一次',
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
  DriveBackup(this._http, {required this._token, required this._forget});

  final DriveHttp _http;
  final Future<String?> Function({required bool interactive}) _token;
  final Future<void> Function(String token) _forget;

  static const folderName = '記帳本備份';
  static const _folderType = 'application/vnd.google-apps.folder';
  static const _api = 'https://www.googleapis.com/drive/v3/files';
  static const _upload = 'https://www.googleapis.com/upload/drive/v3/files';
  static const _about = 'https://www.googleapis.com/drive/v3/about';

  /// How long Google's sign-in may take with its screens shown, as the
  /// person picks an account; and without them.
  static const signInWait = Duration(minutes: 2);
  static const quietSignInWait = Duration(seconds: 30);

  String? _cached;
  String? _folder;

  /// Asks for access, showing Google's screens when [interactive]. False
  /// when it was not given.
  Future<bool> signIn({bool interactive = true}) async =>
      await _access(interactive: interactive) != null;

  /// Takes back the access Google gave this app, so the next sign-in asks
  /// for an account again; best effort, offline it only forgets here.
  Future<void> signOut() async {
    String? token;
    try {
      token = _cached ?? await _token(interactive: false);
    } on Object catch (error) {
      ErrorLog.instance.record('Google 授權', error);
      token = null;
    }
    _cached = null;
    _folder = null;
    if (token == null) return;
    try {
      await _http.send(
        'POST',
        Uri.parse('https://oauth2.googleapis.com/revoke'),
        headers: {'content-type': 'application/x-www-form-urlencoded'},
        text: 'token=${Uri.encodeQueryComponent(token)}',
      );
    } on Object catch (error, stack) {
      // Revoked later from the Google account's settings, if wanted.
      ErrorLog.instance.record(ErrorSteps.driveRevoke, error, stack);
    }
    await _forget(token);
  }

  Future<String?> _access({required bool interactive}) async {
    final cached = _cached;
    if (cached != null) return cached;
    // A sign-in that never answers would hold the backup, and every one
    // after it, forever.
    final token = await _token(interactive: interactive).timeout(
      interactive ? signInWait : quietSignInWait,
      onTimeout: () => throw const DriveException(DriveProblem.noAnswer),
    );
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
    int? saveLimit,
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
          saveLimit: saveLimit,
        );
      } on AnswerTooLarge catch (error) {
        // Not the network: what came was larger than it may be.
        throw DriveException(DriveProblem.refused, ErrorLog.describe(error));
      } on RedirectRefused catch (error) {
        throw DriveException(DriveProblem.refused, ErrorLog.describe(error));
      } on IOException catch (error) {
        throw DriveException(DriveProblem.offline, ErrorLog.describe(error));
      } on TimeoutException catch (error) {
        throw DriveException(DriveProblem.offline, ErrorLog.describe(error));
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
          response.status,
        );
      }
      return response;
    }
  }

  static String _reason(String body) {
    try {
      return JsonFields.decode(body).object('error')?.text('message') ?? '';
    } on FormatException {
      // A body that is not JSON has no message.
      return '';
    }
  }

  /// Drive's answer as an object; one that is not, such as a page a
  /// hotel's Wi-Fi puts in its place, is Drive not taking the request.
  static JsonFields _answer(DriveResponse response) {
    try {
      return JsonFields.decode(response.body);
    } on FormatException catch (error) {
      throw DriveException(DriveProblem.refused, error.message);
    }
  }

  /// Field [key] of [json], or Drive not taking the request.
  static T _need<T extends Object>(JsonFields json, String key) {
    try {
      return json.need<T>(key);
    } on FormatException catch (error) {
      throw DriveException(DriveProblem.refused, error.message);
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
    final files = _answer(found).objects('files') ?? const [];
    if (files.isNotEmpty) {
      return _folder = _need<String>(files.first, 'id');
    }
    final made = await _send(
      'POST',
      Uri.parse(_api).replace(queryParameters: {'fields': 'id'}),
      interactive: interactive,
      headers: {'content-type': 'application/json; charset=utf-8'},
      text: jsonEncode({'name': folderName, 'mimeType': _folderType}),
    );
    return _folder = _need<String>(_answer(made), 'id');
  }

  /// How many backups Drive is asked for at a time; the rest come a page
  /// after another ([list]).
  static const pageSize = 100;

  /// The most pages [list] reads: [pageSize] × 50 = 5,000 backups, far
  /// past any folder, so a Drive that keeps answering with more cannot
  /// hold it forever.
  static const _mostPages = 50;

  /// The backups in the folder, newest first, every page of them; with
  /// [ledger], only those of that ledger.
  Future<List<DriveFile>> list({
    bool interactive = true,
    String? ledger,
  }) async {
    final folder = await _folderId(interactive: interactive);
    final files = <JsonFields>[];
    String? page;
    for (var read = 0; read < _mostPages; read++) {
      final response = await _send(
        'GET',
        Uri.parse(_api).replace(
          queryParameters: {
            'q':
                "'${_quote(folder)}' in parents and trashed=false"
                '${ledger == null ? '' : " and appProperties has { key='ledger' and value='${_quote(ledger)}' }"}',
            'fields':
                'nextPageToken,files(id,name,size,modifiedTime,appProperties)',
            'orderBy': 'modifiedTime desc',
            'pageSize': '$pageSize',
            'spaces': 'drive',
            'pageToken': ?page,
          },
        ),
        interactive: interactive,
      );
      final answer = _answer(response);
      files.addAll(answer.objects('files') ?? const []);
      page = answer.text('nextPageToken');
      if (page == null || page.isEmpty) break;
    }
    return [
      for (final row in files)
        if ((row.text('name') ?? '').endsWith('.etbk'))
          DriveFile(
            _need<String>(row, 'id'),
            _need<String>(row, 'name'),
            DateTime.tryParse(row.text('modifiedTime') ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
            _size(row) ?? 0,
            epoch: row.object('appProperties')?.text(epochProperty),
          ),
    ]..sort((a, b) => b.modified.compareTo(a.modified));
  }

  /// The size in bytes [json] gives; null when it gives none. Drive
  /// writes sizes as words.
  static int? _size(JsonFields json) =>
      int.tryParse(json.text('size') ?? '') ?? json.whole('size');

  /// The property a backup goes up marked with: the backup key epoch it
  /// was sealed with, so those of keys since replaced can be found (D15).
  static const epochProperty = 'epoch';

  /// Uploads [file] into the folder, marked as a backup of [ledger] and
  /// with the key [epoch] it was sealed with ([epochProperty]), then
  /// moves that ledger's older backups beyond the newest [keep] to the
  /// Drive trash. Backups of other ledgers, and those made before backups
  /// were marked, are never touched. Pruning is best effort: the upload
  /// stands even when it fails.
  Future<void> upload(
    File file, {
    required String ledger,
    int? epoch,
    bool interactive = true,
    int keep = 5,
  }) async {
    final folder = await _folderId(interactive: interactive);
    final name = file.uri.pathSegments.last;
    final start = await _send(
      'POST',
      Uri.parse(
        _upload,
      ).replace(queryParameters: {'uploadType': 'resumable', 'fields': 'id'}),
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
        'appProperties': {
          'ledger': ledger,
          if (epoch != null) epochProperty: '$epoch',
        },
      }),
    );
    final location = start.headers['location'];
    if (location == null) {
      throw const DriveException(DriveProblem.refused, 'no upload address');
    }
    final target = Uri.tryParse(location);
    if (target == null || !isGoogleUpload(target)) {
      // Never sent elsewhere, with the token, whatever answered.
      throw const DriveException(DriveProblem.refused, 'upload address');
    }
    await _send(
      'PUT',
      target,
      interactive: interactive,
      headers: {'content-type': 'application/octet-stream'},
      file: file,
    );
    try {
      final kept = await list(interactive: interactive, ledger: ledger);
      for (final old in kept.skip(keep)) {
        await trash(old.id, interactive: interactive);
      }
    } on DriveException catch (error) {
      // Tried again after the next upload.
      ErrorLog.instance.record(ErrorSteps.driveTrim, error);
    }
  }

  /// Moves [id] to the Drive trash, where it stays restorable for 30 days;
  /// one already gone is fine.
  Future<void> trash(String id, {bool interactive = true}) async {
    try {
      await _send(
        'PATCH',
        Uri.parse('$_api/${Uri.encodeComponent(id)}')
            .replace(queryParameters: {'fields': 'id'}),
        interactive: interactive,
        headers: {'content-type': 'application/json; charset=utf-8'},
        text: jsonEncode({'trashed': true}),
      );
    } on DriveException catch (error) {
      if (error.status != 404) rethrow;
    }
  }

  /// The address of the Google account Drive is linked to; null when
  /// Drive does not say.
  Future<String?> account({bool interactive = true}) async {
    final response = await _send(
      'GET',
      Uri.parse(_about)
          .replace(queryParameters: {'fields': 'user(emailAddress)'}),
      interactive: interactive,
    );
    final user = _answer(response).object('user');
    final address = user?.text('emailAddress');
    return address == null || address.isEmpty ? null : address;
  }

  /// Whether [location], where Drive says to send a backup's bytes, is
  /// Google's own over HTTPS: the backup and the access token go only
  /// there.
  static bool isGoogleUpload(Uri location) {
    final host = location.host.toLowerCase();
    return location.scheme == 'https' &&
        (host == 'googleapis.com' || host.endsWith('.googleapis.com'));
  }

  /// Saves the backup [id] into [into]: no more than the size Drive
  /// gives for it, so a broken or hostile answer cannot fill the phone. A
  /// file whose size Drive does not give is refused, and one larger than
  /// any backup is refused by [DriveHttp] before it is asked for.
  Future<void> download(String id, File into, {bool interactive = true}) async {
    final address = Uri.parse('$_api/${Uri.encodeComponent(id)}');
    final about = await _send(
      'GET',
      address.replace(queryParameters: {'fields': 'size'}),
      interactive: interactive,
    );
    final size = _size(_answer(about));
    if (size == null || size < 0) {
      throw const DriveException(DriveProblem.refused, 'no size');
    }
    await into.parent.create(recursive: true);
    try {
      await _send(
        'GET',
        address.replace(queryParameters: {'alt': 'media'}),
        interactive: interactive,
        saveTo: into,
        saveLimit: size,
      );
    } on Object {
      if (into.existsSync()) await into.delete();
      rethrow;
    }
  }
}
