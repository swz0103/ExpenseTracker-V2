import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../core/preferences.dart';
import 'drive_backup.dart';

/// Backups on the person's Google Drive: linked once with Google's
/// sign-in, then sent by hand from the settings and weekly by themselves
/// when the ledger changed. Each carries the receipt photos; the newest
/// five are kept.
final class DriveSync extends ChangeNotifier {
  DriveSync(
    this._drive,
    this._preferences, {
    required Future<void> Function(Future<void> Function(File file) use)
    withBackup,
    required int Function() revision,
    required String ledger,
    DateTime Function()? clock,
  }) : _withBackup = withBackup,
       _revision = revision,
       _ledger = ledger,
       _clock = clock ?? DateTime.now;

  final DriveBackup _drive;
  final Preferences _preferences;
  final Future<void> Function(Future<void> Function(File file) use) _withBackup;
  final int Function() _revision;

  /// The ledger's own id, marking its backups on Drive apart from those of
  /// another ledger kept in the same folder.
  final String _ledger;
  final DateTime Function() _clock;

  bool get linked => _preferences.driveLinked;
  DateTime? get backedUp => _preferences.driveBackedUp;

  /// A backup is going up. Shared by every [DriveSync] of this run, so a
  /// ledger locked and opened again while one goes up does not send a
  /// second.
  bool get busy => _busy;
  static var _busy = false;

  /// Signs in with Google's screens and sends a first backup. False when
  /// the person did not allow it.
  Future<bool> link() async {
    if (!await _drive.signIn()) return false;
    _preferences.update(driveLinked: true);
    await backUpNow();
    return true;
  }

  /// Stops sending backups; those on Drive stay there.
  Future<void> unlink() async {
    _preferences.update(driveLinked: false);
    await _drive.signOut();
    notifyListeners();
  }

  /// Sends a backup now, asking Google's screens when needed.
  Future<void> backUpNow() => _send(interactive: true);

  /// Sends a backup when linked, the last one is older than [every] and
  /// the ledger changed since; never shows Google's screens. True when one
  /// was sent.
  Future<bool> backUpIfDue({Duration every = const Duration(days: 7)}) async {
    if (!linked || _busy) return false;
    final last = backedUp;
    if (last != null &&
        (_clock().difference(last) < every ||
            _preferences.driveRevision == _revision())) {
      return false;
    }
    await _send(interactive: false);
    return true;
  }

  Future<void> _send({required bool interactive}) async {
    if (_busy) return;
    _busy = true;
    notifyListeners();
    try {
      final revision = _revision();
      await _withBackup(
        (file) =>
            _drive.upload(file, ledger: _ledger, interactive: interactive),
      );
      _preferences.driveBackup(_clock(), revision);
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
