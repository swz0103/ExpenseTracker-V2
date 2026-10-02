import 'dart:async';

import 'package:cloud_backup_probe/cloud_backup.dart';
import 'package:cloud_backup_probe/cloud_backup_history.dart';
import 'package:cloud_backup_probe/cloud_backup_manual_flow.dart';
import 'package:cloud_backup_probe/cloud_backup_schedule.dart';
import 'package:expense_preview/cloud_backup_application_runner.dart';
import 'package:expense_preview/cloud_backup_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cold start pumps encrypted work without ticking schedule', () async {
    final gateway = _Gateway();
    final runner = CloudBackupApplicationRunner(gateway);
    final now = DateTime.utc(2026, 10, 2, 8);

    final reports = await runner.maintainPending(now);

    expect(gateway.pendingCalls, ['provider-a', 'provider-b']);
    expect(gateway.unlockedCalls, isEmpty);
    expect(reports, hasLength(2));
    expect(reports.every((report) => report.runtime?.pendingJobs == 1), isTrue);
  });

  test(
    'post-unlock runner checks every provider and isolates failure',
    () async {
      final gateway = _Gateway(failProvider: 'provider-b');
      final runner = CloudBackupApplicationRunner(gateway);

      final reports = await runner.maintainUnlocked(
        DateTime.utc(2026, 10, 2, 9),
      );

      expect(gateway.unlockedCalls, ['provider-a', 'provider-b']);
      expect(reports, hasLength(2));
      expect(reports.first.runtime?.pendingJobs, 0);
      expect(reports.last.error, isA<StateError>());
    },
  );

  test('cold-start and unlocked maintenance are serialized', () async {
    final gateway = _Gateway(blockPending: true);
    final runner = CloudBackupApplicationRunner(gateway);
    final pending = runner.maintainPending(DateTime.utc(2026, 10, 2, 8));
    final unlocked = runner.maintainUnlocked(DateTime.utc(2026, 10, 2, 9));

    await Future<void>.delayed(Duration.zero);
    expect(gateway.events, ['pending-start:provider-a']);
    gateway.releasePending();
    await Future.wait([pending, unlocked]);
    expect(gateway.events, [
      'pending-start:provider-a',
      'pending-end:provider-a',
      'pending-start:provider-b',
      'pending-end:provider-b',
      'unlocked:provider-a',
      'unlocked:provider-b',
    ]);
  });
}

final class _Gateway
    implements
        CloudBackupScreenGateway,
        CloudBackupPendingRuntimeGateway,
        CloudBackupRuntimeGateway {
  _Gateway({this.failProvider, this.blockPending = false});

  final String? failProvider;
  final bool blockPending;
  final pendingCalls = <String>[];
  final unlockedCalls = <String>[];
  final events = <String>[];
  final _pendingCompleters = <Completer<void>>[];

  void releasePending() {
    for (final completer in List.of(_pendingCompleters)) {
      completer.complete();
    }
    _pendingCompleters.clear();
  }

  @override
  List<CloudBackupProviderChoice> get providers => const [
    CloudBackupProviderChoice(id: 'provider-a', label: 'A'),
    CloudBackupProviderChoice(id: 'provider-b', label: 'B'),
  ];

  @override
  Future<CloudBackupRuntimeReport> maintainPendingRuntime(
    String providerId,
    DateTime now,
  ) async {
    pendingCalls.add(providerId);
    events.add('pending-start:$providerId');
    if (blockPending && providerId == 'provider-a') {
      final completer = Completer<void>();
      _pendingCompleters.add(completer);
      await completer.future;
    }
    events.add('pending-end:$providerId');
    return const CloudBackupRuntimeReport(pendingJobs: 1);
  }

  @override
  Future<CloudBackupRuntimeReport> maintainRuntime(
    String providerId,
    DateTime now,
  ) async {
    unlockedCalls.add(providerId);
    events.add('unlocked:$providerId');
    if (providerId == failProvider) throw StateError('injected');
    return const CloudBackupRuntimeReport(pendingJobs: 0);
  }

  @override
  bool canReconnect(String providerId) => false;
  @override
  Future<void> reconnect(String providerId) async {}
  @override
  Future<void> createBackup(String providerId) async {}
  @override
  Future<List<RemoteBackupMetadata>> history(String providerId) async =>
      const [];
  @override
  Future<void> restore({
    required String providerId,
    required RemoteBackupMetadata backup,
    required CloudBackupCredentialKind credentialKind,
    required String credential,
  }) async {}
  @override
  Future<CloudBackupRetentionPlan> previewRetention({
    required String providerId,
    required int keepLatest,
    required DateTime now,
  }) async => CloudBackupRetentionPlan(
    providerId: providerId,
    keep: const [],
    delete: const [],
  );
  @override
  Future<void> applyRetention(CloudBackupRetentionPlan plan) async {}
  @override
  Future<CloudBackupScheduleRecord?> schedule(String providerId) async => null;
  @override
  Future<void> configureSchedule({
    required String providerId,
    required bool enabled,
    required Duration interval,
    required DateTime firstDueAt,
    required DateTime now,
  }) async {}
}
