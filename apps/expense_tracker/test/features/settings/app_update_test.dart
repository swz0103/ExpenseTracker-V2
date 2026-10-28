import 'dart:io';

import 'package:expense_tracker/src/core/preferences.dart';
import 'package:expense_tracker/src/features/settings/model/app_update.dart';
import 'package:flutter_test/flutter_test.dart';

const _sha = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';

/// GitHub and Android's installer, in memory.
final class _Port implements UpdatePort {
  var info = '{"build":190,"version":"2.0.0","commit":"8af812b",'
      '"sha256":"$_sha","size":3}';
  Object? fails;
  var fetched = 0;
  var downloads = 0;
  var outcome = UpdateInstall.started;
  final installed = <(String, String)>[];

  @override
  Future<String> fetch(Uri url) async {
    fetched++;
    if (fails case final error?) throw error;
    expect(url, AppUpdate.infoUrl);
    return info;
  }

  @override
  Future<void> download(
    Uri url,
    File into,
    void Function(int received) progress,
  ) async {
    downloads++;
    expect(url, AppUpdate.apkUrl);
    into.writeAsStringSync('abc');
    progress(3);
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
    final same = update(build: 190);
    expect(await same.check(), isNull);
    expect(same.upToDate, isTrue);
  });

  test('a build made by hand never looks', () async {
    final none = update(build: 0);
    expect(none.possible, isFalse);
    expect(await none.check(), isNull);
    expect(port.fetched, 0);
  });

  test('by itself it looks once a day at most, and only when allowed', () async {
    final app = update();
    expect(await app.checkIfDue(), isNotNull);
    now = now.add(const Duration(hours: 23));
    expect(await app.checkIfDue(), isNull);
    now = now.add(const Duration(hours: 2));
    expect(await app.checkIfDue(), isNotNull);
    expect(port.fetched, 2);
    preferences.update(updateChecks: false);
    now = now.add(const Duration(days: 2));
    expect(await app.checkIfDue(), isNull);
    expect(port.fetched, 2);
  });

  test('anything but update.json, or no network, finds nothing', () async {
    port.info = '<html>not found</html>';
    final app = update();
    expect(await app.check(), isNull);
    expect(app.problem, isNotNull);
    port
      ..info = '{"build":190,"sha256":"short","size":3}'
      ..fails = null;
    expect(await app.check(), isNull);
    port.fails = const SocketException('offline');
    expect(await app.check(), isNull);
    expect(app.problem, '連不上 GitHub，請稍後再試');
  });

  test('the newer build is downloaded once and handed over with its hash',
      () async {
    final app = update();
    await app.check();
    expect(await app.install(), UpdateInstall.started);
    expect(port.installed, [('ExpenseTracker-190.apk', _sha)]);
    expect(app.progress, isNull);
    // Allowed only now: the same file is handed over again.
    expect(await app.install(), UpdateInstall.started);
    expect(port.downloads, 1);
  });

  test('a damaged download says so', () async {
    final app = update();
    await app.check();
    port.outcome = UpdateInstall.damaged;
    expect(await app.install(), UpdateInstall.damaged);
    expect(app.problem, '下載的檔案不完整，請再試一次');
  });
}
