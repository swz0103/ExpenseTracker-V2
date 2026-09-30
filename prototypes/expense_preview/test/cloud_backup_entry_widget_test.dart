import 'dart:io';

import 'package:cloud_backup_probe/cloud_backup.dart';
import 'package:cloud_backup_probe/cloud_backup_history.dart';
import 'package:cloud_backup_probe/cloud_backup_manual_flow.dart';
import 'package:cloud_backup_probe/cloud_backup_schedule.dart';
import 'package:expense_preview/cloud_backup_screen.dart';
import 'package:expense_preview/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';
import 'widget_test.dart' show Documents, closeEngine, input, settle, tap;

void main() {
  testWidgets('home exposes cloud backup and explains missing account link', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final root = Directory('.dart_tool/cloud-backup-entry')
      ..createSync(recursive: true);
    final work = root.createTempSync('case-');
    final engine = engineAt(work, MemoryVault(), schemaVersion: 24);
    try {
      await tester.runAsync(() async {
        await setup(engine);
        await engine.lock();
      });
      await tester.pumpWidget(
        PreviewApp(engine: Future.value(engine), documents: Documents()),
      );
      await settle(tester);
      await input(tester, '密碼', password);
      await tap(tester, '解鎖');
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('open-cloud-backup')),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const ValueKey('open-cloud-backup')));
      await tester.pumpAndSettle();

      expect(find.text('雲端備份'), findsOneWidget);
      expect(find.textContaining('尚未連結雲端帳號'), findsOneWidget);
      expect(find.text('返回帳本'), findsOneWidget);
    } finally {
      await closeEngine(tester, engine);
      await tester.pumpWidget(const SizedBox());
      deleteSynthetic(work, root);
    }
  });

  testWidgets('configured provider is reachable from the formal home entry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final root = Directory('.dart_tool/cloud-backup-entry')
      ..createSync(recursive: true);
    final work = root.createTempSync('configured-');
    final engine = engineAt(work, MemoryVault(), schemaVersion: 24);
    final gateway = _Gateway();
    try {
      await tester.runAsync(() async {
        await setup(engine);
        await engine.lock();
      });
      await tester.pumpWidget(
        PreviewApp(
          engine: Future.value(engine),
          documents: Documents(),
          cloudBackupGatewayFactory: (actual) {
            expect(actual, same(engine));
            return gateway;
          },
        ),
      );
      await settle(tester);
      await input(tester, '密碼', password);
      await tap(tester, '解鎖');
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('open-cloud-backup')),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const ValueKey('open-cloud-backup')));
      await tester.pumpAndSettle();

      expect(find.text('測試雲端'), findsOneWidget);
      await tester.tap(find.text('立即建立加密備份'));
      await tester.pumpAndSettle();
      expect(gateway.createCalls, 1);
      expect(find.text('下載並還原'), findsOneWidget);
    } finally {
      await closeEngine(tester, engine);
      await tester.pumpWidget(const SizedBox());
      deleteSynthetic(work, root);
    }
  });
}

final class _Gateway implements CloudBackupScreenGateway {
  final items = <RemoteBackupMetadata>[];
  var createCalls = 0;

  @override
  List<CloudBackupProviderChoice> get providers => const [
    CloudBackupProviderChoice(id: 'provider-a', label: '測試雲端'),
  ];

  @override
  Future<void> createBackup(String providerId) async {
    createCalls++;
    items.add(
      RemoteBackupMetadata(
        providerId: providerId,
        objectId: 'object-created',
        backupId: 'backup-created',
        sha256: 'a' * 64,
        byteLength: 123,
        createdAt: DateTime.utc(2026, 9, 30),
        contentType: cloudBackupContentType,
      ),
    );
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
  }) async {}

  @override
  Future<CloudBackupRetentionPlan> previewRetention({
    required String providerId,
    required int keepLatest,
    required DateTime now,
  }) async => CloudBackupRetentionPlan(
    providerId: providerId,
    keep: items,
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
