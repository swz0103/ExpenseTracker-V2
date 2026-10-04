import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:backup_security/backup_security.dart';
import 'package:backup_service/backup_service.dart';
import 'package:bookkeeping/bookkeeping.dart';
import 'package:drive_backup/drive_backup.dart';
import 'package:drive_backup/testing.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger_backup/ledger_backup.dart';
import 'package:ledger_sqlcipher/ledger_sqlcipher.dart';
import 'package:storage_sqlcipher/storage_sqlcipher.dart';
import 'package:test/test.dart';

const password = 'correct horse battery';
const principal = 'google-account-1';
const day = Duration(days: 1);
final twd = Currency.of('TWD');
final codec = KeyringCodec(kdf: PasswordKdf.insecureForTests);

void main() {
  late Directory directory;
  late SqlCipherStore store;
  late Bookkeeping<SqlBookkeeping> books;
  late BackupService service;
  late FakeDrive drive;
  late DriveClient client;
  late CreatedKeyring keys;
  final workspace = WorkspaceId(PublicId.generate());
  final t0 = DateTime.utc(2026, 10, 3, 9);
  var stores = 0;

  SqlCipherStore open() => SqlCipherStore.open(
    File('${directory.path}/store-${stores++}.db'),
    StorageKey.random(),
    modules: [ledgerSchema, cloudSchema],
  );

  setUpAll(() async {
    keys = await codec.create(password);
  });

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('backup-service-');
    store = open();
    final ledger = LedgerStore(store);
    books = Bookkeeping(ledger);
    service = BackupService(
      ledger: ledger,
      queue: CloudUploadQueue(store, exclusive: books.exclusive),
      staging: Directory('${directory.path}/staging'),
      exclusive: books.exclusive,
    );
    drive = FakeDrive();
    client = DriveClient(transport: drive, tokens: FakeTokens());
    await books.openAccount(
      OpenAccount(
        operation: OperationKey(workspace, OperationId(PublicId.generate())),
        accountId: PublicId.generate(),
        name: '現金',
        kind: AccountKind.cash,
        currency: twd,
        openedOn: BusinessDate(2026, 10, 1),
        openingBalance: Money(twd, BigInt.from(5000)),
        openingPostingId: PublicId.generate(),
      ),
    );
  });

  tearDown(() {
    store.close();
    directory.deleteSync(recursive: true);
  });

  /// Restores straight into [target], as a test stand-in for the vault.
  RestoreTarget<SqlCipherStore> into(SqlCipherStore target) {
    return (keys, fill) async {
      await fill(LedgerStore(target));
      return target;
    };
  }

  Future<CloudUpload> backup(DateTime now) =>
      service.backupNow(keys: keys.unlocked, principal: principal, now: now);

  Future<SyncReport> sync(DateTime now, {int keep = 2}) => service.sync(
    drive: client,
    principal: principal,
    now: now,
    retention: Retention.newest(keep),
  );

  test('backups are due on schedule, upload and keep the newest', () async {
    expect(service.due(principal: principal, every: day, now: t0), isTrue);
    var now = t0;
    for (var i = 0; i < 3; i++) {
      await backup(now);
      expect(service.due(principal: principal, every: day, now: now), isFalse);
      final report = await sync(now);
      expect(report.uploaded, 1);
      expect(report.last.result, UploadResult.idle);
      now = now.add(day);
    }
    // Nothing changed since the last backup, so none is due.
    expect(service.due(principal: principal, every: day, now: now), isFalse);
    await books.openAccount(
      OpenAccount(
        operation: OperationKey(workspace, OperationId(PublicId.generate())),
        accountId: PublicId.generate(),
        name: '新帳戶',
        kind: AccountKind.bank,
        currency: twd,
        openedOn: BusinessDate(2026, 10, 1),
      ),
    );
    expect(service.due(principal: principal, every: day, now: now), isTrue);
    expect(drive.files.values.where((f) => !f.trashed), hasLength(2));
    expect(service.staging.listSync(), isEmpty);

    final health = service.health(principal: principal, every: day, now: now);
    expect(health.lastUploaded, t0.add(day * 2));
    expect(health.overdue, isFalse);
    expect(health.pending, 0);
    final stale = service.health(
      principal: principal,
      every: day,
      now: now.add(day * 3),
    );
    expect(stale.overdue, isTrue);
  });

  test('a backup on Drive restores into a new ledger', () async {
    await backup(t0);
    await sync(t0);
    final listing = await client.listBackups();
    final target = open();
    addTearDown(target.close);

    final (_, header) = await service.restore(
      drive: client,
      file: listing.files.single,
      unlock: (keyring) => codec.unlockWithPassword(keyring, password),
      into: into(target),
    );
    expect(header.events, store.eventCount);
    expect(projectionRows(target), projectionRows(store));
    expect(service.staging.listSync(), isEmpty);
  });

  test('a Drive file swapped for another backup is refused', () async {
    await backup(t0);
    await sync(t0, keep: 5);
    await backup(t0.add(day));
    await sync(t0.add(day), keep: 5);
    final listing = await client.listBackups();
    expect(listing.files, hasLength(2));
    final newest = drive.files[listing.files.first.id]!;
    final oldest = drive.files[listing.files.last.id]!;
    drive.files[newest.id] = FakeFile(
      newest.id,
      newest.name,
      newest.properties,
      oldest.bytes,
      oldest.sha256,
    );
    // Drive's own size and checksum describe the swapped content, so only
    // the backup id can tell.
    final swapped = (await client.file(newest.id))!;
    final target = open();
    addTearDown(target.close);

    await expectLater(
      service.restore(
        drive: client,
        file: swapped,
        unlock: (keyring) => codec.unlockWithPassword(keyring, password),
        into: into(target),
      ),
      throwsA(
        isA<BackupException>().having(
          (e) => e.problem,
          'problem',
          BackupProblem.authenticationFailed,
        ),
      ),
    );
    expect(target.eventCount, 0);
  });

  test('a failing upload keeps older copies on Drive', () async {
    var now = t0;
    for (var i = 0; i < 2; i++) {
      await backup(now);
      await sync(now, keep: 5);
      now = now.add(day);
    }
    expect(drive.files.values.where((f) => !f.trashed), hasLength(2));
    drive.faults.add(
      Fault(FaultKind.status, (r) => r.method == 'POST', status: 503),
    );
    await backup(now);
    // Keeping 1 would trash an older copy, but not while an upload fails.
    final report = await sync(now, keep: 1);
    expect(report.last.result, UploadResult.retryLater);
    expect(report.removed, 0);
    expect(drive.files.values.where((f) => !f.trashed), hasLength(2));
    final health = service.health(principal: principal, every: day, now: now);
    expect(health.pending, 1);
  });

  test('a failed restore leaves no plain copy behind', () async {
    await backup(t0);
    await sync(t0);
    final listing = await client.listBackups();
    final target = open();
    addTearDown(target.close);
    await expectLater(
      service.restore(
        drive: client,
        file: listing.files.single,
        unlock: (keyring) => codec.unlockWithPassword(keyring, 'wrong one!'),
        into: into(target),
      ),
      throwsA(const KeyringException(KeyringError.wrongSecret)),
    );
    expect(service.staging.listSync(), isEmpty);
    expect(target.eventCount, 0);
  });

  test('due and health count only this account and live uploads', () async {
    await service.backupNow(keys: keys.unlocked, principal: 'other', now: t0);
    expect(service.due(principal: principal, every: day, now: t0), isTrue);
    drive.faults.add(
      Fault(FaultKind.status, (r) => r.method == 'POST', status: 403),
    );
    await backup(t0);
    await sync(t0);
    final health = service.health(principal: principal, every: day, now: t0);
    expect(health.failed, 1);
    expect(health.pending, 0);
    expect(health.overdue, isTrue);
    // A failed upload does not count as a backup taken.
    expect(service.due(principal: principal, every: day, now: t0), isTrue);
  });

  test('a scheduled pass reports problems until a pass succeeds', () async {
    Future<ScheduledPass> pass(DateTime now) => service.runScheduled(
      keys: keys.unlocked,
      principal: principal,
      every: day,
      now: now,
      drive: client,
    );
    drive.faults.add(
      Fault(FaultKind.status, (r) => r.method == 'POST', status: 503),
    );
    final first = await pass(t0);
    expect(first.backup, isNotNull);
    expect(first.problem, 'upload retryLater');
    // Before the retry time nothing runs, and the problem still shows.
    final waiting = await pass(t0.add(const Duration(seconds: 1)));
    expect(waiting.backup, isNull);
    expect(waiting.problem, 'upload retryLater');
    var health = service.health(principal: principal, every: day, now: t0);
    expect(health.problem, 'upload retryLater');
    // The timer's next pass uploads the waiting backup; nothing changed in
    // the ledger, so no new backup is written.
    final later = await pass(t0.add(const Duration(hours: 1)));
    expect(later.backup, isNull);
    expect(later.sync!.uploaded, 1);
    expect(later.problem, isNull);
    health = service.health(principal: principal, every: day, now: t0);
    expect(health.problem, isNull);
    expect(drive.files, hasLength(1));
  });

  test('a scheduled pass never throws and overlapping passes skip', () async {
    final staging = File(service.staging.path)..createSync(recursive: true);
    final failing = await service.runScheduled(
      keys: keys.unlocked,
      principal: principal,
      every: day,
      now: t0,
    );
    expect(failing.problem, startsWith('backup failed'));
    staging.deleteSync();
    final passes = await Future.wait([
      for (var i = 0; i < 2; i++)
        service.runScheduled(
          keys: keys.unlocked,
          principal: principal,
          every: day,
          now: t0,
        ),
    ]);
    expect(passes.where((p) => p.problem == 'busy'), hasLength(1));
    expect(passes.where((p) => p.backup != null), hasLength(1));
    final health = service.health(principal: principal, every: day, now: t0);
    expect(health.problem, isNull);
  });

  test('Drive keeps daily, weekly and monthly copies', () {
    final days = [
      for (var i = 0; i < 120; i++) DateTime.utc(2026, 10, 1).subtract(day * i),
    ];
    final kept = const Retention(daily: 3, weekly: 2, monthly: 3).keep(days);
    final dates = [for (final i in kept.toList()..sort()) days[i]];
    // The three newest, the newest of last week, and the newest of each
    // of the two months before.
    expect(dates, [
      DateTime.utc(2026, 10, 1),
      DateTime.utc(2026, 9, 30),
      DateTime.utc(2026, 9, 29),
      DateTime.utc(2026, 9, 27),
      DateTime.utc(2026, 8, 31),
    ]);
  });

  test('a backup file on this device restores without Drive', () async {
    final upload = await backup(t0);
    final copy = File('${directory.path}/copied.etb');
    upload.file.copySync(copy.path);
    final target = open();
    addTearDown(target.close);
    final (_, header) = await service.restoreFile(
      file: copy,
      unlock: (keyring) => codec.unlockWithPassword(keyring, password),
      into: into(target),
    );
    expect(header.backupId.value, upload.backupId);
    expect(projectionRows(target), projectionRows(store));
  });
}
