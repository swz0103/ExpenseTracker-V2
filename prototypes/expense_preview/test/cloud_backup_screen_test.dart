import 'package:cloud_backup_probe/cloud_backup.dart';
import 'package:cloud_backup_probe/cloud_backup_history.dart';
import 'package:cloud_backup_probe/cloud_backup_manual_flow.dart';
import 'package:cloud_backup_probe/cloud_backup_schedule.dart';
import 'package:cloud_backup_probe/cloud_backup_work.dart';
import 'package:expense_preview/cloud_backup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('creates backup and refreshes provider history', (tester) async {
    final gateway = _Gateway();
    await tester.pumpWidget(
      MaterialApp(home: CloudBackupScreen(gateway: gateway)),
    );
    await tester.pumpAndSettle();
    expect(find.text('目前沒有雲端備份。'), findsOneWidget);

    await tester.tap(find.text('立即建立加密備份'));
    await tester.pumpAndSettle();
    expect(gateway.createCalls, 1);
    expect(find.text('下載並還原'), findsOneWidget);
    expect(find.text('加密備份已完成上傳。'), findsOneWidget);
  });

  testWidgets('restore accepts recovery text and hands off verified backup', (
    tester,
  ) async {
    final gateway = _Gateway()..items.add(_item('one'));
    await tester.pumpWidget(
      MaterialApp(home: CloudBackupScreen(gateway: gateway)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('下載並還原'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SwitchListTile, '使用救援文字'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('cloud-restore-credential')),
      'recovery words',
    );
    await tester.tap(find.text('驗證並繼續'));
    await tester.pumpAndSettle();
    expect(gateway.restoreKind, CloudBackupCredentialKind.recoveryKey);
    expect(gateway.restoreCredential, 'recovery words');
    expect(find.text('備份已驗證，並交給安全還原流程。'), findsOneWidget);
  });

  testWidgets('retention does not remove until recoverable cleanup confirmation', (
    tester,
  ) async {
    final gateway = _Gateway()
      ..items.addAll([_item('newest'), _item('oldest')]);
    await tester.pumpWidget(
      MaterialApp(
        home: CloudBackupScreen(
          gateway: gateway,
          now: () => DateTime.utc(2026, 10, 1),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('retention-count')),
      250,
    );
    await tester.tap(find.byKey(const ValueKey('retention-count')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1 份').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('預覽並清理舊備份'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('清理舊備份？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(gateway.applyCalls, 0);

    await tester.tap(find.text('預覽並清理舊備份'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('確認清理'));
    await tester.pumpAndSettle();
    expect(gateway.applyCalls, 1);
    await tester.drag(find.byType(ListView), const Offset(0, 1000));
    await tester.pumpAndSettle();
    expect(find.text('舊備份已依重新核對的預覽結果移出目前清單。'), findsOneWidget);
  });

  testWidgets('authentication failure is actionable and preserves page', (
    tester,
  ) async {
    final gateway = _Gateway()..createFailure = true;
    await tester.pumpWidget(
      MaterialApp(home: CloudBackupScreen(gateway: gateway)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('立即建立加密備份'));
    await tester.pumpAndSettle();
    expect(find.text('雲端登入已失效，請重新連結後再試。'), findsOneWidget);
    expect(find.text('立即建立加密備份'), findsOneWidget);
    expect(find.text('重新連結雲端帳號'), findsOneWidget);

    await tester.tap(find.text('重新連結雲端帳號'));
    await tester.pumpAndSettle();
    expect(gateway.reconnectCalls, 1);
    expect(find.text('雲端帳號已重新連結，待處理備份已完成。'), findsOneWidget);
    expect(find.text('重新連結雲端帳號'), findsNothing);
  });

  testWidgets('automatic backup is opt-in and starts next period', (
    tester,
  ) async {
    final gateway = _Gateway();
    final now = DateTime.utc(2026, 10, 1, 9);
    await tester.pumpWidget(
      MaterialApp(
        home: CloudBackupScreen(gateway: gateway, now: () => now),
      ),
    );
    await tester.pumpAndSettle();
    expect(gateway.scheduleWrites, 0);
    await tester.tap(find.byKey(const ValueKey('automatic-backup')));
    await tester.pumpAndSettle();
    expect(gateway.scheduleWrites, 1);
    expect(gateway.scheduleEnabled, isTrue);
    expect(gateway.scheduleInterval, const Duration(days: 7));
    expect(gateway.firstDueAt, now.add(const Duration(days: 7)));
    expect(find.text('自動備份已啟用，會從下一個週期開始。'), findsOneWidget);
  });

  testWidgets('persisted runtime failure and pending work remain actionable', (
    tester,
  ) async {
    final gateway = _Gateway()
      ..pendingJobs = 2
      ..runtimeFailure = CloudBackupWorkFailure.authenticationRequired;
    await tester.pumpWidget(
      MaterialApp(home: CloudBackupScreen(gateway: gateway)),
    );
    await tester.pumpAndSettle();
    expect(gateway.maintenanceCalls, 1);
    expect(find.text('尚有 2 份加密備份等待上傳。'), findsOneWidget);
    expect(find.text('雲端登入已失效，請重新連結後續傳。'), findsOneWidget);
    expect(find.text('重新連結雲端帳號'), findsOneWidget);
  });
}

RemoteBackupMetadata _item(String id) => RemoteBackupMetadata(
  providerId: 'provider-a',
  objectId: id,
  backupId: 'backup-$id',
  sha256: 'a' * 64,
  byteLength: 123,
  createdAt: id == 'oldest'
      ? DateTime.utc(2026, 9, 1)
      : DateTime.utc(2026, 10, 1),
  contentType: cloudBackupContentType,
);

final class _Gateway
    implements CloudBackupScreenGateway, CloudBackupRuntimeGateway {
  final items = <RemoteBackupMetadata>[];
  var createCalls = 0;
  var applyCalls = 0;
  var createFailure = false;
  var reconnectCalls = 0;
  CloudBackupCredentialKind? restoreKind;
  String? restoreCredential;
  var scheduleWrites = 0;
  bool? scheduleEnabled;
  Duration? scheduleInterval;
  DateTime? firstDueAt;
  var maintenanceCalls = 0;
  var pendingJobs = 0;
  CloudBackupWorkFailure? runtimeFailure;

  @override
  Future<CloudBackupRuntimeReport> maintainRuntime(
    String providerId,
    DateTime now,
  ) async {
    maintenanceCalls++;
    return CloudBackupRuntimeReport(
      pendingJobs: pendingJobs,
      lastFailure: runtimeFailure,
    );
  }

  @override
  List<CloudBackupProviderChoice> get providers => const [
    CloudBackupProviderChoice(id: 'provider-a', label: '測試雲端'),
  ];

  @override
  bool canReconnect(String providerId) => providerId == 'provider-a';

  @override
  Future<void> reconnect(String providerId) async {
    reconnectCalls++;
    createFailure = false;
  }

  @override
  Future<void> createBackup(String providerId) async {
    createCalls++;
    if (createFailure) {
      throw const CloudBackupProviderException(
        CloudBackupProviderFailure.authenticationRequired,
      );
    }
    items.add(_item('created'));
  }

  @override
  Future<List<RemoteBackupMetadata>> history(String providerId) async =>
      List.of(items);

  @override
  Future<void> restore({
    required String providerId,
    required RemoteBackupMetadata backup,
    required CloudBackupCredentialKind credentialKind,
    required String credential,
  }) async {
    restoreKind = credentialKind;
    restoreCredential = credential;
  }

  @override
  Future<CloudBackupRetentionPlan> previewRetention({
    required String providerId,
    required int keepLatest,
    required DateTime now,
  }) async => CloudBackupRetentionPlan(
    providerId: providerId,
    keep: items.take(keepLatest),
    delete: items.skip(keepLatest),
  );

  @override
  Future<void> applyRetention(CloudBackupRetentionPlan plan) async {
    applyCalls++;
    final ids = plan.delete.map((item) => item.objectId).toSet();
    items.removeWhere((item) => ids.contains(item.objectId));
  }

  @override
  Future<CloudBackupScheduleRecord?> schedule(String providerId) async => null;

  @override
  Future<void> configureSchedule({
    required String providerId,
    required bool enabled,
    required Duration interval,
    required DateTime firstDueAt,
    required DateTime now,
  }) async {
    scheduleWrites++;
    scheduleEnabled = enabled;
    scheduleInterval = interval;
    this.firstDueAt = firstDueAt;
  }
}
