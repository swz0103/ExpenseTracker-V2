import 'dart:io';

import 'package:encrypted_storage_probe/encrypted_database.dart';
import 'package:persistent_jobs_probe/persistent_jobs.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  late File file;
  late StorageKey key;
  late PersistentJobStore store;
  final start = DateTime.utc(2026, 9, 29);

  setUp(() {
    root = Directory.systemTemp.createTempSync('jobs-');
    file = File('${root.path}/queue.db');
    key = StorageKey.random();
    store = PersistentJobStore.open(file, key);
  });

  tearDown(() {
    store.close();
    root.deleteSync(recursive: true);
  });

  test('encrypted store reopens and idempotency survives restart', () {
    final first = store.enqueue(
      idempotencyKey: 'backup:snapshot-1',
      kind: 'backup.upload.v1',
      now: start,
    );
    store.close();
    expect(
      () => PersistentJobStore.open(file, StorageKey.random()),
      throwsA(isA<EncryptedStorageUnavailable>()),
    );
    store = PersistentJobStore.open(file, key);
    final duplicate = store.enqueue(
      idempotencyKey: 'backup:snapshot-1',
      kind: 'backup.upload.v1',
      now: start.add(const Duration(days: 1)),
    );
    expect(duplicate.id, first.id);
    expect(
      () => store.enqueue(
        idempotencyKey: 'backup:snapshot-1',
        kind: 'other.v1',
        now: start,
      ),
      throwsStateError,
    );
    expect(
      file.readAsBytesSync().take(16),
      isNot('SQLite format 3\u0000'.codeUnits),
    );
  });

  test('retry backoff, stale lease, and terminal failure survive restart', () {
    store.enqueue(
      idempotencyKey: 'backup:snapshot-2',
      kind: 'backup.upload.v1',
      now: start,
      maxAttempts: 3,
    );
    final first = store.claim(
      kind: 'backup.upload.v1',
      now: start,
      lease: const Duration(minutes: 1),
    )!;
    expect(first.job.attempts, 1);
    expect(store.fail(first, start), isTrue);
    expect(
      store.claim(
        kind: 'backup.upload.v1',
        now: start,
        lease: const Duration(minutes: 1),
      ),
      isNull,
    );
    final second = store.claim(
      kind: 'backup.upload.v1',
      now: start.add(const Duration(seconds: 30)),
      lease: const Duration(minutes: 1),
    )!;
    store.close();
    store = PersistentJobStore.open(file, key);
    expect(
      store
          .claim(
            kind: 'backup.upload.v1',
            now: start.add(const Duration(seconds: 90)),
            lease: const Duration(minutes: 1),
          )!
          .job
          .attempts,
      3,
    );
    expect(
      store.succeed(second, start.add(const Duration(seconds: 91))),
      isFalse,
    );
    expect(
      store.claim(
        kind: 'backup.upload.v1',
        now: start.add(const Duration(seconds: 151)),
        lease: const Duration(minutes: 1),
      ),
      isNull,
    );
    expect(store.byKey('backup:snapshot-2')!.state, JobState.terminalFailure);
    expect(
      store.retryTerminal(
        'backup:snapshot-2',
        start.add(const Duration(seconds: 152)),
      ),
      isTrue,
    );
    expect(
      store
          .claim(
            kind: 'backup.upload.v1',
            now: start.add(const Duration(seconds: 152)),
            lease: const Duration(minutes: 1),
          )!
          .job
          .id,
      second.job.id,
    );
  });

  test('successful lease is acknowledged once and never re-enqueued', () {
    final job = store.enqueue(
      idempotencyKey: 'backup:snapshot-3',
      kind: 'backup.upload.v1',
      now: start,
    );
    expect(
      store.claim(
        kind: 'other.v1',
        now: start,
        lease: const Duration(minutes: 1),
      ),
      isNull,
    );
    final lease = store.claim(
      kind: 'backup.upload.v1',
      now: start,
      lease: const Duration(minutes: 1),
    )!;
    expect(store.succeed(lease, start), isTrue);
    expect(store.succeed(lease, start), isFalse);
    expect(
      store.claim(
        kind: 'backup.upload.v1',
        now: start.add(const Duration(days: 1)),
        lease: const Duration(minutes: 1),
      ),
      isNull,
    );
    expect(
      store
          .enqueue(
            idempotencyKey: job.idempotencyKey,
            kind: job.kind,
            now: start,
          )
          .id,
      job.id,
    );
    expect(store.byKey(job.idempotencyKey)!.state, JobState.succeeded);
  });

  test('retry waits grow and a failed last attempt needs manual action', () {
    store.enqueue(
      idempotencyKey: 'backup:snapshot-4',
      kind: 'backup.upload.v1',
      now: start,
      maxAttempts: 3,
    );
    final first = store.claim(
      kind: 'backup.upload.v1',
      now: start,
      lease: const Duration(minutes: 1),
    )!;
    expect(store.fail(first, start), isTrue);
    final secondTime = start.add(const Duration(seconds: 30));
    final second = store.claim(
      kind: 'backup.upload.v1',
      now: secondTime,
      lease: const Duration(minutes: 1),
    )!;
    expect(store.fail(second, secondTime), isTrue);
    expect(
      store.claim(
        kind: 'backup.upload.v1',
        now: secondTime.add(const Duration(seconds: 59)),
        lease: const Duration(minutes: 1),
      ),
      isNull,
    );
    final thirdTime = secondTime.add(const Duration(seconds: 60));
    final third = store.claim(
      kind: 'backup.upload.v1',
      now: thirdTime,
      lease: const Duration(minutes: 1),
    )!;
    expect(store.fail(third, thirdTime), isTrue);
    expect(store.byKey('backup:snapshot-4')!.state, JobState.terminalFailure);
    expect(store.retryTerminal('backup:snapshot-4', thirdTime), isTrue);
    expect(store.retryTerminal('backup:snapshot-4', thirdTime), isFalse);
  });
}
