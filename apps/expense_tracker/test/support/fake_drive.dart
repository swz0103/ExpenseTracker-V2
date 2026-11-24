import 'dart:convert';
import 'dart:io';

import 'package:expense_tracker/src/features/backup/model/drive_backup.dart';
import 'package:flutter_test/flutter_test.dart';

typedef DriveSent = ({String method, Uri url, Map<String, String> headers});

/// A file kept on the fake Drive.
final class DriveRow {
  DriveRow(this.name, this.bytes, this.at, this.ledger, {this.epoch});

  final String name;
  final List<int> bytes;
  final DateTime at;
  final String? ledger;

  /// The key epoch it went up marked with; null when unmarked.
  final String? epoch;
  var trashed = false;
}

/// A Drive in memory: one folder and its files, answering as the REST API
/// does for the requests [DriveBackup] makes.
final class FakeDrive implements DriveHttp {
  final sent = <DriveSent>[];
  final files = <String, DriveRow>{};
  final revoked = <String>[];
  final _sessions = <String, Map<String, Object?>?>{};
  String? folder;
  var _next = 0;
  var _clock = DateTime.utc(2026, 10, 1);

  /// Answers 401 to this many requests first.
  var expired = 0;

  /// Moving files to the trash fails.
  var trashFails = false;

  /// The Google account Drive says it is; null when it says none.
  String? account = 'me@example.com';

  /// Where Drive says to send a backup's bytes.
  var uploadAt = 'https://www.googleapis.com';

  /// Files that are not in the trash.
  Iterable<DriveRow> get kept => files.values.where((f) => !f.trashed);

  /// Puts a backup on Drive as another ledger or an older version did.
  void seed(String name, {String? ledger, int? epoch}) {
    _clock = _clock.add(const Duration(minutes: 1));
    files['s${_next++}'] = DriveRow(
      name,
      const [1],
      _clock,
      ledger,
      epoch: epoch == null ? null : '$epoch',
    );
  }

  @override
  Future<DriveResponse> send(
    String method,
    Uri url, {
    Map<String, String> headers = const {},
    String? text,
    File? file,
    File? saveTo,
  }) async {
    sent.add((method: method, url: url, headers: headers));
    if (url.host == 'oauth2.googleapis.com') {
      revoked.add(Uri.splitQueryString(text!)['token']!);
      return const DriveResponse(200);
    }
    if (expired > 0) {
      expired--;
      return const DriveResponse(401);
    }
    final path = url.path;
    if (method == 'GET' && path == '/drive/v3/about') {
      return _json({
        if (account case final address?) 'user': {'emailAddress': address},
      });
    }
    if (method == 'GET' && path == '/drive/v3/files') {
      final q = url.queryParameters['q']!;
      if (q.contains('mimeType')) {
        return _json({
          'files': [
            if (folder case final id?) {'id': id},
          ],
        });
      }
      final only = RegExp(r"value='([^']*)'").firstMatch(q)?.group(1);
      final rows = [
        for (final MapEntry(key: id, value: row) in files.entries)
          if (!row.trashed && (only == null || row.ledger == only))
            {
              'id': id,
              'name': row.name,
              'size': '${row.bytes.length}',
              'modifiedTime': row.at.toIso8601String(),
              if (row.epoch case final epoch?)
                'appProperties': {
                  'ledger': ?row.ledger,
                  DriveBackup.epochProperty: epoch,
                },
            },
      ];
      return _json({'files': rows});
    }
    if (method == 'POST' && path == '/drive/v3/files') {
      final body = jsonDecode(text!) as Map<String, Object?>;
      expect(body['name'], DriveBackup.folderName);
      folder = 'folder';
      return _json({'id': 'folder'});
    }
    if (method == 'POST' && path == '/upload/drive/v3/files') {
      final body = jsonDecode(text!) as Map<String, Object?>;
      expect(body['parents'], [folder]);
      final id = 'f${_next++}';
      _sessions[id] = body['appProperties'] as Map<String, Object?>?;
      return DriveResponse(
        200,
        headers: {
          'location':
              '$uploadAt/upload/session/$id?name='
              '${Uri.encodeComponent(body['name']! as String)}',
        },
      );
    }
    if (method == 'PUT' && path.startsWith('/upload/session/')) {
      final id = path.split('/').last;
      _clock = _clock.add(const Duration(minutes: 1));
      files[id] = DriveRow(
        url.queryParameters['name']!,
        await file!.readAsBytes(),
        _clock,
        _sessions[id]?['ledger'] as String?,
        epoch: _sessions[id]?[DriveBackup.epochProperty] as String?,
      );
      return _json({'id': id});
    }
    if (method == 'PATCH') {
      if (trashFails) return const DriveResponse(500);
      final row = files[path.split('/').last];
      if (row == null) return const DriveResponse(404);
      expect(jsonDecode(text!), {'trashed': true});
      row.trashed = true;
      return _json({'id': path.split('/').last});
    }
    if (method == 'DELETE') {
      fail('Backups go to the trash; nothing is deleted for good.');
    }
    if (method == 'GET' && url.queryParameters['alt'] == 'media') {
      final found = files[path.split('/').last];
      if (found == null) return const DriveResponse(404);
      await saveTo!.writeAsBytes(found.bytes);
      return const DriveResponse(200);
    }
    return const DriveResponse(400);
  }

  DriveResponse _json(Object body) =>
      DriveResponse(200, body: jsonEncode(body));
}
