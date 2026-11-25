import 'dart:async';
import 'dart:io';

import 'package:expense_tracker/src/core/diagnostics/error_log.dart';
import 'package:expense_tracker/src/core/platform/bounded_https.dart';
import 'package:expense_tracker/src/core/platform/preferences.dart';
import 'package:expense_tracker/src/core/platform/update_status.dart';
import 'package:expense_tracker/src/features/settings/model/app_update.dart';
import 'package:flutter_test/flutter_test.dart';

const _sha = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';

/// GitHub and Android's installer, in memory.
final class _Port implements UpdatePort {
  var info =
      '{"build":190,"version":"2.0.0","commit":"8af812b",'
      '"sha256":"$_sha","size":3}';
  Exception? fails;

  /// What the download fails with; null when it works.
  Exception? downloadFails;
  var fetched = 0;
  var downloads = 0;
  Uri? downloadedFrom;
  var outcome = UpdateInstall.started;

  /// The size the fake download reports as received.
  var reports = 3;

  /// Holds the download after its first piece until completed, as a
  /// stalled network does.
  Completer<void>? hold;

  /// Holds a cancelled download's unwinding until completed: the real
  /// port's connection closing takes a moment.
  Completer<void>? unwind;

  /// Completed once a held download's first piece has arrived, so a test
  /// waits for that step itself rather than for time to pass.
  var arrived = Completer<void>();

  /// Each transfer's end, in order.
  final events = <String>[];
  final installed = <(String, String)>[];

  @override
  Future<String> fetch(Uri url) async {
    fetched++;
    if (fails case final error?) throw error;
    expect(
      url,
      Uri.parse(
        'https://github.com/swz0103/ExpenseTracker-V2/releases/latest/download/update.json',
      ),
    );
    return info;
  }

  @override
  Future<void> download(
    Uri url,
    File into,
    void Function(int received) progress, {
    required DownloadCancel cancel,
  }) async {
    final n = ++downloads;
    if (downloadFails case final error?) throw error;
    downloadedFrom = url;
    // As AndroidUpdatePort: written to a part file, renamed when whole,
    // the part deleted however it ends.
    final part = File('${into.path}.part');
    try {
      part.writeAsStringSync('abc');
      if (hold case final held?) {
        progress(1);
        if (!arrived.isCompleted) arrived.complete();
        // Stopping closes the connection, which ends the wait.
        await Future.any([held.future, cancel.whenAsked]);
        if (cancel.asked) {
          await unwind?.future;
          throw const SocketException('Connection closed');
        }
      }
      progress(reports);
      await part.rename(into.path);
      events.add('download $n done');
    } finally {
      if (part.existsSync()) {
        part.deleteSync();
        events.add('download $n deleted its part');
      }
    }
  }

  @override
  Future<UpdateInstall> install(File apk, String sha256) async {
    installed.add((apk.uri.pathSegments.last, sha256));
    return outcome;
  }
}

void main() {
  late Directory cache;
  late _Port port;
  late Preferences preferences;
  late DateTime now;

  setUp(() {
    cache = Directory.systemTemp.createTempSync('app-update-');
    port = _Port();
    preferences = Preferences();
    now = DateTime.utc(2026, 10, 28, 9);
  });
  tearDown(() => cache.deleteSync(recursive: true));

  AppUpdate update({int build = 186}) => AppUpdate(
    port,
    preferences,
    cache: cache,
    build: build,
    clock: () => now,
  );

  test('a newer build is found, the same one is not', () async {
    final found = await update().check();
    expect(found?.build, 190);
    expect(found?.label, '第 190 版（2.0.0 · 8af812b）');
    expect(found?.name, '2.0.0');
    expect(found?.notes, isEmpty);
    port.info =
        '{"build":191,"version":"2.0.1","sha256":"$_sha","size":3,'
        '"notes":["雲端硬碟可以只備份帳本"," ",3]}';
    final noted = await update().check();
    expect(noted?.notes, ['雲端硬碟可以只備份帳本']);
    final same = update(build: 191);
    expect(await same.check(), isNull);
    expect(same.upToDate, isTrue);
  });

  test('a build made by hand never looks', () async {
    final none = update(build: 0);
    expect(none.possible, isFalse);
    expect(await none.check(), isNull);
    expect(port.fetched, 0);
  });

  test('by itself it looks on each opening, not again within ten minutes, '
      'and only when allowed', () async {
    final app = update();
    expect(await app.checkIfDue(), isNotNull);
    now = now.add(const Duration(minutes: 5));
    expect(await app.checkIfDue(), isNotNull, reason: 'the one found');
    expect(port.fetched, 1);
    now = now.add(const Duration(minutes: 6));
    expect(await app.checkIfDue(), isNotNull);
    expect(port.fetched, 2);
    // 關於 looks again after ten minutes, even with the checks off.
    preferences.update(updateChecks: false);
    now = now.add(const Duration(minutes: 5));
    await app.checkIfOlder(const Duration(minutes: 10));
    expect(port.fetched, 2);
    now = now.add(const Duration(minutes: 6));
    await app.checkIfOlder(const Duration(minutes: 10));
    expect(port.fetched, 3);
    now = now.add(const Duration(days: 2));
    expect(await app.checkIfDue(), isNull);
    expect(port.fetched, 3);
  });

  test(
    'a restart within ten minutes looks again: the answer is not kept',
    () async {
      expect(await update().checkIfDue(), isNotNull);
      now = now.add(const Duration(minutes: 2));
      expect(await update().checkIfDue(), isNotNull, reason: 'a new run');
      expect(port.fetched, 2);
    },
  );

  test('anything but update.json, or no network, finds nothing', () async {
    port.info = '<html>not found</html>';
    final app = update();
    expect(await app.check(), isNull);
    expect(app.problem, isNotNull);
    port
      ..info = '{"build":190,"sha256":"short","size":3}'
      ..fails = null;
    expect(await app.check(), isNull);
    // Without a version there is no release to download from.
    port.info = '{"build":190,"sha256":"$_sha","size":3}';
    expect(await app.check(), isNull);
    port.fails = const SocketException('offline');
    expect(await app.check(), isNull);
    expect(app.problem, '連不上 GitHub，請稍後再試');
  });

  // F102: there is always one answer to give, and a failure says why in
  // words rather than as the error's own text.
  group('how the build stands', () {
    test('not looked, looking, then the newest', () async {
      final app = update(build: 190);
      expect(app.status, isA<UpdateNotLooked>());
      final seen = <UpdateStatus>[];
      app.addListener(() => seen.add(app.status));
      await app.check();
      expect(seen.first, isA<UpdateChecking>());
      expect(seen.last, isA<UpdateCurrent>());
      expect(app.status, isA<UpdateCurrent>());
    });

    test('a newer version, by its number', () async {
      final app = update();
      await app.check();
      expect((app.status as UpdateAvailable).version, '2.0.0');
    });

    test('a build made by hand', () {
      expect(update(build: 0).status, isA<UpdateHandBuilt>());
    });

    test(
      'each way of failing is told apart and kept in the error log',
      () async {
        final app = update();
        Future<(UpdateFailure, String?, String)> failing() async {
          final before = ErrorLog.instance.count;
          expect(await app.check(), isNull);
          expect(ErrorLog.instance.count, before + 1);
          return (
            (app.status as UpdateFailed).failure,
            app.problem,
            ErrorLog.instance.entries.first.$2,
          );
        }

        port.fails = const SocketException('offline');
        expect(await failing(), (
          UpdateFailure.offline,
          '連不上 GitHub，請稍後再試',
          '檢查更新：SocketException: SocketException: offline',
        ));
        port.fails = TimeoutException('slow');
        expect((await failing()).$1, UpdateFailure.offline);
        port.fails = const HttpException('GitHub answered 404');
        expect(await failing(), (
          UpdateFailure.refused,
          'GitHub 現在沒有提供更新資訊，請稍後再試',
          '檢查更新：HttpException: HttpException: GitHub answered #',
        ));
        port.fails = const FormatException('odd');
        expect(await failing(), (
          UpdateFailure.checkUnforeseen,
          '檢查更新時發生未預期的錯誤，已記在診斷，請稍後再試',
          '檢查更新：FormatException: FormatException: odd',
        ));
        port
          ..fails = null
          ..info = '<html>not found</html>';
        expect(await failing(), (
          UpdateFailure.unreadableFeed,
          '更新資訊看不懂',
          '檢查更新：FormatException: FormatException: update.json is not an '
              'update feed',
        ));
        // Working again, the failure is gone.
        port.info = '{"build":186,"version":"2.0.0","sha256":"$_sha","size":3}';
        await app.check();
        expect(app.status, isA<UpdateCurrent>());
        expect(app.problem, isNull);
      },
    );

    test('a download cut short says so, and the newer version still '
        'stands', () async {
      final app = update();
      await app.check();
      port.downloadFails = const SocketException('cut');
      expect(await app.install(), isNull);
      expect(app.failure, UpdateFailure.downloadCut);
      expect(app.problem, '下載中斷，請稍後再試');
      expect(app.status, isA<UpdateAvailable>());
      port.downloadFails = const FormatException('odd');
      expect(await app.install(), isNull);
      expect(app.failure, UpdateFailure.installUnforeseen);
      expect(app.problem, '更新時發生未預期的錯誤，已記在診斷，請稍後再試');
    });

    test('an answer past the cap or a redirect refused is not said as the '
        'network, looking or downloading (review 27 finding 4)', () async {
      final app = update();
      final apk = Uri.parse('https://github.com/x.apk');
      port.fails = AnswerTooLarge(65536, apk);
      expect(await app.check(), isNull);
      expect(app.failure, UpdateFailure.refused);
      port.fails = RedirectRefused(Uri.parse('https://elsewhere.example/'));
      expect(await app.check(), isNull);
      expect(app.failure, UpdateFailure.refused);
      port.fails = null;
      await app.check();
      port.downloadFails = AnswerTooLarge(157286400, apk);
      expect(await app.install(), isNull);
      expect(app.failure, UpdateFailure.grewPastSize);
      expect(app.problem, '下載的檔案比預期大，已中止');
      port.downloadFails = RedirectRefused(
        Uri.parse('https://elsewhere.example/x.apk'),
      );
      expect(await app.install(), isNull);
      expect(app.failure, UpdateFailure.refused);
      expect(app.status, isA<UpdateAvailable>());
    });

    test('while it downloads, how far it is', () async {
      final app = update();
      await app.check();
      final seen = <UpdateStatus>[];
      app.addListener(() => seen.add(app.status));
      await app.install();
      // 3 of 3 bytes arrived: all of it.
      expect(seen.whereType<UpdateDownloading>().last.share, 1);
    });
  });

  test(
    'the newer build is downloaded once and handed over with its hash',
    () async {
      final app = update();
      await app.check();
      expect(await app.install(), UpdateInstall.started);
      expect(port.installed, [('ExpenseTracker-190.apk', _sha)]);
      // From the version's own release, never a moving one.
      expect(
        port.downloadedFrom,
        Uri.parse(
          'https://github.com/swz0103/ExpenseTracker-V2/releases/download/'
          'v2.0.0/ExpenseTracker-2.0.0.apk',
        ),
      );
      expect(app.progress, isNull);
      // Allowed only now: the same file is handed over again.
      expect(await app.install(), UpdateInstall.started);
      expect(port.downloads, 1);
    },
  );

  test('a damaged download says so', () async {
    final app = update();
    await app.check();
    port.outcome = UpdateInstall.damaged;
    expect(await app.install(), UpdateInstall.damaged);
    expect(app.problem, '下載的檔案不完整，請再試一次');
  });

  test('an update that is not this app says so', () async {
    final app = update();
    await app.check();
    port.outcome = UpdateInstall.rejected;
    expect(await app.install(), UpdateInstall.rejected);
    expect(app.problem, contains('不會安裝'));
  });

  test('an update of an absurd size is not downloaded', () async {
    // 157286400 = 150 * 1024 * 1024; the feed says one byte more.
    expect(maxApkBytes, 157286400);
    port.info =
        '{"build":190,"version":"2.0.0","sha256":"$_sha","size":157286401}';
    final app = update();
    await app.check();
    expect(await app.install(), isNull);
    expect(port.downloads, 0);
    expect(app.problem, '更新檔大小不合理，已取消下載');
  });

  test('a download that grows past its announced size is stopped', () async {
    final app = update();
    await app.check();
    // update.json says 3 bytes; the stream reports 4.
    port.reports = 4;
    expect(await app.install(), isNull);
    expect(port.installed, isEmpty);
    expect(app.problem, '下載的檔案比預期大，已中止');
    expect(
      File('${cache.path}/updates/ExpenseTracker-190.apk').existsSync(),
      isFalse,
    );
  });

  test('D85: a download under way can be cancelled: nothing is installed '
      'and nothing is said to have gone wrong', () async {
    final app = update();
    await app.check();
    final held = port.hold = Completer<void>();
    final installing = app.install();
    await port.arrived.future;
    // 1 of 3 bytes arrived.
    expect(app.progress, closeTo(0.333, 0.001));
    await app.cancelDownload();
    expect(await installing, isNull);
    expect(app.problem, isNull);
    expect(app.progress, isNull);
    expect(port.installed, isEmpty);
    expect(port.events, ['download 1 deleted its part']);
    held.complete();
    await pumpEventQueue();
    expect(port.installed, isEmpty);
    // And it can be started again.
    port.hold = null;
    expect(await app.install(), UpdateInstall.started);
  });

  test('review 31: cancelled while the network stalls, 更新 again waits '
      'for the first transfer to stop, and the retry is installed', () async {
    final app = update();
    await app.check();
    port.hold = Completer<void>();
    final unwind = port.unwind = Completer<void>();
    final first = app.install();
    await port.arrived.future;
    expect(app.canCancel, isTrue);
    final cancelling = app.cancelDownload();
    // Asked, not yet stopped: busy, 取消下載 gone, 更新 does nothing.
    expect(app.canCancel, isFalse);
    expect(app.busy, isTrue);
    expect(await app.install(), isNull);
    expect(port.downloads, 1, reason: 'never two transfers on one file');
    unwind.complete();
    await cancelling;
    expect(await first, isNull);
    expect(app.busy, isFalse);
    expect(app.problem, isNull);
    // The network is back: the retry downloads whole and is installed.
    port.hold = null;
    expect(await app.install(), UpdateInstall.started);
    expect(port.downloads, 2);
    expect(port.events, ['download 1 deleted its part', 'download 2 done']);
    expect(port.installed, [('ExpenseTracker-190.apk', _sha)]);
  });

  test('review 31: once the file is complete, 取消下載 goes and stops '
      'nothing: the installer opens', () async {
    final app = update();
    await app.check();
    final canCancel = <bool>[];
    app.addListener(() => canCancel.add(app.canCancel));
    expect(await app.install(), UpdateInstall.started);
    // While downloading it could be stopped; complete, it could not.
    expect(canCancel, containsAllInOrder([true, false]));
    expect(canCancel.last, isFalse);
    // Nothing under way: asking stops nothing.
    await app.cancelDownload();
    expect(port.installed, hasLength(1));
  });
}
