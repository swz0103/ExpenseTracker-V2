import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:drive_backup/drive_backup.dart';
import 'package:drive_backup/testing.dart';
import 'package:storage_sqlcipher/storage_sqlcipher.dart';
import 'package:test/test.dart';

const principal = 'google-account-1';
final t0 = DateTime.utc(2026, 10, 3, 9);

void main() {
  late Directory directory;
  late SqlCipherStore store;
  late CloudUploadQueue queue;
  late FakeDrive drive;
  late FakeTokens tokens;
  late DriveClient client;
  var backups = 0;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('drive-backup-');
    store = SqlCipherStore.open(
      File('${directory.path}/app.db'),
      StorageKey.random(),
      modules: [cloudSchema],
    );
    queue = CloudUploadQueue(store, chunkSize: CloudUploadQueue.quantum);
    drive = FakeDrive();
    tokens = FakeTokens();
    client = DriveClient(transport: drive, tokens: tokens);
  });

  tearDown(() {
    store.close();
    directory.deleteSync(recursive: true);
  });

  /// A backup file of about 1.1 MiB: five chunks of 256 KiB.
  File backupFile({int length = 1150000}) {
    final random = Random(backups);
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = random.nextInt(256);
    }
    return File('${directory.path}/backup-${backups++}.etb')
      ..writeAsBytesSync(bytes);
  }

  Future<CloudUpload> enqueue(File file, {DateTime? at}) => queue.enqueue(
    backupId: 'backup-$backups',
    principal: principal,
    file: file,
    createdAt: at ?? t0,
    now: at ?? t0,
  );

  Future<UploadRun> run({DateTime? now}) =>
      queue.runNext(drive: client, principal: principal, now: now ?? t0);

  test('a backup uploads in chunks and its local copy is deleted', () async {
    final file = backupFile();
    final bytes = file.readAsBytesSync();
    final upload = await enqueue(file);

    final outcome = await run();
    expect(outcome.result, UploadResult.uploaded);
    expect(drive.requests.where(isChunk), hasLength(5));
    final stored = queue.get(upload.backupId)!;
    expect(stored.state, UploadState.uploaded);
    expect(stored.sessionUri, isNull);
    expect(drive.files[stored.driveFileId]!.bytes, bytes);
    expect(file.existsSync(), isFalse);
    expect(queue.lastUploaded(principal), t0);
    expect((await run()).result, UploadResult.idle);
  });

  test('a lost reply resumes from what Drive holds, not from zero', () async {
    final file = backupFile();
    final length = file.lengthSync();
    await enqueue(file);
    var chunks = 0;
    drive.faults.add(
      Fault(FaultKind.dropAfter, (r) => isChunk(r) && ++chunks == 3),
    );

    expect((await run()).result, UploadResult.uploaded);
    expect(drive.sessionsStarted, 1);
    expect(drive.uploadedBytes, length);
  });

  test('an upload cut off by an outage continues after restart', () async {
    final file = backupFile();
    final length = file.lengthSync();
    final upload = await enqueue(file);
    var chunks = 0;
    drive.faults.add(
      Fault(
        FaultKind.dropBefore,
        (r) => r.method == 'PUT' && ++chunks > 2,
        times: 1000,
      ),
    );

    final first = await run();
    expect(first.result, UploadResult.retryLater);
    expect(first.retryAt, t0.add(const Duration(minutes: 1)));
    expect(queue.get(upload.backupId)!.sessionUri, isNotNull);
    expect((await run()).result, UploadResult.idle);

    drive
      ..faults.clear()
      ..requests.clear();
    final reopened = CloudUploadQueue(
      store,
      chunkSize: CloudUploadQueue.quantum,
    );
    final later = t0.add(const Duration(minutes: 2));
    final second = await reopened.runNext(
      drive: client,
      principal: principal,
      now: later,
    );
    expect(second.result, UploadResult.uploaded);
    expect(drive.sessionsStarted, 1);
    final sent = drive.requests.where(isChunk).map((r) => r.body.length);
    final resumed = length - 2 * CloudUploadQueue.quantum;
    expect(sent.fold(0, (a, b) => a + b), resumed);
  });

  test('an expired session restarts, or finds the finished file', () async {
    await enqueue(backupFile());
    drive.faults.add(Fault(FaultKind.dropBefore, isChunk, times: 1000));
    expect((await run()).result, UploadResult.retryLater);
    drive
      ..faults.clear()
      ..expireSessions();
    final later = t0.add(const Duration(hours: 1));
    expect((await run(now: later)).result, UploadResult.uploaded);
    expect(drive.sessionsStarted, 2);

    // A reply lost on the last chunk, then the session expires: the
    // reserved file id shows the upload had finished.
    final other = await enqueue(backupFile(), at: later);
    var chunks = 0;
    drive.faults.add(
      Fault(FaultKind.dropAfter, (r) => isChunk(r) && ++chunks == 5),
    );
    drive.faults.add(
      Fault(FaultKind.dropBefore, (r) => chunks >= 5 && !isChunk(r)),
    );
    expect((await run(now: later)).result, UploadResult.retryLater);
    drive
      ..faults.clear()
      ..expireSessions();
    final last = later.add(const Duration(hours: 1));
    expect((await run(now: last)).result, UploadResult.uploaded);
    expect(drive.sessionsStarted, 3);
    expect(queue.get(other.backupId)!.state, UploadState.uploaded);
  });

  test('a refused token is refreshed once; twice asks to sign in', () async {
    await enqueue(backupFile());
    drive.validTokens = {'token-2'};
    expect((await run()).result, UploadResult.uploaded);
    expect(tokens.issued, 2);

    final upload = await enqueue(backupFile());
    drive.validTokens = {};
    final outcome = await run();
    expect(outcome.result, UploadResult.signInRequired);
    final stored = queue.get(upload.backupId)!;
    expect(stored.state, UploadState.queued);
    expect(stored.attempts, 0);

    tokens.signedOut = true;
    expect((await run()).result, UploadResult.signInRequired);
  });

  test('a damaged local file fails alone and never blocks', () async {
    final file = backupFile();
    final bad = await enqueue(file);
    file.writeAsBytesSync([1, 2, 3], mode: FileMode.append);
    final outcome = await run();
    expect(outcome.result, UploadResult.failed);
    expect(outcome.failure, 'local-artifact');
    expect(queue.get(bad.backupId)!.state, UploadState.failed);

    final next = await enqueue(backupFile());
    expect((await run()).result, UploadResult.uploaded);
    expect(queue.get(next.backupId)!.state, UploadState.uploaded);
  });

  test('quota errors fail until the user retries', () async {
    final upload = await enqueue(backupFile());
    drive.faults.add(
      Fault(FaultKind.status, (r) => r.method == 'POST', status: 403),
    );
    final outcome = await run();
    expect(outcome.result, UploadResult.failed);
    expect(outcome.failure, 'permissionDenied');
    expect((await run()).result, UploadResult.idle);

    await queue.retry(upload.backupId, t0);
    expect((await run()).result, UploadResult.uploaded);
  });

  test('retries back off and give up after the attempt budget', () async {
    queue = CloudUploadQueue(
      store,
      chunkSize: CloudUploadQueue.quantum,
      maxAttempts: 3,
    );
    final upload = await enqueue(backupFile());
    drive.faults.add(
      Fault(FaultKind.status, (r) => true, status: 503, times: 1000),
    );
    var now = t0;
    final waits = <Duration>[];
    for (var i = 0; i < 2; i++) {
      final outcome = await run(now: now);
      expect(outcome.result, UploadResult.retryLater);
      waits.add(outcome.retryAt!.difference(now));
      expect((await run(now: now)).result, UploadResult.idle);
      now = outcome.retryAt!;
    }
    expect(waits, [const Duration(minutes: 1), const Duration(minutes: 2)]);
    final last = await run(now: now);
    expect(last.result, UploadResult.failed);
    expect(queue.get(upload.backupId)!.failure, 'unavailable');
  });

  test('a newer backup replaces older ones that have not started', () async {
    final first = backupFile();
    final older = await enqueue(first);
    final newer = await enqueue(
      backupFile(),
      at: t0.add(const Duration(days: 1)),
    );
    expect(queue.get(older.backupId)!.state, UploadState.abandoned);
    expect(first.existsSync(), isFalse);
    expect(
      queue.uploads(state: UploadState.queued).single.backupId,
      newer.backupId,
    );
  });

  test('abandon deletes the file and frees the queue', () async {
    final file = backupFile();
    final upload = await enqueue(file);
    drive.faults.add(Fault(FaultKind.dropBefore, isChunk, times: 1000));
    expect((await run()).result, UploadResult.retryLater);
    await queue.abandon(upload.backupId, t0);
    expect(queue.get(upload.backupId)!.state, UploadState.abandoned);
    expect(file.existsSync(), isFalse);
    final later = t0.add(const Duration(hours: 1));
    expect((await run(now: later)).result, UploadResult.idle);
  });

  test('sweep removes local copies left by a crash', () async {
    final file = backupFile();
    final bytes = file.readAsBytesSync();
    await enqueue(file);
    expect((await run()).result, UploadResult.uploaded);
    file.writeAsBytesSync(bytes);
    expect(await queue.sweep(), 1);
    expect(file.existsSync(), isFalse);
    expect(await queue.sweep(), 0);
  });

  test('the listing skips bad entries and lists newest first', () async {
    for (final day in [1, 3, 2]) {
      final at = DateTime.utc(2026, 10, day);
      await enqueue(backupFile(), at: at);
      expect((await run(now: at)).result, UploadResult.uploaded);
    }
    drive.extraRows.addAll([
      'not an object',
      {'id': 'x', 'name': 'x', 'size': 'big'},
      {
        'id': 'y',
        'name': 'y',
        'size': '3',
        'appProperties': {'format': driveBackupFormat, 'backupId': 'y'},
      },
    ]);
    final listing = await client.listBackups();
    expect(listing.skipped, 3);
    expect([for (final f in listing.files) f.createdAt!.day], [3, 2, 1]);

    await client.trash(listing.files.first.id);
    expect((await client.listBackups()).files, hasLength(2));
    final newest = listing.files[1];
    expect(await client.download(newest.id), drive.files[newest.id]!.bytes);
  });

  test('prune keeps the newest backups by local time only', () async {
    final ids = <String>[];
    for (final day in [1, 2, 3, 4]) {
      final at = DateTime.utc(2026, 10, day);
      final upload = await enqueue(backupFile(), at: at);
      expect((await run(now: at)).result, UploadResult.uploaded);
      ids.add(queue.get(upload.backupId)!.driveFileId!);
    }
    // Edited Drive properties do not change which ones are kept.
    drive.files[ids[0]]!.properties['createdAt'] = '2030-01-01T00:00:00Z';
    drive.files['elsewhere'] = FakeFile(
      'elsewhere',
      'other',
      {
        'format': driveBackupFormat,
        'backupId': 'other',
        'createdAt': '2020-01-01T00:00:00Z',
      },
      [1],
      '0' * 64,
    );

    final now = DateTime.utc(2026, 10, 5);
    final removed = await queue.prune(
      drive: client,
      principal: principal,
      keep: 2,
      now: now,
    );
    expect(removed, 2);
    final trashed = [for (final id in ids) drive.files[id]!.trashed];
    expect(trashed, [true, true, false, false]);
    expect(drive.files['elsewhere']!.trashed, isFalse);
    expect(queue.uploads(state: UploadState.removed), hasLength(2));
    final again = await queue.prune(
      drive: client,
      principal: principal,
      keep: 2,
      now: now,
    );
    expect(again, 0);
  });

  test('only Google upload hosts may receive the token', () {
    bool trusted(String uri) => DriveClient.trustedSession(Uri.parse(uri));
    expect(trusted('https://www.googleapis.com/upload/drive/v3/files'), isTrue);
    expect(trusted('http://www.googleapis.com/upload'), isFalse);
    expect(trusted('https://googleapis.com.evil.example/upload'), isFalse);
    expect(trusted('https://user@www.googleapis.com/upload'), isFalse);
  });
}
