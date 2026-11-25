import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../core/platform/preferences.dart';
import '../../../core/diagnostics/error_log.dart';
import '../../../core/diagnostics/error_steps.dart';
import '../../../core/time/app_clock.dart';
import '../../../core/messages/backup_messages.dart';
import 'backup_rules.dart';
import '../../../core/diagnostics/app_fault.dart';

/// The folder chosen cannot be kept: Android gave no lasting permission
/// for it, as for the storage's top or 下載 since Android 11.
final class FolderRejected implements AppFault {
  const FolderRejected();

  @override
  String toString() => '這個位置不能存備份';
}

/// A file in the chosen folder.
typedef FolderFile = ({String id, String name, DateTime modified});

/// How a backup's key epoch is read from its first bytes: how many to
/// read (`reach`), and the epoch they name (`epochIn`, which throws when
/// they are not a backup's start). `EncryptedBackupManager.head`.
typedef BackupHead = ({int reach, int Function(List<int> leading) epochIn});

/// A folder on the phone chosen once, which the app keeps writing into:
/// Android's folder chooser and its documents API; a fake in tests.
abstract interface class FolderPort {
  /// Opens the folder chooser at Documents; the folder's address and
  /// name, or null when the person cancels. Throws [FolderRejected] when
  /// the folder picked cannot be kept.
  Future<({String uri, String name})?> pick();

  /// Whether the app may still write into [uri]: the person can take the
  /// permission back.
  Future<bool> allowed(String uri);

  /// Gives the permission for [uri] back.
  Future<void> forget(String uri);
  Future<List<FolderFile>> list(String uri);
  Future<void> write(String uri, File file, String name);
  Future<void> delete(String uri, String id);

  /// The first bytes of file [id], at most [bytes] of them: enough to
  /// read a backup's header without copying the whole file.
  Future<List<int>> head(String uri, String id, int bytes);
}

/// Backups to a folder on the phone, such as one in Documents that the
/// phone's own backup or a computer can copy: chosen once, then written
/// daily or weekly when the ledger changed, each with the receipt photos.
/// The newest [BackupRules.keep] are kept; the app only touches its own
/// files there.
final class PhoneBackup extends ChangeNotifier {
  PhoneBackup(
    this._folder,
    this._preferences, {
    required this._withBackup,
    required this._revision,
    required String ledger,
    DateTime Function()? clock,
  }) : _mark = BackupRules.markOf(ledger),
       _clock = clock ?? AppClock.now;

  final FolderPort _folder;
  final Preferences _preferences;
  final Future<void> Function(Future<void> Function(File file) use) _withBackup;
  final int Function() _revision;
  final DateTime Function() _clock;

  /// The ledger's mark in its backups' names ([BackupRules.markOf]).
  final String _mark;

  bool get on => _preferences.phoneFolder != null;
  String get folderName => _preferences.phoneFolderName;
  bool get daily => _preferences.phoneDaily;
  DateTime? get backedUp => _preferences.phoneBackedUp;

  /// A backup is being written; shared by every [PhoneBackup] of the run.
  bool get busy => _busy;
  static var _busy = false;

  /// What went wrong with the last backup made by itself; null when it
  /// went well.
  String? get problem => _problem;
  String? _problem;

  /// Asks for a folder and writes a first backup into it. False when the
  /// person cancelled.
  Future<bool> choose() async {
    final picked = await _folder.pick();
    if (picked == null) return false;
    _preferences.phoneFolderSet(picked.uri, name: picked.name);
    await backUpNow();
    return true;
  }

  /// Stops; the backups in the folder stay.
  Future<void> stop() async {
    final uri = _preferences.phoneFolder;
    _preferences.phoneFolderSet(null);
    _problem = null;
    notifyListeners();
    if (uri != null) await _folder.forget(uri);
  }

  void setDaily(bool daily) => _preferences.update(phoneDaily: daily);

  /// Writes a backup now.
  Future<void> backUpNow() => _write();

  /// Writes a backup when one is due by the chosen rhythm and the ledger
  /// changed since the last. True when one was written; a failure is
  /// kept in [problem] rather than thrown.
  Future<bool> backUpIfDue() async {
    if (!on || _busy) return false;
    final last = backedUp;
    final every = BackupRules.phoneEvery(daily: daily);
    if (last != null &&
        (_clock().difference(last) < every ||
            _preferences.phoneRevision == _revision())) {
      return false;
    }
    try {
      await _write();
      return true;
    } on Object catch (error) {
      ErrorLog.instance.record('手機資料夾備份', error);
      // Exception to error words: kept for the log; the screen says only
      // that the last backup did not work (上次沒有成功).
      _problem = ErrorLog.describe(error);
      notifyListeners();
      return false;
    }
  }

  /// The name of this ledger's backup taken at [at]: sorts by time.
  String nameAt(DateTime at) => BackupRules.phoneName(_mark, at);

  Future<void> _write() async {
    final uri = _preferences.phoneFolder;
    if (uri == null || _busy) return;
    _busy = true;
    notifyListeners();
    try {
      if (!await _folder.allowed(uri)) {
        throw StateError(BackupWords.folderDenied);
      }
      final at = _clock();
      final revision = _revision();
      await _withBackup((file) => _folder.write(uri, file, nameAt(at)));
      _preferences.phoneBackup(at, revision);
      _problem = null;
      await _prune(uri);
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// This ledger's backups in the folder sealed before a reset of the
  /// keys at [at], newest first: those whose header, read by [head],
  /// names a key epoch before [epoch]. One whose header cannot be read is
  /// judged by the
  /// time in its name, and in the minute of [at] by when the file was
  /// written; a folder that gives no such time (0) keeps it out of the
  /// list. None when no folder is chosen.
  Future<List<FolderFile>> writtenBefore(
    DateTime at, {
    required int epoch,
    required BackupHead head,
  }) async {
    final uri = _preferences.phoneFolder;
    if (uri == null) return const [];
    final then = nameAt(at);
    return [
      for (final file in await _ours(uri))
        if (switch (await _epochOf(uri, file, head)) {
          final sealed? => sealed < epoch,
          null =>
            file.name.compareTo(then) < 0 ||
                (file.name == then &&
                    file.modified.millisecondsSinceEpoch > 0 &&
                    file.modified.isBefore(at)),
        })
          file,
    ];
  }

  /// The key epoch [file]'s header names; null when it cannot be read.
  Future<int?> _epochOf(String uri, FolderFile file, BackupHead head) async {
    try {
      return head.epochIn(await _folder.head(uri, file.id, head.reach));
    } on Object catch (error) {
      ErrorLog.instance.record(ErrorSteps.oldKeyBackups, error);
      return null;
    }
  }

  /// Deletes this ledger's backup [id] from the folder ([writtenBefore]).
  Future<void> remove(String id) async {
    final uri = _preferences.phoneFolder;
    if (uri == null) return;
    await _folder.delete(uri, id);
  }

  /// This ledger's backups in the folder, newest first.
  Future<List<FolderFile>> _ours(String uri) async => [
    for (final file in await _folder.list(uri))
      if (file.name.startsWith(BackupRules.phonePrefix(_mark)) &&
          file.name.endsWith(BackupRules.suffix))
        file,
  ]..sort((a, b) => b.name.compareTo(a.name));

  /// Deletes this ledger's backups beyond the newest [BackupRules.keep];
  /// other files
  /// in the folder, another ledger's backups among them, are never
  /// touched.
  Future<void> _prune(String uri) async {
    final ours = await _ours(uri);
    for (final old in ours.skip(BackupRules.keep)) {
      await _folder.delete(uri, old.id);
    }
  }
}
