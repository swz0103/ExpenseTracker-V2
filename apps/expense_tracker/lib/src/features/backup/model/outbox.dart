import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../../../core/platform/preferences.dart';
import 'phone_backup.dart';
import '../../../core/diagnostics/error_log.dart';
import '../../../core/time/app_clock.dart';
import '../../../core/formatting/json_fields.dart';
import '../../../core/platform/app_files.dart';

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
    required this._write,
    required this._revision,
    required this._ledger,
    this._schedule,
    DateTime Function()? clock,
  }) : _clock = clock ?? AppClock.now;

  /// The ledger's directory.
  final Directory directory;
  final Preferences _preferences;

  /// Writes an encrypted backup into the folder, with the receipt photos
  /// unless told not to.
  final Future<File> Function(Directory folder, {bool withPhotos}) _write;
  final int Function() _revision;
  final String _ledger;

  /// Starts the background job, or stops it with `on: false`.
  final Future<void> Function({required bool on})? _schedule;
  final DateTime Function() _clock;

  static Directory folderOf(Directory directory) =>
      Directory('${directory.path}/${AppFiles.outbox}');

  /// The highest revision a backup of the ledger in [directory] is known
  /// to have been delivered or to wait at: the folder's and Drive's as
  /// [preferences] note them, what the job noted in `delivered.json`
  /// that the app has not read back yet, and the backup waiting in
  /// `ready.json`; 0 when none says. Read without the ledger's keys, of
  /// any ledger: a restore goes on from above it, so no delivery passes
  /// for the book restored (review 28).
  static int deliveredRevision(Directory directory, Preferences preferences) {
    final folder = folderOf(directory);
    int? revisionIn(Object? json) => switch (json) {
      {'revision': final int revision} => revision,
      _ => null,
    };
    final delivered = _read(File('${folder.path}/${AppFiles.outboxDelivered}'));
    return [
      preferences.phoneRevision,
      preferences.driveRevision,
      revisionIn(delivered?['phone']),
      revisionIn(delivered?['drive']),
      revisionIn(_read(File('${folder.path}/${AppFiles.outboxReady}'))),
    ].nonNulls.fold(0, max);
  }

  Directory get _folder => folderOf(directory);
  File get _ready => File('${_folder.path}/${AppFiles.outboxReady}');
  File get _delivered => File('${_folder.path}/${AppFiles.outboxDelivered}');

  /// Somewhere to deliver to: a folder on the phone, or Google Drive.
  bool get wanted =>
      _preferences.phoneFolder != null || _preferences.driveLinked;

  /// The [prepare] under way: asked for again meanwhile, it is the answer,
  /// so two never write at once (ARC-05).
  Future<bool>? _preparing;

  /// Writes the backup for the job to deliver when the ledger changed
  /// since the one waiting and a place to deliver to does not hold this
  /// revision yet; starts or stops the job. True when one was written.
  /// Asked for while one is under way, it answers with that one.
  Future<bool> prepare() =>
      _preparing ??= _prepare().whenComplete(() => _preparing = null);

  Future<bool> _prepare() async {
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
    // The phone's folder always takes the photos; Drive only when asked,
    // and then it gets its own copy without them.
    final phone = _preferences.phoneFolder != null;
    final drive = _preferences.driveLinked;
    final photos = _preferences.drivePhotos;
    final file = await _write(_folder, withPhotos: phone || photos);
    final driveFile = phone && drive && !photos
        ? await _write(_folder, withPhotos: false)
        : null;
    await _save(_ready, {
      'v': 1,
      'file': file.uri.pathSegments.last,
      'driveFile': ?driveFile?.uri.pathSegments.last,
      'drivePhotos': photos,
      'revision': revision,
      'ledger': _ledger,
      'mark': PhoneBackup.markOf(_ledger),
      'at': _clock().toUtc().millisecondsSinceEpoch,
    });
    // The one waiting before is replaced: only the newest is delivered.
    for (final old in _folder.listSync()) {
      if (old is File &&
          old.path.endsWith('.etbk') &&
          old.path != file.path &&
          old.path != driveFile?.path) {
        await old.delete();
      }
    }
    return true;
  }

  /// Takes away the backup waiting for the job, and what says it is
  /// ready: after a reset of the keys it is sealed with the old ones. The
  /// next [prepare] writes one with the new keys when one is wanted.
  Future<void> empty() async {
    final folder = _folder;
    if (!folder.existsSync()) return;
    if (_ready.existsSync()) await _ready.delete();
    for (final old in folder.listSync()) {
      if (old is File && old.path.endsWith('.etbk')) await old.delete();
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
      uri: JsonFields(json).text('uri') ?? '',
    );
  }

  static bool _newer(DateTime at, DateTime? than) =>
      than == null || at.isAfter(than);

  static Map<String, Object?>? _read(File file) {
    if (!file.existsSync()) return null;
    try {
      final json = jsonDecode(file.readAsStringSync());
      return json is Map<String, Object?> ? json : null;
    } on Object catch (error) {
      ErrorLog.instance.record('備份佇列檔', error);
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
