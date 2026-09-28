import 'dart:io';

import 'package:expense_preview/main.dart';
import 'package:expense_preview/app_pin.dart';
import 'package:expense_preview/platform_services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';
import 'widget_test.dart' show Documents, closeEngine, input, settle, tap;

final class _DeviceUnlock implements DeviceUnlockStore {
  String? saved;
  int reads = 0;
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
    reads++;
    onRead?.call();
    if (failRead) throw StateError('user cancelled');
    return saved;
  }

  @override
  Future<void> disable() async => saved = null;
}

final class _AppPin implements AppPinStore {
  String? saved;
  bool failRead = false;
  VoidCallback? onMatch;
  VoidCallback? onEnable;
  @override
  Future<bool> isEnabled() async {
    if (failRead) throw StateError('PIN storage unavailable');
    return saved != null;
  }

  @override
  Future<void> enable(String pin) async {
    onEnable?.call();
    saved = pin;
  }

  @override
  Future<bool> matches(String pin) async {
    onMatch?.call();
    return saved == pin;
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

  testWidgets(
    'App PIN adds a device-authenticated gate with password fallback',
    (tester) async {
      final work = root.createTempSync('pin-flow-');
      final engine = engineAt(work, MemoryVault(), schemaVersion: 14);
      final shortcut = _DeviceUnlock();
      final pin = _AppPin();
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
            appPin: pin,
          ),
        );
        await settle(tester);
        await input(tester, '密碼', password);
        expect(find.byType(CheckboxListTile), findsOneWidget);
        await tester.tap(find.byType(CheckboxListTile));
        await tester.pump();
        await tap(tester, '解鎖');
        await tap(tester, '設定 App PIN');
        await input(tester, '新 App PIN（6–12 位數字）', '123456');
        await input(tester, '再次輸入 App PIN', '123456');
        await tap(tester, '啟用 App PIN');
        expect(pin.saved, '123456');
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await settle(tester);
        expect(engine.isUnlocked, isFalse);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await settle(tester);
        expect(find.text('使用裝置解鎖'), findsNothing);
        await input(tester, 'App PIN（6–12 位數字）', '000000');
        await tap(tester, '使用 App PIN 與裝置認證');
        expect(engine.isUnlocked, isFalse);
        expect(shortcut.reads, greaterThanOrEqualTo(2));
        await input(tester, 'App PIN（6–12 位數字）', '123456');
        await tap(tester, '使用 App PIN 與裝置認證');
        expect(engine.isUnlocked, isTrue);
        await tap(tester, '停用 App PIN');
        await input(tester, '目前 App PIN', '123456');
        await tap(tester, '確認停用 App PIN');
        expect(pin.saved, isNull);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await settle(tester);
        expect(find.text('使用裝置解鎖'), findsOneWidget);
      } finally {
        await closeEngine(tester, engine);
        await tester.pumpWidget(const SizedBox());
        deleteSynthetic(work, root);
      }
    },
  );

  testWidgets('master password can recover a forgotten App PIN', (
    tester,
  ) async {
    final work = root.createTempSync('pin-recovery-');
    final engine = engineAt(work, MemoryVault(), schemaVersion: 14);
    final shortcut = _DeviceUnlock()..saved = password;
    final pin = _AppPin()..saved = '123456';
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
          appPin: pin,
        ),
      );
      await settle(tester);
      expect(find.text('使用裝置解鎖'), findsNothing);
      await input(tester, '密碼', password);
      await tap(tester, '解鎖');
      await tap(tester, '停用這台手機的裝置解鎖');
      expect(shortcut.saved, isNull);
      expect(pin.saved, isNull);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await settle(tester);
      expect(find.text('使用 App PIN 與裝置認證'), findsNothing);
      await input(tester, '密碼', password);
      await tap(tester, '解鎖');
      expect(engine.isUnlocked, isTrue);
    } finally {
      await closeEngine(tester, engine);
      await tester.pumpWidget(const SizedBox());
      deleteSynthetic(work, root);
    }
  });

  testWidgets('background during PIN verification cannot reopen ledger', (
    tester,
  ) async {
    final work = root.createTempSync('pin-background-');
    final engine = engineAt(work, MemoryVault(), schemaVersion: 14);
    final shortcut = _DeviceUnlock()..saved = password;
    final pin = _AppPin()..saved = '123456';
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
          appPin: pin,
        ),
      );
      await settle(tester);
      pin.onMatch = () {
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
      await input(tester, 'App PIN（6–12 位數字）', '123456');
      await tap(tester, '使用 App PIN 與裝置認證');
      expect(engine.isUnlocked, isFalse);
    } finally {
      await closeEngine(tester, engine);
      await tester.pumpWidget(const SizedBox());
      deleteSynthetic(work, root);
    }
  });

  testWidgets('background during PIN enrollment revokes the unfinished PIN', (
    tester,
  ) async {
    final work = root.createTempSync('pin-enrollment-background-');
    final engine = engineAt(work, MemoryVault(), schemaVersion: 14);
    final shortcut = _DeviceUnlock()..saved = password;
    final pin = _AppPin();
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
          appPin: pin,
        ),
      );
      await settle(tester);
      await input(tester, '密碼', password);
      await tap(tester, '解鎖');
      await tap(tester, '設定 App PIN');
      await input(tester, '新 App PIN（6–12 位數字）', '123456');
      await input(tester, '再次輸入 App PIN', '123456');
      pin.onEnable = () {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      };
      await tap(tester, '啟用 App PIN');
      expect(engine.isUnlocked, isFalse);
      expect(pin.saved, isNull);
    } finally {
      await closeEngine(tester, engine);
      await tester.pumpWidget(const SizedBox());
      deleteSynthetic(work, root);
    }
  });

  testWidgets('unreadable PIN state hides the device shortcut', (tester) async {
    final work = root.createTempSync('pin-unreadable-');
    final engine = engineAt(work, MemoryVault(), schemaVersion: 14);
    final shortcut = _DeviceUnlock()..saved = password;
    final pin = _AppPin()
      ..saved = '123456'
      ..failRead = true;
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
          appPin: pin,
        ),
      );
      await settle(tester);
      expect(find.text('使用裝置解鎖'), findsNothing);
      expect(find.text('使用 App PIN 與裝置認證'), findsNothing);
      await input(tester, '密碼', password);
      await tap(tester, '解鎖');
      expect(engine.isUnlocked, isTrue);
      expect(shortcut.reads, 0);
    } finally {
      await closeEngine(tester, engine);
      await tester.pumpWidget(const SizedBox());
      deleteSynthetic(work, root);
    }
  });
}
