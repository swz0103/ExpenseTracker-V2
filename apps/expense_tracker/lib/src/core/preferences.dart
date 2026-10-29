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

/// What the home-screen widget 本月概況 shows: nothing of the ledger, the
/// month's spending and what is left of the budget, or only the share of
/// the budget used.
enum WidgetFigures {
  off('不顯示數字'),
  amounts('顯示金額'),
  percent('只顯示百分比');

  const WidgetFigures(this.label);

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
      _nudgeMinute = (json['nudgeMinute'] as num?)?.toInt() ?? 0;
      _exactReminders = json['exactReminders'] as bool? ?? false;
      _phoneFolder = json['phoneFolder'] as String?;
      _phoneFolderName = json['phoneFolderName'] as String? ?? '';
      _phoneDaily = json['phoneDaily'] as bool? ?? false;
      _phoneBackedUp = DateTime.tryParse(
        json['phoneBackedUp'] as String? ?? '',
      );
      _phoneRevision = (json['phoneRevision'] as num?)?.toInt();
      _overview = (json['overview'] as List<Object?>?)?.cast<String>();
      _budgetAlerts = json['budgetAlerts'] as bool? ?? true;
      _budgetAlerted = {
        ...?(json['budgetAlerted'] as List<Object?>?)?.whereType<String>(),
      };
      _updateChecks = json['updateChecks'] as bool? ?? true;
      _updateCheckedAt = DateTime.tryParse(
        json['updateCheckedAt'] as String? ?? '',
      );
      _widgetFigures = WidgetFigures.values.firstWhere(
        (f) => f.name == json['widgetFigures'],
        orElse: () => WidgetFigures.off,
      );
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

  /// The minute past [nudgeHour] the nudge comes at.
  int get nudgeMinute => _nudgeMinute;
  var _nudgeMinute = 0;

  /// Reminders come on the minute, with the phone's alarm permission,
  /// rather than when the phone finds it convenient.
  bool get exactReminders => _exactReminders;
  var _exactReminders = false;

  /// The folder on the phone backups are kept in, as the system names it
  /// for the app; null when none was chosen.
  String? get phoneFolder => _phoneFolder;
  String? _phoneFolder;

  /// The folder's name as the chooser showed it.
  String get phoneFolderName => _phoneFolderName;
  var _phoneFolderName = '';

  /// Backups to the phone's folder daily rather than weekly.
  bool get phoneDaily => _phoneDaily;
  var _phoneDaily = false;

  /// When the last backup reached the phone's folder, and the ledger's
  /// revision in it.
  DateTime? get phoneBackedUp => _phoneBackedUp;
  DateTime? _phoneBackedUp;
  int? get phoneRevision => _phoneRevision;
  int? _phoneRevision;

  /// 總覽's blocks in the order chosen, a hidden one written `!name`;
  /// null for the order the app comes with.
  List<String>? get overview => _overview;
  List<String>? _overview;

  /// Keeps 總覽's blocks as [blocks], or the app's order with null.
  void overviewSet(List<String>? blocks) {
    _overview = blocks == null ? null : List.unmodifiable(blocks);
    notifyListeners();
    _save();
  }

  /// Keeps backups in the folder [uri] named [name], or stops with null.
  void phoneFolderSet(String? uri, {String name = ''}) {
    _phoneFolder = uri;
    _phoneFolderName = uri == null ? '' : name;
    if (uri == null) {
      _phoneBackedUp = null;
      _phoneRevision = null;
    }
    notifyListeners();
    _save();
  }

  /// Notes a backup of the ledger at [revision] kept in the phone's
  /// folder.
  void phoneBackup(DateTime at, int revision) {
    _phoneBackedUp = at;
    _phoneRevision = revision;
    notifyListeners();
    _save();
  }

  /// The first-start tour has been seen or skipped.
  bool get started => _started;
  var _started = false;

  /// What the home-screen widget shows; nothing until chosen, as the
  /// home screen is seen by anyone holding the phone.
  WidgetFigures get widgetFigures => _widgetFigures;
  var _widgetFigures = WidgetFigures.off;

  /// A notification when a budget reaches its warning share, and again
  /// when it is used up.
  bool get budgetAlerts => _budgetAlerts;
  var _budgetAlerts = true;

  /// The budget notifications already posted this month, as
  /// `<month>|<budget>|<level>`, so each comes once.
  Set<String> get budgetAlerted => Set.unmodifiable(_budgetAlerted);
  var _budgetAlerted = <String>{};

  /// Keeps [keys] as the budget notifications posted; those of earlier
  /// months are let go by the caller.
  void budgetAlertedSet(Set<String> keys) {
    _budgetAlerted = {...keys};
    _save();
  }

  /// Whether the app looks for a newer version by itself, at most daily.
  bool get updateChecks => _updateChecks;
  var _updateChecks = true;

  /// When it last looked.
  DateTime? get updateCheckedAt => _updateCheckedAt;
  DateTime? _updateCheckedAt;

  /// Notes that the app looked for a newer version at [at].
  void updateChecked(DateTime at) {
    _updateCheckedAt = at;
    _save();
  }

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
    int? nudgeMinute,
    bool? exactReminders,
    bool? phoneDaily,
    bool? started,
    bool? widgetShown,
    bool? driveLinked,
    WidgetFigures? widgetFigures,
    bool? updateChecks,
    bool? budgetAlerts,
  }) {
    _appearance = appearance ?? _appearance;
    _haptics = haptics ?? _haptics;
    _dueAlerts = dueAlerts ?? _dueAlerts;
    _dailyNudge = dailyNudge ?? _dailyNudge;
    _nudgeHour = (nudgeHour ?? _nudgeHour).clamp(0, 23);
    _nudgeMinute = (nudgeMinute ?? _nudgeMinute).clamp(0, 59);
    _exactReminders = exactReminders ?? _exactReminders;
    _phoneDaily = phoneDaily ?? _phoneDaily;
    _started = started ?? _started;
    _widgetShown = widgetShown ?? _widgetShown;
    _driveLinked = driveLinked ?? _driveLinked;
    _widgetFigures = widgetFigures ?? _widgetFigures;
    _updateChecks = updateChecks ?? _updateChecks;
    _budgetAlerts = budgetAlerts ?? _budgetAlerts;
    notifyListeners();
    _save();
  }

  void _save() {
    final file = _file;
    if (file == null) return;
    try {
      file.parent.createSync(recursive: true);
      // Written beside, then renamed over: a crash part way leaves the
      // old file whole rather than half a new one.
      final next = File('${file.path}.new');
      next.writeAsStringSync(
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
          'nudgeMinute': _nudgeMinute,
          'exactReminders': _exactReminders,
          'phoneFolder': _phoneFolder,
          'phoneFolderName': _phoneFolderName,
          'phoneDaily': _phoneDaily,
          'phoneBackedUp': _phoneBackedUp?.toUtc().toIso8601String(),
          'phoneRevision': _phoneRevision,
          'overview': _overview,
          'widgetFigures': _widgetFigures.name,
          'updateChecks': _updateChecks,
          'budgetAlerts': _budgetAlerts,
          'budgetAlerted': _budgetAlerted.toList(),
          'updateCheckedAt': _updateCheckedAt?.toUtc().toIso8601String(),
        }),
        flush: true,
      );
      next.renameSync(file.path);
    } on Object {
      // Kept in memory for this run; the next change tries again.
    }
  }
}
