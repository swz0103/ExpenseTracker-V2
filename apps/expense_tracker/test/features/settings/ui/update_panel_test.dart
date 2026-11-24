import 'dart:async';
import 'dart:io';

import 'package:expense_tracker/src/core/design_system/keys.dart';
import 'package:expense_tracker/src/core/platform/preferences.dart';
import 'package:expense_tracker/src/features/settings/model/app_update.dart';
import 'package:expense_tracker/src/features/settings/ui/update_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _sha = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';

final class _Port implements UpdatePort {
  var outcome = UpdateInstall.started;
  var installs = 0;

  /// Holds the download after its first piece until completed.
  Completer<void>? hold;

  @override
  Future<String> fetch(Uri url) async =>
      '{"build":200,"version":"0.9.6","sha256":"$_sha","size":3,'
      '"notes":["雲端硬碟可以只備份帳本","打開就檢查更新"]}';

  @override
  Future<void> download(
    Uri url,
    File into,
    void Function(int received) progress,
  ) async {
    into.writeAsStringSync('abc');
    if (hold case final held?) {
      progress(1);
      await held.future;
    }
    progress(3);
  }

  @override
  Future<UpdateInstall> install(File apk, String sha256) async {
    installs++;
    return outcome;
  }
}

void main() {
  testWidgets('a newer version shows what it changes; 更新 installs it and '
      'closes; only its own choices close it', (tester) async {
    final cache = Directory.systemTemp.createTempSync('update-panel-');
    addTearDown(() => cache.deleteSync(recursive: true));
    final port = _Port();
    final preferences = Preferences();
    final update = AppUpdate(port, preferences, cache: cache, build: 190);
    await tester.runAsync(update.check);
    late BuildContext page;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            page = context;
            return const SizedBox();
          },
        ),
      ),
    );

    showUpdatePanel(page, update).ignore();
    await tester.pumpAndSettle();
    expect(find.text('新版 0.9.6'), findsOneWidget);
    expect(find.text('雲端硬碟可以只備份帳本'), findsOneWidget);
    expect(find.textContaining('MB'), findsNothing);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('新版 0.9.6'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('新版 0.9.6'), findsOneWidget);
    await tester.tap(find.byKey(Keys.later));
    await tester.pumpAndSettle();
    expect(find.text('新版 0.9.6'), findsNothing);
    expect(port.installs, 0);
    expect(update.mayOffer(update.newer!), isFalse);
    expect(preferences.updateLaterUntil, isNotNull);

    showUpdatePanel(page, update).ignore();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Keys.skip));
    await tester.pumpAndSettle();
    expect(find.text('新版 0.9.6'), findsNothing);
    expect(preferences.updateSkipped, 200);

    port.outcome = UpdateInstall.needsPermission;
    showUpdatePanel(page, update).ignore();
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(Keys.install));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('請允許'), findsOneWidget);

    port.outcome = UpdateInstall.started;
    await tester.runAsync(() async {
      await tester.tap(find.byKey(Keys.install));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(find.text('新版 0.9.6'), findsNothing);
    expect(port.installs, 2);
  });

  testWidgets('D85: a download under way shows 取消下載, which stops it and '
      'goes back to the choices without a word of failure', (tester) async {
    final cache = Directory.systemTemp.createTempSync('update-panel-');
    addTearDown(() => cache.deleteSync(recursive: true));
    final port = _Port()..hold = Completer<void>();
    final update = AppUpdate(port, Preferences(), cache: cache, build: 190);
    await tester.runAsync(update.check);
    late BuildContext page;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            page = context;
            return const SizedBox();
          },
        ),
      ),
    );
    showUpdatePanel(page, update).ignore();
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(Keys.install));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    expect(find.text('下載中 33%'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(Keys.cancelDownload));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.byKey(Keys.cancelDownload), findsNothing);
    expect(find.byKey(Keys.install), findsOneWidget);
    expect(find.textContaining('失敗'), findsNothing);
    expect(port.installs, 0);
    port.hold!.complete();
  });
}
