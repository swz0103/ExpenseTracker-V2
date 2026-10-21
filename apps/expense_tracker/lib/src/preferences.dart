import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Light or dark colours.
enum Appearance {
  system('跟隨系統'),
  light('淺色'),
  dark('深色');

  const Appearance(this.label);

  final String label;
}

/// How this phone shows the app: colours, taps felt, notifications. Kept
/// beside the ledger in a file of its own, so it holds from the lock
/// screen on; the preview keeps it in memory.
final class Preferences extends ChangeNotifier {
  Preferences({File? file}) : _file = file {
    final file = _file;
    if (file == null || !file.existsSync()) return;
    try {
      final json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      _appearance = Appearance.values.firstWhere(
        (a) => a.name == json['appearance'],
        orElse: () => Appearance.system,
      );
      _haptics = json['haptics'] as bool? ?? true;
      _dueAlerts = json['dueAlerts'] as bool? ?? false;
      _dailyNudge = json['dailyNudge'] as bool? ?? false;
      _nudgeHour = (json['nudgeHour'] as num?)?.toInt() ?? 21;
      _started = json['started'] as bool? ?? false;
      _widgetShown = json['widgetShown'] as bool? ?? false;
      _driveLinked = json['driveLinked'] as bool? ?? false;
      _driveBackedUp = DateTime.tryParse(
        json['driveBackedUp'] as String? ?? '',
      );
      _driveRevision = (json['driveRevision'] as num?)?.toInt();
    } on Object {
      // An unreadable file leaves the defaults.
    }
  }

  final File? _file;

  Appearance get appearance => _appearance;
  var _appearance = Appearance.system;

  /// 震動: a tick on choices, a tap on saving.
  bool get haptics => _haptics;
  var _haptics = true;

  /// A notification on the day a recurring item or a card payment falls
  /// due (card payments two days before as well).
  bool get dueAlerts => _dueAlerts;
  var _dueAlerts = false;

  /// A nudge at [nudgeHour] on days nothing was recorded.
  bool get dailyNudge => _dailyNudge;
  var _dailyNudge = false;

  int get nudgeHour => _nudgeHour;
  var _nudgeHour = 21;

  /// The 開始使用 card was put away.
  bool get started => _started;
  var _started = false;

  /// The way to the home-screen widget was shown.
  bool get widgetShown => _widgetShown;
  var _widgetShown = false;

  /// Backups go up to Google Drive: by hand, and weekly by themselves.
  bool get driveLinked => _driveLinked;
  var _driveLinked = false;

  /// When the last backup reached Google Drive.
  DateTime? get driveBackedUp => _driveBackedUp;
  DateTime? _driveBackedUp;

  /// The ledger's revision in that backup.
  int? get driveRevision => _driveRevision;
  int? _driveRevision;

  /// Notes a backup of the ledger at [revision] kept on Google Drive.
  void driveBackup(DateTime at, int revision) {
    _driveBackedUp = at;
    _driveRevision = revision;
    notifyListeners();
    _save();
  }

  void update({
    Appearance? appearance,
    bool? haptics,
    bool? dueAlerts,
    bool? dailyNudge,
    int? nudgeHour,
    bool? started,
    bool? widgetShown,
    bool? driveLinked,
  }) {
    _appearance = appearance ?? _appearance;
    _haptics = haptics ?? _haptics;
    _dueAlerts = dueAlerts ?? _dueAlerts;
    _dailyNudge = dailyNudge ?? _dailyNudge;
    _nudgeHour = (nudgeHour ?? _nudgeHour).clamp(0, 23);
    _started = started ?? _started;
    _widgetShown = widgetShown ?? _widgetShown;
    _driveLinked = driveLinked ?? _driveLinked;
    notifyListeners();
    _save();
  }

  void _save() {
    final file = _file;
    if (file == null) return;
    try {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
        jsonEncode({
          'appearance': _appearance.name,
          'haptics': _haptics,
          'dueAlerts': _dueAlerts,
          'dailyNudge': _dailyNudge,
          'nudgeHour': _nudgeHour,
          'started': _started,
          'widgetShown': _widgetShown,
          'driveLinked': _driveLinked,
          'driveBackedUp': _driveBackedUp?.toUtc().toIso8601String(),
          'driveRevision': _driveRevision,
        }),
        flush: true,
      );
    } on Object {
      // Kept in memory for this run; the next change tries again.
    }
  }
}
