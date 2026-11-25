// 關於 in the two Android flavors. Whether the build may update itself is a
// compile-time constant (core/platform/distribution.dart), so each case
// runs in the build it is written for: the play case with
// `flutter test --flavor play test/app/about_section_test.dart`
// (CI's play job does), the sideload case in every other run.
import 'dart:async';
import 'dart:io';

import 'package:expense_tracker/src/app/about_section.dart';
import 'package:expense_tracker/src/app/demo/seed.dart';
import 'package:expense_tracker/src/core/design_system/keys.dart';
import 'package:expense_tracker/src/core/platform/distribution.dart';
import 'package:expense_tracker/src/core/platform/preferences.dart';
import 'package:expense_tracker/src/core/platform/update_status.dart';
import 'package:expense_tracker/src/features/settings/model/app_update.dart';
import 'package:expense_tracker/src/features/settings/model/platform_services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _sha = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';

/// A port that counts how often the internet is asked.
final class _Port implements UpdatePort {
  var fetched = 0;

  /// The newest published build.
  var build = 190;

  /// What asking fails with; null when it works.
  Exception? fails;

  /// Holds the answer back until completed, when set.
  Completer<void>? hold;

  @override
  Future<String> fetch(Uri url) async {
    fetched++;
    await hold?.future;
    if (fails case final error?) throw error;
    return '{"build":$build,"version":"2.0.0","sha256":"$_sha","size":3}';
  }

  @override
  Future<void> download(
    Uri url,
    File into,
    void Function(int received) progress, {
    required DownloadCancel cancel,
  }) async {}

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

  // F102: 檢查更新 used to leave the card as it was when nothing newer was
  // found, so a tap looked like nothing happened.
  group('檢查更新 always answers', () {
    late Directory cache;
    late _Port port;
    late AppUpdate update;

    Future<void> opened(WidgetTester tester, {int build = 190}) async {
      cache = Directory.systemTemp.createTempSync('about-check-');
      addTearDown(() => cache.deleteSync(recursive: true));
      port = _Port()..build = build;
      final preferences = Preferences();
      update = AppUpdate(port, preferences, cache: cache, build: 190);
      await open(
        tester,
        PlatformServices(preferences: preferences, update: update),
      );
      // Opening 關於 looked once by itself.
      expect(port.fetched, 1);
    }

    testWidgets('checking…, then up to date, on the card and in a note', (
      tester,
    ) async {
      await opened(tester);
      expect(find.text('已是最新版本'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      port.hold = Completer<void>();
      await tester.tap(find.byKey(Keys.checkUpdate));
      await tester.pump();
      expect(find.text('檢查中…'), findsOneWidget);
      // A second tap while it looks asks nothing more.
      await tester.tap(find.byKey(Keys.checkUpdate));
      await tester.pump();
      expect(port.fetched, 2);
      port.hold!.complete();
      await tester.pumpAndSettle();
      expect(port.fetched, 2);
      // The card, and the note that says the look was made.
      expect(find.text('已是最新版本'), findsNWidgets(2));
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text('已是最新版本'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a newer version found opens its panel', (tester) async {
      await opened(tester);
      port.build = 191;
      await tester.tap(find.byKey(Keys.checkUpdate));
      await tester.pumpAndSettle();
      expect(find.text('有新版 2.0.0'), findsOneWidget);
      expect(find.byKey(Keys.install), findsOneWidget);
    });

    testWidgets('no network says why, on the card and in a note', (
      tester,
    ) async {
      await opened(tester);
      port.fails = const SocketException('offline');
      await tester.tap(find.byKey(Keys.checkUpdate));
      await tester.pumpAndSettle();
      expect(find.text('連不上 GitHub，請稍後再試'), findsNWidgets(2));
      // Working again, the next tap says so.
      port.fails = null;
      await tester.tap(find.byKey(Keys.checkUpdate));
      await tester.pumpAndSettle();
      expect(find.text('連不上 GitHub，請稍後再試'), findsNothing);
      expect(find.text('已是最新版本'), findsNWidgets(2));
    });

    testWidgets('a build made by hand says so, and has nothing to tap', (
      tester,
    ) async {
      cache = Directory.systemTemp.createTempSync('about-check-');
      addTearDown(() => cache.deleteSync(recursive: true));
      port = _Port();
      final preferences = Preferences();
      update = AppUpdate(port, preferences, cache: cache, build: 0);
      await open(
        tester,
        PlatformServices(preferences: preferences, update: update),
      );
      expect(find.text('自行建置的版本'), findsOneWidget);
      await tester.tap(find.byKey(Keys.checkUpdate));
      await tester.pumpAndSettle();
      expect(port.fetched, 0);
      // Without the update service at all (the preview) it says the same.
      await open(tester, const PlatformServices());
      expect(find.text('自行建置的版本'), findsOneWidget);
    });
    // Sideload cases: skipped in the play build.
  }, skip: !canSelfUpdate);

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
      expect(update.status, isA<UpdateNotOffered>());
      // The card is there, with nothing to tap.
      await tester.tap(find.byKey(Keys.checkUpdate));
      await tester.pumpAndSettle();
      expect(port.fetched, 0);
      expect(find.byType(SnackBar), findsNothing);
      // D29: the card says who updates it, and nothing else of updates.
      expect(find.text('由 Google Play 更新'), findsOneWidget);
      for (final text in [
        '自動檢查新版本',
        '自行建置的版本',
        '點這裡檢查更新',
        '檢查中…',
        '已是最新版本',
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
