import 'cloud_backup_screen.dart';

final class CloudBackupApplicationProviderReport {
  const CloudBackupApplicationProviderReport({
    required this.providerId,
    this.runtime,
    this.error,
  });

  final String providerId;
  final CloudBackupRuntimeReport? runtime;
  final Object? error;
}

/// Owns application-level cloud maintenance independently of the backup page.
/// Calls are serialized so cold-start upload recovery and post-unlock schedule
/// capture cannot race the same persistent job stores.
final class CloudBackupApplicationRunner {
  CloudBackupApplicationRunner(this.gateway);

  final CloudBackupScreenGateway gateway;
  Future<void> _tail = Future.value();

  Future<List<CloudBackupApplicationProviderReport>> maintainPending(
    DateTime now,
  ) => _enqueue(() async {
    final pending = gateway is CloudBackupPendingRuntimeGateway
        ? gateway as CloudBackupPendingRuntimeGateway
        : null;
    if (pending == null) return const [];
    return _forProviders(
      (providerId) => pending.maintainPendingRuntime(providerId, now.toUtc()),
    );
  });

  Future<List<CloudBackupApplicationProviderReport>> maintainUnlocked(
    DateTime now,
  ) => _enqueue(() async {
    final runtime = gateway is CloudBackupRuntimeGateway
        ? gateway as CloudBackupRuntimeGateway
        : null;
    if (runtime == null) return const [];
    return _forProviders(
      (providerId) => runtime.maintainRuntime(providerId, now.toUtc()),
    );
  });

  Future<List<CloudBackupApplicationProviderReport>> _forProviders(
    Future<CloudBackupRuntimeReport> Function(String providerId) maintain,
  ) async {
    final reports = <CloudBackupApplicationProviderReport>[];
    for (final provider in gateway.providers) {
      try {
        reports.add(
          CloudBackupApplicationProviderReport(
            providerId: provider.id,
            runtime: await maintain(provider.id),
          ),
        );
      } catch (error) {
        reports.add(
          CloudBackupApplicationProviderReport(
            providerId: provider.id,
            error: error,
          ),
        );
      }
    }
    return List.unmodifiable(reports);
  }

  Future<List<CloudBackupApplicationProviderReport>> _enqueue(
    Future<List<CloudBackupApplicationProviderReport>> Function() operation,
  ) {
    final run = _tail.then((_) => operation());
    _tail = run.then<void>((_) {}, onError: (_) {});
    return run;
  }
}
