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

  Future<CloudUpload> backup(DateTime now) =>
      service.backupNow(keys: keys.unlocked, principal: principal, now: now);

  Future<SyncReport> sync(DateTime now, {int keep = 2}) =>
      service.sync(drive: client, principal: principal, keep: keep, now: now);

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

    final header = await service.restore(
      drive: client,
      file: listing.files.single,
      unlock: (keyring) => codec.unlockWithPassword(keyring, password),
      into: LedgerStore(target),
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
    final target = open();
    addTearDown(target.close);

    await expectLater(
      service.restore(
        drive: client,
        file: listing.files.first,
        unlock: (keyring) => codec.unlockWithPassword(keyring, password),
        into: LedgerStore(target),
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
      await sync(now, keep: 1);
      now = now.add(day);
    }
    expect(drive.files.values.where((f) => !f.trashed), hasLength(1));
    drive.faults.add(
      Fault(FaultKind.status, (r) => r.method == 'POST', status: 503),
    );
    await backup(now);
    final report = await sync(now, keep: 1);
    expect(report.last.result, UploadResult.retryLater);
    expect(report.removed, 0);
    expect(drive.files.values.where((f) => !f.trashed), hasLength(1));
    final health = service.health(principal: principal, every: day, now: now);
    expect(health.pending, 1);
  });
}
