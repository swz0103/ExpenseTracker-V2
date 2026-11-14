import 'dart:io';

import 'package:expense_tracker/src/core/preferences.dart';
import 'package:expense_tracker/src/features/settings/model/app_update.dart';
import 'package:expense_tracker/src/features/settings/ui/update_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _sha = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';

final class _Port implements UpdatePort {
  var outcome = UpdateInstall.started;
  var installs = 0;

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
      'closes, 稍後 just closes', (tester) async {
    final cache = Directory.systemTemp.createTempSync('update-panel-');
    addTearDown(() => cache.deleteSync(recursive: true));
    final port = _Port();
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
    expect(find.text('新版 0.9.6'), findsOneWidget);
    expect(find.text('雲端硬碟可以只備份帳本'), findsOneWidget);
    expect(find.textContaining('MB'), findsNothing);
    await tester.tap(find.text('稍後'));
    await tester.pumpAndSettle();
    expect(find.text('新版 0.9.6'), findsNothing);
    expect(port.installs, 0);

    port.outcome = UpdateInstall.needsPermission;
    showUpdatePanel(page, update).ignore();
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('更新'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('請允許'), findsOneWidget);

    port.outcome = UpdateInstall.started;
    await tester.runAsync(() async {
      await tester.tap(find.text('更新'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(find.text('新版 0.9.6'), findsNothing);
    expect(port.installs, 2);
  });
}
