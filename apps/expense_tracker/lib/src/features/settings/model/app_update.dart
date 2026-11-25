import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../core/messages/update_messages.dart';
import '../../../core/platform/bounded_https.dart';
import '../../../core/platform/distribution.dart';
import '../../../core/platform/preferences.dart';
import '../../../core/platform/update_status.dart';
import '../../../core/diagnostics/error_log.dart';
import '../../../core/time/app_clock.dart';
import '../../../core/formatting/json_fields.dart';
import '../../../core/platform/app_files.dart';

/// This build's number, set by the APK build (android.yml); 0 in a build
/// made by hand and in the preview, which never look for updates.
const currentBuild = int.fromEnvironment('APP_BUILD');

/// The newest published build, as `update.json` beside the APK on the
/// newest version's release, `v<version>`, says it (android.yml).
final class UpdateInfo {
  const UpdateInfo({
    required this.build,
    required this.version,
    required this.commit,
    required this.sha256,
    required this.size,
    this.notes = const [],
  });

  final int build;
  final String version;
  final String commit;

  /// The APK's SHA-256, checked before it is installed.
  final String sha256;

  /// The APK's size in bytes.
  final int size;

  /// What this version changes, a few short lines (whats_new.txt).
  final List<String> notes;

  /// 0.9.6: every published build has a version.
  String get name => version;

  /// Reads `update.json`; null for anything else.
  static UpdateInfo? parse(String text) {
    try {
      final json = jsonDecode(text);
      if (json is! Map<String, Object?>) return null;
      final build = json['build'];
      final sha256 = json['sha256'];
      final size = json['size'];
      final version = JsonFields(json).text('version') ?? '';
      // The APK is found by the version: a build without one has no
      // release to download from.
      if (build is! int ||
          !RegExp(r'^[0-9]+\.[0-9]+\.[0-9]+$').hasMatch(version) ||
          size is! int ||
          sha256 is! String ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256)) {
        return null;
      }
      return UpdateInfo(
        build: build,
        version: version,
        commit: JsonFields(json).text('commit') ?? '',
        sha256: sha256,
        size: size,
        notes: [
          if (json['notes'] case final List<Object?> lines)
            for (final line in lines)
              if (line is String && line.trim().isNotEmpty) line.trim(),
        ],
      );
    } on FormatException {
      // A feed that cannot be read says nothing new.
      return null;
    }
  }

  /// 「第 186 版（2.0.0 · 8af812b）」.
  String get label =>
      '第 $build 版（${[version, commit].where((s) => s.isNotEmpty).join(' · ')}）';
}

/// What became of handing the APK to Android's installer.
enum UpdateInstall {
  /// Android's installer is open; the person confirms there.
  started,

  /// The app may not install apps yet: Android's setting for it was
  /// opened, to allow it and try again.
  needsPermission,

  /// The download does not match its SHA-256, is larger than allowed or
  /// cannot be read as an APK, and was deleted.
  damaged,

  /// The file is an APK, but not a newer version of this app signed with
  /// the same key (its package name, version code or signing certificate
  /// differ), and was deleted: it is not installed.
  rejected,
}

/// The most an update may weigh, in bytes: the APK is about 28 MB, so
/// 150 MiB stops a download that fills the phone. Checked before it is
/// downloaded (against `update.json`'s size), while it arrives, and again
/// by Android's side before it is installed (UpdateGate.kt, which is told
/// this number with the file).
const maxApkBytes = 150 * 1024 * 1024;

/// The most `update.json` may weigh, in bytes: it is a few hundred bytes,
/// and it is read at every opening, so a huge answer must not fill the
/// phone's memory.
const maxUpdateInfoBytes = 64 * 1024;

/// The internet and Android's installer; `AndroidUpdatePort` with the app's
/// channel on the phone, a fake in tests.
abstract interface class UpdatePort {
  Future<String> fetch(Uri url);

  /// Saves [url] into [into], saying how much has arrived. When [cancel]
  /// is asked, the transfer stops at once, even while nothing arrives
  /// (the connection is closed), and what had arrived is deleted; it
  /// returns or throws only once it has stopped.
  Future<void> download(
    Uri url,
    File into,
    void Function(int received) progress, {
    required DownloadCancel cancel,
  });

  /// Checks [apk] (its size, [sha256], its package name, version code and
  /// signing certificate against the running app's) and opens Android's
  /// installer with it.
  Future<UpdateInstall> install(File apk, String sha256);
}

/// Asks a download under way to stop ([UpdatePort.download]).
final class DownloadCancel {
  final _asked = Completer<void>();

  /// Whether stopping was asked.
  bool get asked => _asked.isCompleted;

  /// Completes when stopping is asked.
  Future<void> get whenAsked => _asked.future;

  void ask() {
    if (!asked) _asked.complete();
  }
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
    required this._cache,
    this._build = currentBuild,
    DateTime Function()? clock,
  }) : _clock = clock ?? AppClock.now;

  final UpdatePort _port;
  final Preferences _preferences;
  final Directory _cache;
  final int _build;
  final DateTime Function() _clock;

  static const _releases =
      'https://github.com/swz0103/ExpenseTracker-V2/releases';

  /// `update.json` on the release GitHub marks the latest: each version
  /// has a release of its own, `v<version>`.
  static final infoUrl = Uri.parse('$_releases/latest/download/update.json');

  /// The APK of [version], on that version's release.
  static Uri apkUrl(String version) =>
      Uri.parse('$_releases/download/v$version/ExpenseTracker-$version.apk');

  /// Whether this build can be updated: one built by hand cannot, nor
  /// can the play build (distribution.dart).
  bool get possible => canSelfUpdate && _build > 0;

  /// The newer build found; null when none was, or not yet looked.
  UpdateInfo? get newer => _newer;
  UpdateInfo? _newer;

  /// Looked and found this build the newest.
  bool get upToDate => _upToDate;
  var _upToDate = false;

  /// Looking for a newer build now.
  var _checking = false;

  /// The share downloaded, 0 to 1, while downloading; null otherwise.
  double? get progress => _progress;
  double? _progress;

  /// Why the last look or download did not work; null when it did.
  UpdateFailure? get failure => _failure;
  UpdateFailure? _failure;

  /// [failure] in words; null when nothing went wrong.
  String? get problem => switch (_failure) {
    final failure? => UpdateMessages.failure(failure),
    null => null,
  };

  bool get busy => _checking || _progress != null;

  /// How this build stands against the newest, for 關於 to say: always
  /// one answer, whatever was or was not found.
  UpdateStatus get status {
    if (!canSelfUpdate) return const UpdateNotOffered();
    if (_build <= 0) return const UpdateHandBuilt();
    if (_progress case final share?) return UpdateDownloading(share);
    if (_checking) return const UpdateChecking();
    if (_newer case final newer?) return UpdateAvailable(newer.version);
    if (_failure case final failure?) return UpdateFailed(failure);
    if (_upToDate) return const UpdateCurrent();
    return const UpdateNotLooked();
  }

  /// Looks for a newer build. Returns it, or null when there is none or
  /// it could not tell ([failure] says why). Whatever happens, [status]
  /// has the answer afterwards.
  Future<UpdateInfo?> check() async {
    if (!possible || busy) return null;
    _checking = true;
    _failure = null;
    notifyListeners();
    try {
      final info = UpdateInfo.parse(await _port.fetch(infoUrl));
      _preferences.updateChecked(_clock());
      _lookedThisRun = true;
      if (info == null) {
        ErrorLog.instance.record(
          UpdateMessages.checkStep,
          const FormatException('update.json is not an update feed'),
        );
        _failure = UpdateFailure.unreadableFeed;
        return null;
      }
      _newer = info.build > _build ? info : null;
      _upToDate = _newer == null;
      return _newer;
    } on Object catch (error, stack) {
      ErrorLog.instance.record(UpdateMessages.checkStep, error, stack);
      _failure = switch (error) {
        HttpException() => UpdateFailure.refused,
        IOException() || TimeoutException() => UpdateFailure.offline,
        _ => UpdateFailure.checkUnforeseen,
      };
      return null;
    } finally {
      _checking = false;
      notifyListeners();
    }
  }

  /// Looks by itself each time the app is opened or come back to (not
  /// again within ten minutes), when allowed. One small file from GitHub.
  Future<UpdateInfo?> checkIfDue() async {
    if (!possible || !_preferences.updateChecks) return null;
    return checkIfOlder(const Duration(minutes: 10));
  }

  /// Looks unless it did within [age], as on opening 設定 › 關於, where the
  /// version shown should be the one there is now.
  Future<UpdateInfo?> checkIfOlder(Duration age) async {
    final last = _preferences.updateCheckedAt;
    // Only a look made this run counts: the answer of one before a restart
    // is not kept, and a newer version would go unsaid until [age] passed.
    if (_lookedThisRun && last != null && _clock().difference(last) < age) {
      return _newer;
    }
    return check();
  }

  var _lookedThisRun = false;

  /// Whether [info] may be offered on its own, on opening the app: not
  /// while put off with 晚一點再說, nor when 略過這一版 passed it over.
  bool mayOffer(UpdateInfo info) {
    final until = _preferences.updateLaterUntil;
    if (until != null && _clock().isBefore(until)) return false;
    return _preferences.updateSkipped != info.build;
  }

  /// 晚一點再說: not offered again on its own until tomorrow.
  void later() {
    final now = _clock().toLocal();
    _preferences.updateLater(until: DateTime(now.year, now.month, now.day + 1));
  }

  /// 略過這一版: offered again on its own only when a newer build comes.
  void skip(UpdateInfo info) => _preferences.updateLater(skip: info.build);

  /// Stops the download under way ([cancelDownload]); null when none is,
  /// and once the file has arrived and is being handed to the installer.
  DownloadCancel? _cancel;

  /// Completes when the [install] under way has ended.
  Completer<void>? _ended;

  /// Whether the download under way can still be stopped: 取消下載 shows
  /// only then, not once it is asked nor once the file is complete.
  bool get canCancel => !(_cancel?.asked ?? true);

  /// Stops the download under way (D85): the transfer is told to stop,
  /// and this completes once it has, what had arrived deleted, [install]
  /// returned null with no [failure] and [busy] false. Only then can the
  /// download be started again, so two never write one file (review 31).
  /// Once the file is complete and handed to the installer, it is too
  /// late: nothing is stopped.
  Future<void> cancelDownload() async {
    final cancel = _cancel;
    if (cancel == null || cancel.asked) return _ended?.future;
    cancel.ask();
    notifyListeners();
    await _ended?.future;
  }

  /// Downloads the newer build, checks it and hands it to Android's
  /// installer. Null when there was nothing to install, it was cancelled
  /// ([cancelDownload]) or it failed ([failure] says why).
  Future<UpdateInstall?> install() async {
    final info = _newer;
    if (info == null || busy) return null;
    _failure = null;
    _progress = 0;
    notifyListeners();
    if (info.size > maxApkBytes) {
      // Not even started: nothing this large is an update of this app.
      _failure = UpdateFailure.absurdSize;
      _progress = null;
      notifyListeners();
      return null;
    }
    final folder = Directory('${_cache.path}/${AppFiles.updates}');
    final apk = File('${folder.path}/ExpenseTracker-${info.build}.apk');
    final ended = _ended = Completer<void>();
    final cancel = _cancel = DownloadCancel();
    try {
      await folder.create(recursive: true);
      if (!apk.existsSync() || apk.lengthSync() != info.size) {
        // Waited for to its end, cancelled or not: a new download starts
        // only once this one has stopped writing.
        await _port.download(apkUrl(info.version), apk, (received) {
          if (cancel.asked) throw const _DownloadCancelled();
          // More than update.json says it weighs: stopped, not saved.
          if (received > info.size) throw const _OversizedDownload();
          _progress = info.size == 0
              ? 0
              : (received / info.size).clamp(0, 1).toDouble();
          notifyListeners();
        }, cancel: cancel);
      }
      if (cancel.asked) {
        // The person stopped it: nothing went wrong, nothing to say.
        if (apk.existsSync()) await apk.delete();
        return null;
      }
      // Complete: too late to stop, 取消下載 goes.
      _cancel = null;
      notifyListeners();
      final outcome = await _port.install(apk, info.sha256);
      if (outcome == UpdateInstall.damaged) {
        _failure = UpdateFailure.damaged;
      } else if (outcome == UpdateInstall.rejected) {
        _failure = UpdateFailure.notThisApp;
      }
      return outcome;
    } on Object catch (error, stack) {
      if (apk.existsSync()) await apk.delete();
      // Stopped as asked: whatever the transfer ended with is the stop's,
      // and nothing went wrong.
      if (cancel.asked) return null;
      if (error is _OversizedDownload) {
        ErrorLog.instance.record(
          UpdateMessages.downloadStep,
          UpdateMessages.grewPastSize,
        );
        _failure = UpdateFailure.grewPastSize;
        return null;
      }
      ErrorLog.instance.record(UpdateMessages.downloadStep, error, stack);
      // A cap or a redirect refused is not the network: said before the
      // IOException they are.
      _failure = switch (error) {
        AnswerTooLarge() => UpdateFailure.grewPastSize,
        RedirectRefused() => UpdateFailure.refused,
        IOException() || TimeoutException() => UpdateFailure.downloadCut,
        _ => UpdateFailure.installUnforeseen,
      };
      return null;
    } finally {
      _cancel = null;
      _progress = null;
      notifyListeners();
      ended.complete();
    }
  }
}

/// A download the person stopped ([AppUpdate.cancelDownload]).
final class _DownloadCancelled implements Exception {
  const _DownloadCancelled();
}

/// A download that went past the size `update.json` gave for it.
final class _OversizedDownload implements Exception {
  const _OversizedDownload();
}
