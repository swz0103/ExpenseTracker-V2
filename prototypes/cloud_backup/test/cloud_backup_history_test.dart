import 'package:cloud_backup_probe/cloud_backup.dart';
import 'package:cloud_backup_probe/cloud_backup_history.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 10, 1, 12);

  test('registry selects multiple providers without a hard-coded default', () {
    final first = _CatalogProvider('provider-a', []);
    final second = _CatalogProvider('provider-b', []);
    final registry = CloudBackupProviderRegistry([first, second]);
    expect(registry.providerIds, ['provider-a', 'provider-b']);
    expect(registry.provider('provider-b'), same(second));
    expect(registry.catalog('provider-a'), same(first));
    expect(() => CloudBackupProviderRegistry([first, first]), throwsStateError);
  });

  test('history is stable and retention requires explicit apply', () async {
    final provider = _CatalogProvider('provider-a', [
      _item('oldest', now.subtract(const Duration(days: 10))),
      _item('newest', now.subtract(const Duration(hours: 1))),
      _item('middle', now.subtract(const Duration(days: 4))),
      _item('recent', now.subtract(const Duration(hours: 12))),
    ]);
    final service = CloudBackupRetentionService(provider);
    final plan = await service.preview(
      const CloudBackupRetentionPolicy(
        keepLatest: 2,
        minimumAge: Duration(days: 2),
      ),
      now: now,
    );
    expect(plan.keep.map((item) => item.objectId), ['newest', 'recent']);
    expect(plan.delete.map((item) => item.objectId), ['middle', 'oldest']);
    expect(provider.deleted, isEmpty);

    await service.apply(plan);
    expect(provider.deleted, ['middle', 'oldest']);
    expect((await service.history()).map((item) => item.objectId), [
      'newest',
      'recent',
    ]);
  });

  test(
    'changed remote metadata aborts retention before any deletion',
    () async {
      final provider = _CatalogProvider('provider-a', [
        _item('newest', now),
        _item('oldest', now.subtract(const Duration(days: 10))),
      ]);
      final service = CloudBackupRetentionService(provider);
      final plan = await service.preview(
        const CloudBackupRetentionPolicy(keepLatest: 1),
        now: now,
      );
      provider.items[1] = _item(
        'oldest',
        now.subtract(const Duration(days: 10)),
        sha256: 'b' * 64,
      );
      await expectLater(
        service.apply(plan),
        throwsA(isA<CloudBackupValidationException>()),
      );
      expect(provider.deleted, isEmpty);
    },
  );

  test('invalid policies and malformed provider history fail closed', () async {
    final provider = _CatalogProvider('provider-a', [
      _item('bad', now, sha256: 'not-a-digest'),
    ]);
    final service = CloudBackupRetentionService(provider);
    await expectLater(
      service.history(),
      throwsA(isA<CloudBackupValidationException>()),
    );
    await expectLater(
      service.preview(
        const CloudBackupRetentionPolicy(keepLatest: 0),
        now: now,
      ),
      throwsArgumentError,
    );
  });
}

RemoteBackupMetadata _item(String id, DateTime createdAt, {String? sha256}) =>
    RemoteBackupMetadata(
      providerId: 'provider-a',
      objectId: id,
      backupId: 'backup-$id',
      sha256: sha256 ?? 'a' * 64,
      byteLength: 100,
      createdAt: createdAt,
      contentType: cloudBackupContentType,
    );

final class _CatalogProvider
    implements CloudBackupProvider, CloudBackupCatalogProvider {
  _CatalogProvider(this.providerId, Iterable<RemoteBackupMetadata> items)
    : items = List.of(items);

  @override
  final String providerId;
  final List<RemoteBackupMetadata> items;
  final List<String> deleted = [];

  @override
  Future<List<RemoteBackupMetadata>> listBackups() async => List.of(items);

  @override
  Future<void> deleteBackup(RemoteBackupMetadata expected) async {
    final index = items.indexWhere(
      (item) => item.objectId == expected.objectId,
    );
    if (index < 0) throw StateError('missing');
    deleted.add(expected.objectId);
    items.removeAt(index);
  }

  @override
  Future<List<int>> download(String objectId) => throw UnimplementedError();

  @override
  Future<RemoteBackupMetadata?> inspect(RemoteBackupReservation reservation) =>
      throw UnimplementedError();

  @override
  Future<RemoteBackupReservation> reserve(VerifiedBackupArtifact artifact) =>
      throw UnimplementedError();

  @override
  Future<RemoteBackupMetadata> upload(
    RemoteBackupReservation reservation,
    VerifiedBackupArtifact artifact,
  ) => throw UnimplementedError();
}
