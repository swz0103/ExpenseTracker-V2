import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../core/preferences.dart';

/// A file in the chosen folder.
typedef FolderFile = ({String id, String name, DateTime modified});

/// A folder on the phone chosen once, which the app keeps writing into:
/// Android's folder chooser and its documents API; a fake in tests.
abstract interface class FolderPort {
  /// Opens the folder chooser; the folder's address and name, or null
  /// when the person cancels.
  Future<({String uri, String name})?> pick();

  /// Whether the app may still write into [uri]: the person can take the
  /// permission back.
  Future<bool> allowed(String uri);

  /// Gives the permission for [uri] back.
  Future<void> forget(String uri);
  Future<List<FolderFile>> list(String uri);
  Future<void> write(String uri, File file, String name);
  Future<void> delete(String uri, String id);
}

/// Backups to a folder on the phone, such as one in Documents that the
/// phone's own backup or a computer can copy: chosen once, then written
/// daily or weekly when the ledger changed, each with the receipt photos.
/// The newest [keep] are kept; the app only touches its own files there.
final class PhoneBackup extends ChangeNotifier {
  PhoneBackup(
    this._folder,
    this._preferences, {
    required Future<void> Function(Future<void> Function(File file) use)
    withBackup,
    required int Function() revision,
    DateTime Function()? clock,
  }) : _withBackup = withBackup,
       _revision = revision,
       _clock = clock ?? DateTime.now;

  final FolderPort _folder;
  final Preferences _preferences;
  final Future<void> Function(Future<void> Function(File file) use) _withBackup;
  final int Function() _revision;
  final DateTime Function() _clock;

  /// How many backups stay in the folder.
  static const keep = 5;

  /// The start and end of the names of the app's backups there.
  static const _prefix = '記帳本-';
  static const _suffix = '.etbk';

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
    final every = daily ? const Duration(days: 1) : const Duration(days: 7);
    if (last != null &&
        (_clock().difference(last) < every ||
            _preferences.phoneRevision == _revision())) {
      return false;
    }
    try {
      await _write();
      return true;
    } on Object catch (error) {
      _problem = '$error';
      notifyListeners();
      return false;
    }
  }

  /// The name of a backup taken at [at]: sorts by time.
  static String nameAt(DateTime at) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '$_prefix${at.year}${two(at.month)}${two(at.day)}'
        '-${two(at.hour)}${two(at.minute)}$_suffix';
  }

  Future<void> _write() async {
    final uri = _preferences.phoneFolder;
    if (uri == null || _busy) return;
    _busy = true;
    notifyListeners();
    try {
      if (!await _folder.allowed(uri)) {
        throw StateError('沒有這個資料夾的存取權，請重新選擇');
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

  /// Deletes the app's backups beyond the newest [keep]; other files in
  /// the folder are never touched.
  Future<void> _prune(String uri) async {
    final ours = [
      for (final file in await _folder.list(uri))
        if (file.name.startsWith(_prefix) && file.name.endsWith(_suffix)) file,
    ]..sort((a, b) => b.name.compareTo(a.name));
    for (final old in ours.skip(keep)) {
      await _folder.delete(uri, old.id);
    }
  }
}
