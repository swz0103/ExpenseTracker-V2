import 'dart:async';
import 'dart:io';

import 'package:expense_tracker/src/features/backup/model/drive_backup.dart';
import 'package:expense_tracker/src/features/backup/model/drive_sync.dart';
import 'package:expense_tracker/src/core/platform/preferences.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_drive.dart';

void main() {
  late Directory directory;
  late FakeDrive http;
  late List<String> tokens;
  late List<String> forgotten;
  var allowed = true;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('drive-');
    http = FakeDrive();
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

  test('a backup goes only to Google\'s own upload address (SEC-13)', () async {
    final client = drive();
    http.uploadAt = 'https://uploads.example.org';
    await expectLater(
      client.upload(backup('記帳本-1.etbk', 'one'), ledger: 'L1'),
      throwsA(
        isA<DriveException>().having(
          (e) => e.problem,
          'problem',
          DriveProblem.refused,
        ),
      ),
    );
    expect(
      http.sent.where((s) => s.url.host == 'uploads.example.org'),
      isEmpty,
    );
    expect(http.kept, isEmpty);
    expect(
      DriveBackup.isGoogleUpload(
        Uri.parse('https://www.googleapis.com/upload/drive/v3/files?x=1'),
      ),
      isTrue,
    );
    for (final other in [
      'http://www.googleapis.com/upload',
      'https://googleapis.com.example.org/upload',
      'https://evilgoogleapis.com/upload',
    ]) {
      expect(
        DriveBackup.isGoogleUpload(Uri.parse(other)),
        isFalse,
        reason: other,
      );
    }
  });

  test('linking learns which Google account it is (F90)', () async {
    final preferences = Preferences();
    final sync = DriveSync(
      drive(),
      preferences,
      withBackup: (use, {withPhotos = true}) =>
          use(backup('記帳本-1.etbk', 'one')),
      revision: () => 1,
      ledger: 'L1',
    );
    addTearDown(sync.dispose);
    expect(sync.account, isNull);
    await sync.link();
    expect(sync.account, 'me@example.com');
    await sync.unlink();
    expect(sync.account, isNull);
  });

  test('a backup sent through DriveSync is marked with the key epoch now, '
      'listed and moved to the trash by it (D15)', () async {
    var epoch = 1;
    final sync = DriveSync(
      drive(),
      Preferences(),
      withBackup: (use, {withPhotos = true}) =>
          use(backup('記帳本-1.etbk', 'one')),
      revision: () => 1,
      ledger: 'L1',
      epoch: () => epoch,
    );
    addTearDown(sync.dispose);
    await sync.backUpNow();
    epoch = 2;
    await sync.backUpNow();
    final listed = await sync.backups();
    expect([for (final f in listed) f.epoch], ['2', '1']);
    await sync.trash(listed.last.id);
    expect([for (final f in await sync.backups()) f.epoch], ['2']);
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

  test('every page of the folder is listed, not only the first', () async {
    final client = drive();
    await client.upload(backup('記帳本-0.etbk', '0'), ledger: 'L1');
    // 100 a page: 230 more makes 231, three pages (100 + 100 + 31).
    for (var i = 0; i < 230; i++) {
      http.seed('舊-$i.etbk', ledger: 'L1', epoch: 1);
    }
    expect(DriveBackup.pageSize, 100);
    // Only the listing below: the upload's own clean-up listed too.
    http.sent.clear();
    final listed = await client.list(ledger: 'L1');
    expect(listed, hasLength(231));
    expect({for (final f in listed) f.id}, hasLength(231));
    final asked = [
      for (final s in http.sent)
        if (s.method == 'GET' &&
            s.url.path == '/drive/v3/files' &&
            !s.url.queryParameters['q']!.contains('mimeType'))
          s.url.queryParameters['pageToken'],
    ];
    expect(asked, [null, '100', '200']);
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

  test('a daily backup goes up only when due and changed, '
      'with the photos only when asked', () async {
    var now = DateTime.utc(2026, 10, 1);
    var revision = 1;
    final sentPhotos = <bool>[];
    final preferences = Preferences(
      file: File('${directory.path}/preferences.json'),
    );
    var written = 0;
    final sync = DriveSync(
      drive(),
      preferences,
      withBackup: (use, {withPhotos = true}) async {
        sentPhotos.add(withPhotos);
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

    now = now.add(const Duration(days: 1));
    // Nothing changed since.
    expect(await sync.backUpIfDue(), isFalse);
    revision = 2;
    expect(await sync.backUpIfDue(), isTrue);
    expect(http.files, hasLength(2));
    // Too soon after.
    revision = 3;
    now = now.add(const Duration(hours: 12));
    expect(await sync.backUpIfDue(), isFalse);
    // The ledger alone until the photos are asked for, then sent at once.
    expect(sentPhotos, [false, false]);
    await sync.setPhotos(true);
    expect(sentPhotos, [false, false, true]);

    // Kept for the next start.
    final again = Preferences(file: File('${directory.path}/preferences.json'));
    expect(again.driveLinked, isTrue);
    expect(again.drivePhotos, isTrue);
    expect(again.driveRevision, 3);

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
        withBackup: (use, {withPhotos = true}) async {
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

  test('a backup with the photos waits for Wi-Fi; the ledger alone does '
      'not', () async {
    final preferences = Preferences(
      file: File('${directory.path}/preferences.json'),
    );
    var wifi = false;
    final sync = DriveSync(
      drive(),
      preferences,
      withBackup: (use, {withPhotos = true}) async {
        final file = backup('記帳本.etbk', 'x');
        try {
          await use(file);
        } finally {
          file.deleteSync();
        }
      },
      revision: () => 1,
      ledger: 'L1',
      unmetered: () async => wifi,
    );
    addTearDown(sync.dispose);
    preferences.update(driveLinked: true, drivePhotos: true);
    expect(await sync.backUpIfDue(), isFalse);
    expect(http.kept, isEmpty);
    wifi = true;
    expect(await sync.backUpIfDue(), isTrue);
    expect(http.kept, hasLength(1));
    // Without the photos, a day later and changed, on mobile data.
    wifi = false;
    preferences.update(drivePhotos: false);
    preferences.driveBackup(
      DateTime.now().subtract(const Duration(days: 2)),
      0,
    );
    expect(await sync.backUpIfDue(), isTrue);
  });

  testWidgets('a sign-in Google never answers gives up, and the next backup '
      'goes up', (tester) async {
    var answer = Completer<String?>();
    var asked = 0;
    final client = DriveBackup(
      http,
      token: ({required interactive}) {
        asked++;
        return answer.future;
      },
      forget: (token) async {},
    );
    final sync = DriveSync(
      client,
      Preferences(),
      withBackup: (use, {withPhotos = true}) => use(File('unused.etbk')),
      revision: () => 1,
      ledger: 'L1',
    );
    addTearDown(sync.dispose);
    final stages = <DriveStage?>[];
    sync.addListener(() => stages.add(sync.stage));

    Object? failed;
    final first = sync.backUpNow().catchError((Object e) => failed = e);
    await tester.pump();
    expect(sync.busy, isTrue);
    expect(stages, [DriveStage.packing, DriveStage.uploading]);
    // Google's screen closed without a word: nothing comes back.
    await tester.pump(DriveBackup.signInWait);
    await first;
    expect(
      failed,
      isA<DriveException>().having(
        (e) => e.problem,
        'problem',
        DriveProblem.noAnswer,
      ),
    );
    expect(sync.busy, isFalse, reason: 'the next backup is not held');
    expect(sync.stage, isNull);

    // The next one asks again, and goes up.
    answer = Completer()..complete('token');
    await tester.runAsync(() => sync.backUpNow().catchError((Object _) {}));
    expect(asked, 2);
  });
}
