// 關於 in the two Android flavors. Whether the build may update itself is a
// compile-time constant (core/platform/distribution.dart), so each case
// runs in the build it is written for: the play case with
// `flutter test --flavor play test/app/about_section_test.dart`
// (CI's play job does), the sideload case in every other run.
import 'dart:io';

import 'package:expense_tracker/src/app/about_section.dart';
import 'package:expense_tracker/src/app/demo/seed.dart';
import 'package:expense_tracker/src/core/platform/distribution.dart';
import 'package:expense_tracker/src/core/platform/preferences.dart';
import 'package:expense_tracker/src/features/settings/model/app_update.dart';
import 'package:expense_tracker/src/features/settings/model/platform_services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _sha = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';

/// A port that counts how often the internet is asked.
final class _Port implements UpdatePort {
  var fetched = 0;

  @override
  Future<String> fetch(Uri url) async {
    fetched++;
    return '{"build":190,"version":"2.0.0","sha256":"$_sha","size":3}';
  }

  @override
  Future<void> download(
    Uri url,
    File into,
    void Function(int received) progress,
  ) async {}

  @override
  Future<UpdateInstall> install(File apk, String sha256) async =>
      UpdateInstall.started;
}

void main() {
  Future<void> open(WidgetTester tester, PlatformServices services) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [AboutSection(ledger: demoLedger(), services: services)],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'sideload: 關於 offers the automatic check and looks for a newer build',
    (tester) async {
      final cache = Directory.systemTemp.createTempSync('about-flavor-');
      addTearDown(() => cache.deleteSync(recursive: true));
      final port = _Port();
      final preferences = Preferences();
      final update = AppUpdate(port, preferences, cache: cache, build: 186);
      await open(
        tester,
        PlatformServices(preferences: preferences, update: update),
      );
      expect(find.text('自動檢查新版本'), findsOneWidget);
      expect(port.fetched, 1);
      expect(find.text('有新版 2.0.0'), findsOneWidget);
    },
    // A sideload case: skipped in the play build.
    skip: !canSelfUpdate,
  );

  testWidgets(
    'play: 關於 shows no update, and nothing is asked of the internet',
    (tester) async {
      // Even a port that was handed in is never used: the build cannot
      // update itself.
      final cache = Directory.systemTemp.createTempSync('about-flavor-');
      addTearDown(() => cache.deleteSync(recursive: true));
      final port = _Port();
      final preferences = Preferences();
      final update = AppUpdate(port, preferences, cache: cache, build: 186);
      expect(update.possible, isFalse);
      await open(
        tester,
        PlatformServices(preferences: preferences, update: update),
      );
      expect(port.fetched, 0);
      expect(await update.check(), isNull);
      expect(port.fetched, 0);
      for (final text in [
        '自動檢查新版本',
        '自行建置的版本',
        '點這裡檢查更新',
        '檢查中…',
        '已是最新',
        '更新',
      ]) {
        expect(find.text(text), findsNothing, reason: text);
      }
      // The rest of 關於 is still there.
      expect(find.text('診斷'), findsOneWidget);
    },
    // A play case: skipped unless run with --flavor play.
    skip: canSelfUpdate,
  );
}
