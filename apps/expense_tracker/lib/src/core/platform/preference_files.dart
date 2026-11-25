import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:vault/backup_security.dart' show DeviceKeyWrapper;

import '../formatting/json_fields.dart';
import '../diagnostics/error_log.dart';
import '../diagnostics/error_steps.dart';
import 'app_files.dart';

/// What the preferences hold at one moment, as their files keep it: the
/// plain choices, the private part and what the background jobs are
/// handed. Made by `Preferences` each time a file is written.
final class KeptPreferences {
  const KeptPreferences({
    required this.plain,
    required this.private,
    required this.noPrivate,
    required this.privateChosen,
    required this.updateChecks,
    required this.drive,
    required this.phone,
  });

  /// The fields of [AppFiles.preferences], choices only.
  final Map<String, Object?> plain;

  /// The fields that could say who the person is, sealed.
  final Map<String, Object?> private;

  /// Nothing private is kept: no sealed part is needed.
  final bool noPrivate;

  /// The account or the folder was chosen (or cleared) since the start.
  final bool privateChosen;

  /// Whether the app looks for a newer version by itself.
  final bool updateChecks;

  /// Google Drive, when linked: on Wi-Fi only with the photos, and its
  /// last backup.
  final ({bool photosOnWifi, DateTime? at, int? revision})? drive;

  /// The phone's folder, when chosen, in plain form (sealed here for the
  /// background jobs), with its id, its rhythm and its last backup.
  final ({String folder, String id, bool daily, DateTime? at, int? revision})?
  phone;
}

/// The files the preferences are kept in, beside the ledger: the plain
/// choices ([AppFiles.preferences]), the private part sealed with the
/// phone's Keystore ([AppFiles.preferencesSealed]), and what the
/// background jobs read ([AppFiles.background]). Each change is written a
/// moment later, off the UI thread, changes close together in one write
/// ([saved]); each file is written beside and renamed over.
final class PreferenceFiles {
  /// The files beside [file], sealed with `keystore`; `kept` says what to
  /// write, asked as each file is written.
  PreferenceFiles(this.file, this._keystore, this._kept);

  final File file;
  final DeviceKeyWrapper _keystore;
  final KeptPreferences Function() _kept;

  /// What the private part is sealed for; a blob sealed for another use
  /// does not open as it.
  static final _privateContext = utf8.encode('expense_tracker/preferences');

  /// What the phone folder is sealed for in [AppFiles.background]; the
  /// background job opens it with the same (`QuickSeal.FOLDER_CONTEXT`).
  static const folderContext = 'expense_tracker/backup-folder';

  File get _sealedFile =>
      File('${file.parent.path}/${AppFiles.preferencesSealed}');

  File get _backgroundFile =>
      File('${file.parent.path}/${AppFiles.background}');

  /// Reads the plain file into [plain] and the sealed part into [sealed].
  /// False when the plain file was there and could not be read: the
  /// defaults stay, and it is not written over until a setting is
  /// changed.
  Future<bool> read({
    required void Function(JsonFields json) plain,
    required void Function(JsonFields json) sealed,
  }) async {
    var read = true;
    try {
      if (await file.exists()) {
        plain(JsonFields.decode(await file.readAsString()));
      }
    } on Object catch (error, stack) {
      read = false;
      ErrorLog.instance.record(ErrorSteps.preferencesRead, error, stack);
    }
    final kept = _sealedFile;
    try {
      if (await kept.exists()) {
        final bytes = await kept.readAsBytes();
        final open = await _unwrapped(bytes);
        sealed(JsonFields.decode(utf8.decode(open)));
        _privateWritten = jsonEncode(_kept().private);
      }
    } on Object catch (error, stack) {
      // A key gone (the phone's Keystore reset) leaves what the plain
      // file had, or nothing: the folder is chosen again. The sealed file
      // stays until the person chooses the account or the folder anew,
      // so a Keystore that only failed this once opens it at the next
      // start.
      _sealedUnread = true;
      ErrorLog.instance.record(ErrorSteps.preferencesRead, error, stack);
    }
    return read;
  }

  /// Whether the background jobs have no file of what they read yet.
  Future<bool> backgroundMissing() async => !await _backgroundFile.exists();

  /// [sealed] opened by the Keystore, asked twice: one busy at the start
  /// often opens it a moment later. The second refusal is thrown.
  Future<List<int>> _unwrapped(List<int> sealed) async {
    for (var tries = 2; ; tries--) {
      try {
        return await _keystore.unwrap(sealed, _privateContext);
      } on Object {
        if (tries == 1) rethrow;
      }
    }
  }

  /// Copies a stop part way through a write left beside the files.
  Future<void> clearHalfWritten() async {
    final names = [
      for (final kept in [file, _sealedFile, _backgroundFile])
        '${kept.uri.pathSegments.last}.',
    ];
    try {
      final folder = file.parent;
      if (!await folder.exists()) return;
      await for (final entry in folder.list()) {
        final name = entry.uri.pathSegments.last;
        if (entry is File &&
            name.endsWith('.new') &&
            names.any(name.startsWith)) {
          await entry.delete();
        }
      }
    } on Object catch (error, stack) {
      ErrorLog.instance.record(ErrorSteps.preferencesWrite, error, stack);
    }
  }

  /// The write under way; null when none is.
  Future<void>? _saving;

  /// A change came while [_saving] was under way: written after it.
  var _again = false;

  /// The private part as last sealed, so an unchanged one is not sealed
  /// again; the folder as last sealed for the background job, and the
  /// background file as last written.
  String? _privateWritten;

  /// The sealed file did not open at the start: left as it is until the
  /// person chooses the account or the folder
  /// ([KeptPreferences.privateChosen]), and then written over, a value
  /// cleared too, so that it never comes back.
  var _sealedUnread = false;
  (String, String)? _folderSealed;
  String? _backgroundWritten;

  /// Done once every change so far is written (or could not be): before
  /// the app is left, so the background jobs read what was chosen.
  Future<void> get saved => _saving ?? Future<void>.value();

  /// Writes what is kept now, a moment later.
  void save() {
    if (_saving != null) {
      _again = true;
      return;
    }
    _saving = _write().whenComplete(() => _saving = null);
  }

  Future<void> _write() async {
    // Changes made together, in the same turn, go in one write.
    await Future<void>.delayed(Duration.zero);
    do {
      _again = false;
      try {
        await _writeOnce();
      } on Object catch (error, stack) {
        // Kept in memory for this run; the next change tries again.
        ErrorLog.instance.record(ErrorSteps.preferencesWrite, error, stack);
      }
    } while (_again);
  }

  Future<void> _writeOnce() async {
    await file.parent.create(recursive: true);
    // The sealed part first: a stop between the two leaves the plain file
    // as it was, private fields and all, never neither.
    final sealedOk = await _writeSealed();
    final kept = _kept();
    await _replace(
      file,
      utf8.encode(
        jsonEncode({
          ...kept.plain,
          // Not sealed this time (the Keystore refused): kept plain, as
          // before, rather than lost; sealed at the next change.
          if (!sealedOk) ...kept.private,
        }),
      ),
    );
    await _writeBackground();
  }

  /// Seals the private part into its file when it changed; false when it
  /// could not be sealed.
  Future<bool> _writeSealed() async {
    final sealed = _sealedFile;
    final kept = _kept();
    final text = jsonEncode(kept.private);
    if (text == _privateWritten) return true;
    // Nothing chosen since the sealed file did not open: it stays, and
    // what is private now is kept plain beside it for this turn.
    if (_sealedUnread && !kept.privateChosen) return kept.noPrivate;
    try {
      if (kept.noPrivate) {
        _sealedUnread = false;
        if (await sealed.exists()) await sealed.delete();
      } else {
        _sealedUnread = false;
        await _replace(
          sealed,
          await _keystore.wrap(utf8.encode(text), _privateContext),
        );
      }
      _privateWritten = text;
      return true;
    } on Object catch (error, stack) {
      ErrorLog.instance.record(ErrorSteps.preferencesWrite, error, stack);
      return false;
    }
  }

  /// Hands the background jobs what they need, and no more
  /// ([AppFiles.background]): whether to look for a newer version; Drive
  /// linked, on Wi-Fi only with the photos, and its last backup; the
  /// phone's folder (sealed, with its id), its rhythm and its last backup.
  /// Times are milliseconds since 1970.
  Future<void> _writeBackground() async {
    final kept = _kept();
    final phone = kept.phone;
    String? sealedFolder;
    if (phone != null) {
      final folder = phone.folder;
      final sealed = _folderSealed;
      if (sealed != null && sealed.$1 == folder) {
        sealedFolder = sealed.$2;
      } else {
        sealedFolder = base64.encode(
          await _keystore.wrap(utf8.encode(folder), utf8.encode(folderContext)),
        );
        _folderSealed = (folder, sealedFolder);
      }
    }
    final text = jsonEncode(
      backgroundPlan(
        updateChecks: kept.updateChecks,
        drive: kept.drive,
        phone: phone == null || sealedFolder == null
            ? null
            : (
                folder: sealedFolder,
                id: phone.id,
                daily: phone.daily,
                at: phone.at,
                revision: phone.revision,
              ),
      ),
    );
    if (text == _backgroundWritten) return;
    await _replace(_backgroundFile, utf8.encode(text));
    _backgroundWritten = text;
  }

  /// What the background jobs are handed ([AppFiles.background]); the
  /// keys `BackupWorker.kt` and `UpdateWorker.kt` read.
  @visibleForTesting
  static Map<String, Object?> backgroundPlan({
    required bool updateChecks,
    required ({bool photosOnWifi, DateTime? at, int? revision})? drive,
    required ({
      String folder,
      String id,
      bool daily,
      DateTime? at,
      int? revision,
    })?
    phone,
  }) => {
    'v': 1,
    'updateChecks': updateChecks,
    'drive': switch (drive) {
      null => null,
      final d => {
        'photosOnWifi': d.photosOnWifi,
        'at': d.at?.millisecondsSinceEpoch,
        'revision': d.revision,
      },
    },
    'phone': switch (phone) {
      null => null,
      final p => {
        'folder': p.folder,
        'id': p.id,
        'daily': p.daily,
        'at': p.at?.millisecondsSinceEpoch,
        'revision': p.revision,
      },
    },
  };

  /// Written beside, then renamed over: a stop part way leaves the old
  /// file whole, never half a new one. By the I/O threads, flushed there.
  static Future<void> _replace(File file, List<int> bytes) async {
    final next = File('${file.path}.${_random.nextInt(1 << 30)}.new');
    await next.writeAsBytes(bytes, flush: true);
    await next.rename(file.path);
  }

  static final _random = Random.secure();
}
