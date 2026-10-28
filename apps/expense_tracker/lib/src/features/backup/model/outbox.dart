import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../../../core/preferences.dart';
import 'phone_backup.dart';

/// Backups that reach the phone's folder and Google Drive without the app
/// being opened. The ledger's key is only in the open app, so the backup
/// is written, already encrypted, when the app is left with changes not
/// yet in a backup: into `outbox/`, beside `ready.json` saying what it
/// is. A background job (BackupWorker.kt) delivers it when one is due by
/// the chosen rhythm, and notes each delivery in `delivered.json`, which
/// the app reads back into [Preferences] when it is next opened. The job
/// never needs the key, and never sees anything but the sealed backup.
///
/// The folder is this phone's own: it stays out of Android's cloud backup
/// and the move to a new phone (res/xml).
final class Outbox {
  Outbox(
    this.directory,
    this._preferences, {
    required Future<File> Function(Directory folder) write,
    required int Function() revision,
    required String ledger,
    Future<void> Function({required bool on})? schedule,
    DateTime Function()? clock,
  }) : _write = write,
       _revision = revision,
       _ledger = ledger,
       _schedule = schedule,
       _clock = clock ?? DateTime.now;

  /// The ledger's directory.
  final Directory directory;
  final Preferences _preferences;

  /// Writes an encrypted backup, with the receipt photos, into the folder.
  final Future<File> Function(Directory folder) _write;
  final int Function() _revision;
  final String _ledger;

  /// Starts the background job, or stops it with `on: false`.
  final Future<void> Function({required bool on})? _schedule;
  final DateTime Function() _clock;

  static Directory folderOf(Directory directory) =>
      Directory('${directory.path}/outbox');

  Directory get _folder => folderOf(directory);
  File get _ready => File('${_folder.path}/ready.json');
  File get _delivered => File('${_folder.path}/delivered.json');

  /// Somewhere to deliver to: a folder on the phone, or Google Drive.
  bool get wanted => _preferences.phoneFolder != null || _preferences.driveLinked;

  var _busy = false;

  /// Writes the backup for the job to deliver when the ledger changed
  /// since the one waiting and a place to deliver to does not hold this
  /// revision yet; starts or stops the job. True when one was written.
  Future<bool> prepare() async {
    if (_busy) return false;
    final on = wanted;
    await _schedule?.call(on: on);
    if (!on) return false;
    final revision = _revision();
    final ready = _read(_ready);
    if (ready != null &&
        ready['ledger'] == _ledger &&
        ready['revision'] == revision) {
      return false;
    }
    final phoneHas =
        _preferences.phoneFolder == null ||
        _preferences.phoneRevision == revision;
    final driveHas =
        !_preferences.driveLinked || _preferences.driveRevision == revision;
    if (phoneHas && driveHas) return false;
    _busy = true;
    try {
      final file = await _write(_folder);
      await _save(_ready, {
        'v': 1,
        'file': file.uri.pathSegments.last,
        'revision': revision,
        'ledger': _ledger,
        'mark': PhoneBackup.markOf(_ledger),
        'at': _clock().toUtc().millisecondsSinceEpoch,
      });
      // The one waiting before is replaced: only the newest is delivered.
      for (final old in _folder.listSync()) {
        if (old is File && old.path.endsWith('.etbk') && old.path != file.path) {
          await old.delete();
        }
      }
      return true;
    } finally {
      _busy = false;
    }
  }

  /// Notes in [Preferences] what the job delivered while the app was
  /// closed, so the settings show it and the app does not send the same
  /// backup again. Returns what went wrong there since last asked, to be
  /// logged.
  List<String> collect() {
    final delivered = _read(_delivered);
    if (delivered == null) return const [];
    final phone = _delivery(delivered['phone']);
    final folder = _preferences.phoneFolder;
    if (phone != null &&
        folder != null &&
        phone.uri == folder &&
        _newer(phone.at, _preferences.phoneBackedUp)) {
      _preferences.phoneBackup(phone.at, phone.revision);
    }
    final drive = _delivery(delivered['drive']);
    if (drive != null &&
        _preferences.driveLinked &&
        _newer(drive.at, _preferences.driveBackedUp)) {
      _preferences.driveBackup(drive.at, drive.revision);
    }
    final problems = <String>[];
    final failed = delivered['problems'];
    if (failed is Map<String, Object?>) {
      for (final MapEntry(:key, :value) in failed.entries) {
        if (value is! Map<String, Object?>) continue;
        final at = value['at'];
        final message = value['message'];
        if (at is! int || message is! String) continue;
        if (at <= (_seen[key] ?? 0)) continue;
        _seen[key] = at;
        problems.add('${key == 'drive' ? '雲端硬碟' : '手機資料夾'}：$message');
      }
    }
    return problems;
  }

  /// The newest problem of each place already reported, this run.
  final _seen = <String, int>{};

  ({DateTime at, int revision, String uri})? _delivery(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final at = json['at'];
    final revision = json['revision'];
    if (at is! int || revision is! int || json['ledger'] != _ledger) {
      return null;
    }
    return (
      at: DateTime.fromMillisecondsSinceEpoch(at, isUtc: true),
      revision: revision,
      uri: json['uri'] as String? ?? '',
    );
  }

  static bool _newer(DateTime at, DateTime? than) =>
      than == null || at.isAfter(than);

  static Map<String, Object?>? _read(File file) {
    if (!file.existsSync()) return null;
    try {
      final json = jsonDecode(file.readAsStringSync());
      return json is Map<String, Object?> ? json : null;
    } on Object {
      return null;
    }
  }

  /// Written beside, then renamed over: the job never reads half a file.
  static Future<void> _save(File file, Map<String, Object?> json) async {
    await file.parent.create(recursive: true);
    final next = File('${file.path}.${Random.secure().nextInt(1 << 30)}.new');
    await next.writeAsString(jsonEncode(json), flush: true);
    await next.rename(file.path);
  }
}
