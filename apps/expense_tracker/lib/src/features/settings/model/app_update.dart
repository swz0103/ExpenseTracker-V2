import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../core/preferences.dart';

/// This build's number, set by the APK build (android.yml); 0 in a build
/// made by hand and in the preview, which never look for updates.
const currentBuild = int.fromEnvironment('APP_BUILD');

/// The newest published build, as `update.json` beside the APK on the
/// release `android-latest` says it (android.yml).
final class UpdateInfo {
  const UpdateInfo({
    required this.build,
    required this.version,
    required this.commit,
    required this.sha256,
    required this.size,
  });

  final int build;
  final String version;
  final String commit;

  /// The APK's SHA-256, checked before it is installed.
  final String sha256;

  /// The APK's size in bytes.
  final int size;

  /// Reads `update.json`; null for anything else.
  static UpdateInfo? parse(String text) {
    try {
      final json = jsonDecode(text);
      if (json is! Map<String, Object?>) return null;
      final build = json['build'];
      final sha256 = json['sha256'];
      final size = json['size'];
      if (build is! int ||
          size is! int ||
          sha256 is! String ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256)) {
        return null;
      }
      return UpdateInfo(
        build: build,
        version: json['version'] as String? ?? '',
        commit: json['commit'] as String? ?? '',
        sha256: sha256,
        size: size,
      );
    } on FormatException {
      return null;
    }
  }

  /// 「第 186 版（2.0.0 · 8af812b）」.
  String get label => [
    '第 $build 版',
    if (version.isNotEmpty || commit.isNotEmpty)
      '（${[version, commit].where((s) => s.isNotEmpty).join(' · ')}）',
  ].join();
}

/// What became of handing the APK to Android's installer.
enum UpdateInstall {
  /// Android's installer is open; the person confirms there.
  started,

  /// The app may not install apps yet: Android's setting for it was
  /// opened, to allow it and try again.
  needsPermission,

  /// The download does not match its SHA-256 and was deleted.
  damaged,
}

/// The internet and Android's installer; [IoUpdatePort] with the app's
/// channel on the phone, a fake in tests.
abstract interface class UpdatePort {
  Future<String> fetch(Uri url);

  /// Saves [url] into [into], saying how much has arrived.
  Future<void> download(
    Uri url,
    File into,
    void Function(int received) progress,
  );

  /// Checks [apk] against [sha256] and opens Android's installer with it.
  Future<UpdateInstall> install(File apk, String sha256);
}

/// Newer versions of the app, from the release the APKs are published on:
/// looked for by hand in 設定 › 關於, and once a day at most by itself
/// when allowed; downloaded, checked against their SHA-256 and handed to
/// Android's installer, where the person confirms. Nothing of the ledger
/// is sent: only the two files are fetched from GitHub.
final class AppUpdate extends ChangeNotifier {
  AppUpdate(
    this._port,
    this._preferences, {
    required Directory cache,
    int build = currentBuild,
    DateTime Function()? clock,
  }) : _cache = cache,
       _build = build,
       _clock = clock ?? DateTime.now;

  final UpdatePort _port;
  final Preferences _preferences;
  final Directory _cache;
  final int _build;
  final DateTime Function() _clock;

  static const _release =
      'https://github.com/swz0103/ExpenseTracker-V2/releases/download/android-latest';
  static final infoUrl = Uri.parse('$_release/update.json');
  static final apkUrl = Uri.parse('$_release/ExpenseTracker.apk');

  /// Whether this build can be updated: one built by hand cannot.
  bool get possible => _build > 0;

  /// The newer build found; null when none was, or not yet looked.
  UpdateInfo? get newer => _newer;
  UpdateInfo? _newer;

  /// Looked and found this build the newest.
  bool get upToDate => _upToDate;
  var _upToDate = false;

  bool get checking => _checking;
  var _checking = false;

  /// The share downloaded, 0 to 1, while downloading; null otherwise.
  double? get progress => _progress;
  double? _progress;

  /// What went wrong last; null when nothing did.
  String? get problem => _problem;
  String? _problem;

  bool get busy => _checking || _progress != null;

  /// Looks for a newer build. Returns it, or null when there is none or
  /// it could not tell ([problem] says why).
  Future<UpdateInfo?> check() async {
    if (!possible || busy) return null;
    _checking = true;
    _problem = null;
    notifyListeners();
    try {
      final info = UpdateInfo.parse(await _port.fetch(infoUrl));
      _preferences.updateChecked(_clock());
      if (info == null) {
        _problem = '更新資訊看不懂';
        return null;
      }
      _newer = info.build > _build ? info : null;
      _upToDate = _newer == null;
      return _newer;
    } on Object catch (error) {
      _problem = error is IOException || error is TimeoutException
          ? '連不上 GitHub，請稍後再試'
          : '$error';
      return null;
    } finally {
      _checking = false;
      notifyListeners();
    }
  }

  /// Looks once a day at most, when allowed.
  Future<UpdateInfo?> checkIfDue() async {
    if (!possible || !_preferences.updateChecks) return null;
    final last = _preferences.updateCheckedAt;
    if (last != null && _clock().difference(last) < const Duration(days: 1)) {
      return null;
    }
    return check();
  }

  /// Downloads the newer build, checks it and hands it to Android's
  /// installer. Null when there was nothing to install or it failed
  /// ([problem] says why).
  Future<UpdateInstall?> install() async {
    final info = _newer;
    if (info == null || busy) return null;
    _problem = null;
    _progress = 0;
    notifyListeners();
    final folder = Directory('${_cache.path}/updates');
    final apk = File('${folder.path}/ExpenseTracker-${info.build}.apk');
    try {
      await folder.create(recursive: true);
      if (!apk.existsSync() || apk.lengthSync() != info.size) {
        await _port.download(apkUrl, apk, (received) {
          _progress = info.size == 0
              ? 0
              : (received / info.size).clamp(0, 1).toDouble();
          notifyListeners();
        });
      }
      final outcome = await _port.install(apk, info.sha256);
      if (outcome == UpdateInstall.damaged) {
        _problem = '下載的檔案不完整，請再試一次';
      }
      return outcome;
    } on Object catch (error) {
      _problem = error is IOException || error is TimeoutException
          ? '下載中斷，請稍後再試'
          : '$error';
      if (apk.existsSync()) await apk.delete();
      return null;
    } finally {
      _progress = null;
      notifyListeners();
    }
  }
}
