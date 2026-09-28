import 'dart:io';

import 'package:expense_preview/main.dart';
import 'package:expense_preview/platform_services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';
import 'widget_test.dart' show Documents, closeEngine, input, settle, tap;

final class _DeviceUnlock implements DeviceUnlockStore {
  String? saved;
  bool failWrite = false;
  bool failRead = false;
  VoidCallback? onRead;
  @override
  Future<bool> isEnabled() async => saved != null;
  @override
  Future<void> enable(String password) async {
    if (failWrite) throw StateError('device not enrolled');
    saved = password;
  }

  @override
  Future<String?> readPassword() async {
    onRead?.call();
    if (failRead) throw StateError('user cancelled');
    return saved;
  }

  @override
  Future<void> disable() async => saved = null;
}

void main() {
  final root = Directory('.dart_tool/device-unlock-widget')
    ..createSync(recursive: true);

  testWidgets('opt-in, background lock, device unlock and revoke', (
    tester,
  ) async {
    final work = root.createTempSync('flow-');
    final engine = engineAt(work, MemoryVault(), schemaVersion: 14);
    final shortcut = _DeviceUnlock();
    try {
      await tester.runAsync(() async {
        await setup(engine);
        await engine.lock();
      });
      await tester.pumpWidget(
        PreviewApp(
          engine: Future.value(engine),
          documents: Documents(),
          deviceUnlock: shortcut,
        ),
      );
      await settle(tester);
      expect(shortcut.saved, isNull);
      await input(tester, '密碼', password);
      await tester.tap(find.widgetWithText(CheckboxListTile, '在這台手機啟用裝置解鎖'));
      await tester.pump();
      await tap(tester, '解鎖');
      expect(engine.isUnlocked, isTrue);
      expect(shortcut.saved, password);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await settle(tester);
      expect(engine.isUnlocked, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      shortcut.onRead = () {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        Future<void>.delayed(const Duration(milliseconds: 100), () {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
        });
      };
      await tap(tester, '使用裝置解鎖');
      expect(engine.isUnlocked, isTrue);

      await tap(tester, '停用這台手機的裝置解鎖');
      expect(shortcut.saved, isNull);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await settle(tester);
      expect(find.text('使用裝置解鎖'), findsNothing);
      expect(engine.isUnlocked, isFalse);
    } finally {
      await closeEngine(tester, engine);
      await tester.pumpWidget(const SizedBox());
      deleteSynthetic(work, root);
    }
  });

  testWidgets('enrollment failure leaves password unlock usable', (
    tester,
  ) async {
    final work = root.createTempSync('failure-');
    final engine = engineAt(work, MemoryVault(), schemaVersion: 14);
    final shortcut = _DeviceUnlock()..failWrite = true;
    try {
      await tester.runAsync(() async {
        await setup(engine);
        await engine.lock();
      });
      await tester.pumpWidget(
        PreviewApp(
          engine: Future.value(engine),
          documents: Documents(),
          deviceUnlock: shortcut,
        ),
      );
      await settle(tester);
      await input(tester, '密碼', password);
      await tester.tap(find.widgetWithText(CheckboxListTile, '在這台手機啟用裝置解鎖'));
      await tester.pump();
      await tap(tester, '解鎖');
      expect(engine.isUnlocked, isTrue);
      expect(shortcut.saved, isNull);
      expect(find.text('裝置解鎖未啟用；仍可使用帳本密碼。'), findsOneWidget);
    } finally {
      await closeEngine(tester, engine);
      await tester.pumpWidget(const SizedBox());
      deleteSynthetic(work, root);
    }
  });

  testWidgets('device prompt failure never opens ledger', (tester) async {
    final work = root.createTempSync('cancel-');
    final engine = engineAt(work, MemoryVault(), schemaVersion: 14);
    final shortcut = _DeviceUnlock()..saved = password;
    try {
      await tester.runAsync(() async {
        await setup(engine);
        await engine.lock();
      });
      await tester.pumpWidget(
        PreviewApp(
          engine: Future.value(engine),
          documents: Documents(),
          deviceUnlock: shortcut,
        ),
      );
      await settle(tester);
      shortcut.failRead = true;
      await tap(tester, '使用裝置解鎖');
      expect(engine.isUnlocked, isFalse);
      await input(tester, '密碼', password);
      await tap(tester, '解鎖');
      expect(engine.isUnlocked, isTrue);
    } finally {
      await closeEngine(tester, engine);
      await tester.pumpWidget(const SizedBox());
      deleteSynthetic(work, root);
    }
  });

  testWidgets('leaving the app during device prompt locks the ledger', (
    tester,
  ) async {
    final work = root.createTempSync('background-');
    final engine = engineAt(work, MemoryVault(), schemaVersion: 14);
    final shortcut = _DeviceUnlock()..saved = password;
    try {
      await tester.runAsync(() async {
        await setup(engine);
        await engine.lock();
      });
      await tester.pumpWidget(
        PreviewApp(
          engine: Future.value(engine),
          documents: Documents(),
          deviceUnlock: shortcut,
        ),
      );
      await settle(tester);
      shortcut.onRead = () {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        Future<void>.delayed(const Duration(milliseconds: 100), () {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.hidden,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
        });
      };
      await tap(tester, '使用裝置解鎖');
      expect(engine.isUnlocked, isFalse);
      expect(engine.isUnlocked, isFalse);
    } finally {
      await closeEngine(tester, engine);
      await tester.pumpWidget(const SizedBox());
      deleteSynthetic(work, root);
    }
  });
}
