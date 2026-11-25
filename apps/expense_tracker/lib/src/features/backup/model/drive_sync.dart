import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../core/diagnostics/error_log.dart';
import '../../../core/messages/backup_messages.dart';
import '../../../core/platform/preferences.dart';
import 'drive_backup.dart';
import '../../../core/time/app_clock.dart';
import 'backup_rules.dart';

/// Backups on the person's Google Drive: linked once with Google's
/// sign-in, then sent by hand from the settings and daily by themselves
/// when the ledger changed. Each carries the ledger, and the receipt
/// photos only when asked ([photos]); the newest five are kept.
final class DriveSync extends ChangeNotifier {
  DriveSync(
    this._drive,
    this._preferences, {
    required this._withBackup,
    required this._revision,
    required this._ledger,
    this._epoch,
    this._unmetered,
    DateTime Function()? clock,
  }) : _clock = clock ?? AppClock.now;

  final DriveBackup _drive;
  final Preferences _preferences;
  final Future<void> Function(
    Future<void> Function(File file) use, {
    bool withPhotos,
  })
  _withBackup;
  final int Function() _revision;

  /// The ledger's own id, marking its backups on Drive apart from those of
  /// another ledger kept in the same folder.
  final String _ledger;

  /// The backup key epoch the backups are sealed with now, marking each
  /// on Drive so those of keys since replaced can be found (D15).
  final int Function()? _epoch;

  /// Whether the phone is on Wi-Fi: a backup with the photos carries
  /// every one, so it waits for one rather than spend mobile data.
  final Future<bool> Function()? _unmetered;
  final DateTime Function() _clock;

  bool get linked => _preferences.driveLinked;

  /// The Google account the backups go to; null until Drive has said.
  String? get account => _preferences.driveAccount;
  DateTime? get backedUp => _preferences.driveBackedUp;

  /// The backups carry the receipt photos too.
  bool get photos => _preferences.drivePhotos;

  /// Backups with the photos wait for Wi-Fi ([Preferences.photosOnWifi]).
  bool get photosOnWifi => _preferences.photosOnWifi;

  /// Lets backups with the photos go up on any network, or only on Wi-Fi.
  void setPhotosOnWifi(bool on) {
    _preferences.update(photosOnWifi: on);
    notifyListeners();
  }

  /// Adds the photos to the backups, sending one with them now, or
  /// leaves them out from the next one.
  Future<void> setPhotos(bool on) async {
    _preferences.update(drivePhotos: on);
    notifyListeners();
    if (on && linked) await backUpNow();
  }

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
    await _learnAccount(interactive: true);
    await backUpNow();
    return true;
  }

  /// Stops sending backups; those on Drive stay there.
  Future<void> unlink() async {
    _preferences.update(driveLinked: false);
    _preferences.driveAccountIs(null);
    await _drive.signOut();
    notifyListeners();
  }

  /// This ledger's backups on Drive, newest first; never shows Google's
  /// screens.
  Future<List<DriveFile>> backups() =>
      _drive.list(interactive: false, ledger: _ledger);

  /// Moves the backup [id] to the Drive trash.
  Future<void> trash(String id) => _drive.trash(id, interactive: false);

  /// Sends a backup now, asking Google's screens when needed.
  Future<void> backUpNow() => _send(interactive: true);

  /// Sends a backup when linked, the last one is older than [every] and
  /// the ledger changed since, on Wi-Fi when it carries the photos; never
  /// shows Google's screens. True when one was sent.
  Future<bool> backUpIfDue({Duration every = BackupRules.drive}) async {
    if (!linked || _busy) return false;
    final last = backedUp;
    if (last != null &&
        (_clock().difference(last) < every ||
            _preferences.driveRevision == _revision())) {
      return false;
    }
    final unmetered = _unmetered;
    if (photos &&
        _preferences.photosOnWifi &&
        unmetered != null &&
        !await unmetered()) {
      return false;
    }
    await _send(interactive: false);
    return true;
  }

  /// Asks Drive which account it is, so the card can say; best effort, a
  /// failure leaves it unknown until the next backup.
  Future<void> _learnAccount({required bool interactive}) async {
    try {
      final account = await _drive.account(interactive: interactive);
      if (account != null) _preferences.driveAccountIs(account);
    } on Object catch (error) {
      ErrorLog.instance.record(BackupWords.accountLookup, error);
    }
  }

  /// What a backup going up is doing now; null when none is.
  DriveStage? get stage => _busy ? _stage : null;
  static var _stage = DriveStage.packing;

  Future<void> _send({required bool interactive}) async {
    if (_busy) return;
    _busy = true;
    _stage = DriveStage.packing;
    notifyListeners();
    try {
      final revision = _revision();
      await _withBackup((file) {
        _stage = DriveStage.uploading;
        notifyListeners();
        return _drive.upload(
          file,
          ledger: _ledger,
          epoch: _epoch?.call(),
          interactive: interactive,
        );
      }, withPhotos: photos);
      _preferences.driveBackup(_clock(), revision);
      // Linked before the account was kept: learnt with the next backup.
      if (account == null) await _learnAccount(interactive: interactive);
    } finally {
      // Also when Google never answers: DriveBackup gives up on its
      // sign-in after a while, so a backup is never held for good.
      _busy = false;
      notifyListeners();
    }
  }
}

/// The steps of a backup going to Google Drive, as the card says them.
enum DriveStage {
  /// The ledger, and the photos when they go too, sealed into one file.
  packing('打包中…'),

  /// The file going to Drive, after Google's sign-in.
  uploading('上傳中…');

  const DriveStage(this.label);

  final String label;
}
