import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:expense_tracker/src/book/drive_backup.dart';
import 'package:expense_tracker/src/book/drive_sync.dart';
import 'package:expense_tracker/src/preferences.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _Sent = ({String method, Uri url, Map<String, String> headers});

/// A file kept on the fake Drive.
final class _Row {
  _Row(this.name, this.bytes, this.at, this.ledger);

  final String name;
  final List<int> bytes;
  final DateTime at;
  final String? ledger;
  var trashed = false;
}

/// A Drive in memory: one folder and its files, answering as the REST API
/// does for the requests [DriveBackup] makes.
final class _FakeDrive implements DriveHttp {
  final sent = <_Sent>[];
  final files = <String, _Row>{};
  final revoked = <String>[];
  final _sessions = <String, String?>{};
  String? folder;
  var _next = 0;
  var _clock = DateTime.utc(2026, 10, 1);

  /// Answers 401 to this many requests first.
  var expired = 0;

  /// Moving files to the trash fails.
  var trashFails = false;

  /// Files that are not in the trash.
  Iterable<_Row> get kept => files.values.where((f) => !f.trashed);

  /// Puts a backup on Drive as another ledger or an older version did.
  void seed(String name, {String? ledger}) {
    _clock = _clock.add(const Duration(minutes: 1));
    files['s${_next++}'] = _Row(name, const [1], _clock, ledger);
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
      _sessions[id] =
          (body['appProperties'] as Map<String, Object?>?)?['ledger']
              as String?;
      return DriveResponse(
        200,
        headers: {
          'location':
              'https://www.googleapis.com/upload/session/$id?name='
              '${Uri.encodeComponent(body['name']! as String)}',
        },
      );
    }
    if (method == 'PUT' && path.startsWith('/upload/session/')) {
      final id = path.split('/').last;
      _clock = _clock.add(const Duration(minutes: 1));
      files[id] = _Row(
        url.queryParameters['name']!,
        await file!.readAsBytes(),
        _clock,
        _sessions[id],
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

void main() {
  late Directory directory;
  late _FakeDrive http;
  late List<String> tokens;
  late List<String> forgotten;
  var allowed = true;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('drive-');
    http = _FakeDrive();
    tokens = [];
    forgotten = [];
    allowed = true;
  });
  tearDown(() => directory.deleteSync(recursive: true));

  DriveBackup drive() => DriveBackup(
    http,
    token: ({required interactive}) async {
      if (!allowed) return null;
      final token = 'token${tokens.length}';
      tokens.add(token);
      return token;
    },
    forget: (token) async => forgotten.add(token),
  );

  File backup(String name, String text) =>
      File('${directory.path}/$name')..writeAsStringSync(text);

  test('a backup goes into its own folder and comes back', () async {
    final client = drive();
    await client.upload(backup('記帳本-1.etbk', 'one'), ledger: 'L1');
    expect(http.folder, 'folder');
    final listed = await client.list();
    expect([for (final f in listed) f.name], ['記帳本-1.etbk']);
    expect(listed.single.size, 3);

    final into = File('${directory.path}/restore.etbk');
    await client.download(listed.single.id, into);
    expect(into.readAsStringSync(), 'one');
    // One token for the whole run, sent with every request.
    expect(tokens, ['token0']);
    expect(
      http.sent.every((s) => s.headers['authorization'] == 'Bearer token0'),
      isTrue,
    );
  });

  test("only the newest five of this ledger's backups are kept", () async {
    final client = drive();
    // Another ledger's backups, and ones from before backups were marked,
    // share the folder.
    for (var i = 0; i < 6; i++) {
      http.seed('其他-$i.etbk', ledger: 'L2');
    }
    http.seed('舊版.etbk');
    for (var i = 0; i < 7; i++) {
      await client.upload(backup('記帳本-$i.etbk', '$i'), ledger: 'L1');
    }
    final mine = [for (final f in await client.list(ledger: 'L1')) f.name];
    expect(mine, [for (var i = 6; i >= 2; i--) '記帳本-$i.etbk']);
    expect(http.kept.where((f) => f.ledger == 'L2'), hasLength(6));
    expect(http.kept.where((f) => f.ledger == null), hasLength(1));
    // The two older ones wait in the Drive trash.
    expect(http.files.values.where((f) => f.trashed), hasLength(2));
    // A restore lists every backup in the folder.
    expect(await client.list(), hasLength(12));
  });

  test('a failed cleanup does not undo the upload', () async {
    final client = drive();
    http.trashFails = true;
    for (var i = 0; i < 7; i++) {
      await client.upload(backup('記帳本-$i.etbk', '$i'), ledger: 'L1');
    }
    expect(http.kept, hasLength(7));
  });

  test('a token Google refuses is forgotten and asked for again', () async {
    http.expired = 1;
    final client = drive();
    expect(await client.list(), isEmpty);
    expect(tokens, ['token0', 'token1']);
    expect(forgotten, ['token0']);

    // The same happens part way through an upload and a download.
    await client.upload(backup('記帳本.etbk', 'one'), ledger: 'L1');
    http.expired = 1;
    await client.upload(backup('記帳本-2.etbk', 'two'), ledger: 'L1');
    final newest = (await client.list()).first;
    http.expired = 1;
    final into = File('${directory.path}/restore.etbk');
    await client.download(newest.id, into);
    expect(into.readAsStringSync(), 'two');
    expect(tokens, ['token0', 'token1', 'token2', 'token3']);
  });

  test('without access nothing is sent', () async {
    allowed = false;
    final client = drive();
    expect(await client.signIn(), isFalse);
    await expectLater(
      client.list(),
      throwsA(
        isA<DriveException>().having(
          (e) => e.problem,
          'problem',
          DriveProblem.notAllowed,
        ),
      ),
    );
    expect(http.sent, isEmpty);
  });

  test('a weekly backup goes up only when due and changed', () async {
    var now = DateTime.utc(2026, 10, 1);
    var revision = 1;
    final preferences = Preferences(
      file: File('${directory.path}/preferences.json'),
    );
    var written = 0;
    final sync = DriveSync(
      drive(),
      preferences,
      withBackup: (use) async {
        final file = backup('記帳本-${written++}.etbk', 'x');
        try {
          await use(file);
        } finally {
          file.deleteSync();
        }
      },
      revision: () => revision,
      ledger: 'L1',
      clock: () => now,
    );
    addTearDown(sync.dispose);

    // Not linked: nothing.
    expect(await sync.backUpIfDue(), isFalse);
    expect(await sync.link(), isTrue);
    expect(http.files, hasLength(1));
    expect(sync.backedUp, now);

    now = now.add(const Duration(days: 8));
    // Nothing changed since.
    expect(await sync.backUpIfDue(), isFalse);
    revision = 2;
    expect(await sync.backUpIfDue(), isTrue);
    expect(http.files, hasLength(2));
    // Too soon after.
    revision = 3;
    expect(await sync.backUpIfDue(), isFalse);

    // Kept for the next start.
    final again = Preferences(file: File('${directory.path}/preferences.json'));
    expect(again.driveLinked, isTrue);
    expect(again.driveRevision, 2);

    await sync.unlink();
    expect(preferences.driveLinked, isFalse);
    // Google is asked to take the access back, so the next link asks for
    // an account again.
    expect(http.revoked, ['token0']);
    expect(forgotten, ['token0']);
    // The plain copies are gone.
    expect(
      directory.listSync().whereType<File>().where(
        (f) => f.path.endsWith('.etbk'),
      ),
      isEmpty,
    );
  });

  test(
    'a second ledger screen does not send a backup while one goes up',
    () async {
      final preferences = Preferences(
        file: File('${directory.path}/preferences.json'),
      );
      final hold = Completer<void>();
      DriveSync make() => DriveSync(
        drive(),
        preferences,
        withBackup: (use) async {
          await hold.future;
          final file = backup('記帳本.etbk', 'x');
          try {
            await use(file);
          } finally {
            file.deleteSync();
          }
        },
        revision: () => 1,
        ledger: 'L1',
      );
      final first = make();
      final second = make();
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      preferences.update(driveLinked: true);
      final going = first.backUpNow();
      expect(second.busy, isTrue);
      expect(await second.backUpIfDue(), isFalse);
      hold.complete();
      await going;
      expect(second.busy, isFalse);
      expect(http.kept, hasLength(1));
    },
  );
}
