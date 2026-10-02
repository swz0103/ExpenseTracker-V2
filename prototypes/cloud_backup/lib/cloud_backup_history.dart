import 'cloud_backup.dart';

/// Optional provider capability used by history and retention. Upload-only
/// providers can still participate in the registry without implementing it.
abstract interface class CloudBackupCatalogProvider {
  String get providerId;

  Future<List<RemoteBackupMetadata>> listBackups();

  /// Removes exactly [expected] from active history. Implementations must
  /// inspect current remote metadata again, fail closed if it changed, and use
  /// provider trash or another recoverable removal mechanism when available.
  Future<void> deleteBackup(RemoteBackupMetadata expected);
}

final class CloudBackupProviderRegistry {
  CloudBackupProviderRegistry(Iterable<CloudBackupProvider> providers)
    : _providers = _index(providers);

  final Map<String, CloudBackupProvider> _providers;

  List<String> get providerIds => _providers.keys.toList(growable: false);

  CloudBackupProvider provider(String providerId) {
    final result = _providers[providerId];
    if (result == null) throw StateError('Unknown cloud backup provider');
    return result;
  }

  CloudBackupCatalogProvider catalog(String providerId) {
    final result = provider(providerId);
    if (result is! CloudBackupCatalogProvider) {
      throw StateError('Provider does not support backup history');
    }
    return result as CloudBackupCatalogProvider;
  }

  static Map<String, CloudBackupProvider> _index(
    Iterable<CloudBackupProvider> providers,
  ) {
    final result = <String, CloudBackupProvider>{};
    for (final provider in providers) {
      _validateProviderId(provider.providerId);
      if (result.containsKey(provider.providerId)) {
        throw StateError('Duplicate cloud backup provider ID');
      }
      result[provider.providerId] = provider;
    }
    if (result.isEmpty)
      throw ArgumentError('At least one provider is required');
    return Map.unmodifiable(result);
  }
}

final class CloudBackupRetentionPolicy {
  const CloudBackupRetentionPolicy({
    required this.keepLatest,
    this.minimumAge = Duration.zero,
  });

  final int keepLatest;
  final Duration minimumAge;

  void validate() {
    if (keepLatest < 1 || keepLatest > 100) {
      throw ArgumentError.value(keepLatest, 'keepLatest');
    }
    if (minimumAge.isNegative) {
      throw ArgumentError.value(minimumAge, 'minimumAge');
    }
  }
}

final class CloudBackupRetentionPlan {
  CloudBackupRetentionPlan({
    required this.providerId,
    required Iterable<RemoteBackupMetadata> keep,
    required Iterable<RemoteBackupMetadata> delete,
  }) : keep = List.unmodifiable(keep),
       delete = List.unmodifiable(delete);

  final String providerId;
  final List<RemoteBackupMetadata> keep;
  final List<RemoteBackupMetadata> delete;
}

/// Produces a deterministic preview. Nothing is deleted until [apply] is
/// explicitly called with that preview.
final class CloudBackupRetentionService {
  const CloudBackupRetentionService(this.provider);

  final CloudBackupCatalogProvider provider;

  Future<List<RemoteBackupMetadata>> history() async {
    final items = await provider.listBackups();
    for (final item in items) {
      _validateHistoryItem(item, provider.providerId);
    }
    final sorted = List<RemoteBackupMetadata>.from(items)
      ..sort((a, b) {
        final time = b.createdAt.toUtc().compareTo(a.createdAt.toUtc());
        return time != 0 ? time : b.objectId.compareTo(a.objectId);
      });
    final identities = <String>{};
    for (final item in sorted) {
      if (!identities.add(item.objectId)) {
        throw const CloudBackupValidationException(
          CloudBackupValidationFailure.remoteMetadataMismatch,
        );
      }
    }
    return List.unmodifiable(sorted);
  }

  Future<CloudBackupRetentionPlan> preview(
    CloudBackupRetentionPolicy policy, {
    required DateTime now,
  }) async {
    policy.validate();
    final items = await history();
    final cutoff = now.toUtc().subtract(policy.minimumAge);
    final keep = <RemoteBackupMetadata>[];
    final remove = <RemoteBackupMetadata>[];
    for (var index = 0; index < items.length; index++) {
      final item = items[index];
      if (index < policy.keepLatest || item.createdAt.toUtc().isAfter(cutoff)) {
        keep.add(item);
      } else {
        remove.add(item);
      }
    }
    return CloudBackupRetentionPlan(
      providerId: provider.providerId,
      keep: keep,
      delete: remove,
    );
  }

  Future<void> apply(CloudBackupRetentionPlan plan) async {
    if (plan.providerId != provider.providerId) {
      throw StateError('Retention plan belongs to another provider');
    }
    _validatePlan(plan);
    var remaining = List<RemoteBackupMetadata>.of(plan.delete);
    if (remaining.isEmpty) {
      await _requirePlanState(plan, remaining);
      return;
    }
    while (remaining.isNotEmpty) {
      final expected = remaining.first;
      // Retention is deliberately expensive: re-read immediately before every
      // destructive operation so a stale preview cannot silently outlive a
      // keep-item removal or metadata change from another client.
      await _requirePlanState(plan, remaining);
      await provider.deleteBackup(expected);
      remaining = remaining.sublist(1);
      // Verify the invariant again after every provider call. A provider may
      // implement deletion as recoverable trash, but the service never assumes
      // that a successful response preserved the planned keep set.
      await _requirePlanState(plan, remaining);
    }
  }

  void _validatePlan(CloudBackupRetentionPlan plan) {
    if (plan.keep.isEmpty) {
      throw const CloudBackupValidationException(
        CloudBackupValidationFailure.remoteMetadataMismatch,
      );
    }
    final identities = <String>{};
    for (final item in [...plan.keep, ...plan.delete]) {
      _validateHistoryItem(item, provider.providerId);
      if (!identities.add(item.objectId)) {
        throw const CloudBackupValidationException(
          CloudBackupValidationFailure.remoteMetadataMismatch,
        );
      }
    }
  }

  Future<void> _requirePlanState(
    CloudBackupRetentionPlan plan,
    List<RemoteBackupMetadata> remaining,
  ) async {
    final current = {for (final item in await history()) item.objectId: item};
    for (final expected in [...plan.keep, ...remaining]) {
      final actual = current[expected.objectId];
      if (actual == null || !_sameMetadata(actual, expected)) {
        throw const CloudBackupValidationException(
          CloudBackupValidationFailure.remoteMetadataMismatch,
        );
      }
    }
    if (current.length - remaining.length < plan.keep.length) {
      throw const CloudBackupValidationException(
        CloudBackupValidationFailure.remoteMetadataMismatch,
      );
    }
  }
}

bool _sameMetadata(RemoteBackupMetadata a, RemoteBackupMetadata b) =>
    a.providerId == b.providerId &&
    a.objectId == b.objectId &&
    a.backupId == b.backupId &&
    a.sha256 == b.sha256 &&
    a.byteLength == b.byteLength &&
    a.createdAt.toUtc() == b.createdAt.toUtc() &&
    a.contentType == b.contentType;

void _validateHistoryItem(RemoteBackupMetadata item, String providerId) {
  if (item.providerId != providerId ||
      item.objectId.isEmpty ||
      item.backupId.isEmpty ||
      !RegExp(r'^[0-9a-f]{64}$').hasMatch(item.sha256) ||
      item.byteLength < 1 ||
      item.contentType != cloudBackupContentType) {
    throw const CloudBackupValidationException(
      CloudBackupValidationFailure.remoteMetadataMismatch,
    );
  }
}

void _validateProviderId(String value) {
  if (value.isEmpty ||
      value.length > 200 ||
      !RegExp(r'^[a-zA-Z0-9._:-]+$').hasMatch(value)) {
    throw ArgumentError.value(value, 'providerId');
  }
}
