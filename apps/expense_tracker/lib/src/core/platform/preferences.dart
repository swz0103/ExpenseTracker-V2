import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:ledger_trade_costs/calc/broker_discount.dart'
    show BrokerDiscountRange;

import '../formatting/json_fields.dart';
import '../ledger/trading.dart' show defaultBrokerDiscount;
import '../diagnostics/error_log.dart';
import '../diagnostics/error_steps.dart';

/// Light or dark colours.
enum Appearance {
  system('跟著手機'),
  light('淺色'),
  dark('深色');

  const Appearance(this.label);

  final String label;
}

/// 震動: none, Android's light ticks, or a step heavier (標準).
enum Vibration {
  off('關'),
  light('輕'),
  standard('標準');

  const Vibration(this.label);

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

/// 自動上鎖: how long the app may be off the screen before a ledger with a
/// password asks for it again. The one table of the choices; [standard]
/// until the person picks another.
enum AutoLock {
  immediately('立即', Duration.zero),
  oneMinute('1 分鐘', Duration(minutes: 1)),
  fiveMinutes('5 分鐘', Duration(minutes: 5)),
  fifteenMinutes('15 分鐘', Duration(minutes: 15)),
  never('不自動上鎖', null);

  const AutoLock(this.label, this.after);

  final String label;

  /// How long away locks the ledger; null for never while the app stays
  /// open (a closed app always asks again).
  final Duration? after;

  /// The choice a ledger has until another is made.
  static const standard = fiveMinutes;

  /// The least time away that locks the ledger while the app itself sent
  /// the person elsewhere for a moment (the camera for a receipt, a file
  /// chooser, Google's sign-in), so a shorter choice does not close the
  /// form being filled in.
  static const errand = Duration(minutes: 5);

  /// How long away locks the ledger under this choice; [onErrand] when
  /// the app itself sent the person away. Null for never.
  Duration? limit({required bool onErrand}) {
    final after = this.after;
    if (after == null) return null;
    return onErrand && after < errand ? errand : after;
  }
}

/// How this phone shows the app: colours, taps felt, notifications. Kept
/// beside the ledger in a file of its own, so it holds from the lock
/// screen on; the preview keeps it in memory.
final class Preferences extends ChangeNotifier {
  Preferences({this._file}) {
    final file = _file;
    if (file == null || !file.existsSync()) return;
    try {
      // Field by field: one that cannot be read keeps its default and
      // costs none of the others.
      final json = JsonFields.decode(file.readAsStringSync());
      _appearance = Appearance.values.firstWhere(
        (a) => a.name == json.text('appearance'),
        orElse: () => Appearance.system,
      );
      // Before 0.20.0 only on or off was kept: on is 標準.
      _vibration = Vibration.values.firstWhere(
        (v) => v.name == json.text('vibration'),
        orElse: () =>
            json.flag('haptics') == false ? Vibration.off : Vibration.standard,
      );
      _dueAlerts = json.flag('dueAlerts') ?? false;
      _dailyNudge = json.flag('dailyNudge') ?? false;
      _nudgeHour = json.whole('nudgeHour') ?? 21;
      _started = json.flag('started') ?? false;
      _widgetShown = json.flag('widgetShown') ?? false;
      _driveLinked = json.flag('driveLinked') ?? false;
      _drivePhotos = json.flag('drivePhotos') ?? false;
      _photosOnWifi = json.flag(photosOnWifiKey) ?? true;
      _googleBackup = json.flag('googleBackup') ?? true;
      _driveBackedUp = DateTime.tryParse(json.text('driveBackedUp') ?? '');
      _driveRevision = json.whole('driveRevision');
      _driveAccount = json.text('driveAccount');
      _nudgeMinute = json.whole('nudgeMinute') ?? 0;
      _exactReminders = json.flag('exactReminders') ?? false;
      _phoneFolder = json.text('phoneFolder');
      _phoneFolderName = json.text('phoneFolderName') ?? '';
      _phoneDaily = json.flag('phoneDaily') ?? false;
      _phoneBackedUp = DateTime.tryParse(json.text('phoneBackedUp') ?? '');
      _phoneRevision = json.whole('phoneRevision');
      _overview = json.texts('overview');
      _budgetAlerts = json.flag('budgetAlerts') ?? false;
      _budgetAlerted = {...?json.texts('budgetAlerted')};
      _updateChecks = json.flag('updateChecks') ?? true;
      _updateCheckedAt = DateTime.tryParse(json.text('updateCheckedAt') ?? '');
      _updateLaterUntil = DateTime.tryParse(
        json.text('updateLaterUntil') ?? '',
      );
      _updateSkipped = json.whole('updateSkipped');
      _widgetFigures = WidgetFigures.values.firstWhere(
        (f) => f.name == json.text('widgetFigures'),
        orElse: () => WidgetFigures.off,
      );
      _brokerDiscount = _discountIn(
        json.whole('brokerDiscount') ?? defaultBrokerDiscount,
      );
      _autoLock = AutoLock.values.firstWhere(
        (a) => a.name == json.text('autoLock'),
        orElse: () => AutoLock.standard,
      );
    } on Object catch (error, stack) {
      // An unreadable file leaves the defaults.
      ErrorLog.instance.record(ErrorSteps.preferencesRead, error, stack);
    }
  }

  final File? _file;

  Appearance get appearance => _appearance;
  var _appearance = Appearance.system;

  /// 震動: a tick on choices, a tap on saving, and how heavy.
  Vibration get vibration => _vibration;
  var _vibration = Vibration.standard;

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

  /// How long away locks a ledger with a password; read by the lock gate
  /// each time the app comes back.
  AutoLock get autoLock => _autoLock;
  var _autoLock = AutoLock.standard;

  /// The broker's discount on the fee a trade suggests, in basis points of
  /// the full fee: 6000 for 6折, 2800 for 2.8折, 10000 for none. The one
  /// setting of it; 6折 until changed.
  int get brokerDiscount => _brokerDiscount;
  var _brokerDiscount = defaultBrokerDiscount;

  /// [basisPoints] held to a discount a fee can have: from 0.01% of the
  /// fee to all of it.
  static int _discountIn(int basisPoints) =>
      BrokerDiscountRange.clamp(basisPoints);

  /// A notification when a budget reaches its warning share, and again
  /// when it is used up. Off until the person turns it on, which asks the
  /// phone to allow notifications, as every kind of reminder does.
  bool get budgetAlerts => _budgetAlerts;
  var _budgetAlerts = false;

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

  /// Until when a newer version waits to be offered again: 晚一點再說
  /// puts it off to the next day.
  DateTime? get updateLaterUntil => _updateLaterUntil;
  DateTime? _updateLaterUntil;

  /// The build 略過這一版 passed over: offered again only when a newer
  /// one comes.
  int? get updateSkipped => _updateSkipped;
  int? _updateSkipped;

  /// Puts off offering a newer version until [until], or passes over
  /// [skip]; 設定 › 關於 offers it whatever these say.
  void updateLater({DateTime? until, int? skip}) {
    _updateLaterUntil = until ?? _updateLaterUntil;
    _updateSkipped = skip ?? _updateSkipped;
    _save();
  }

  /// The way to the home-screen widget was shown.
  bool get widgetShown => _widgetShown;
  var _widgetShown = false;

  /// Was the switch for Android's own backup of the ledger, gone in
  /// 0.13.0, when the copy it takes became always kept; read and written
  /// still, so an older version given this file back finds it.
  bool get googleBackup => _googleBackup;
  var _googleBackup = true;

  /// Backups go up to Google Drive: by hand, and weekly by themselves.
  bool get driveLinked => _driveLinked;
  var _driveLinked = false;

  /// The backups on Google Drive carry the receipt photos too, and so wait
  /// for Wi-Fi; without them only the ledger goes, on any network.
  bool get drivePhotos => _drivePhotos;
  var _drivePhotos = false;

  /// Backups that carry the receipt photos go up only on Wi-Fi or another
  /// network that costs nothing per byte; off, on any network. On until
  /// the person turns it off (AND-05). The background job reads it from
  /// the file under [photosOnWifiKey] (`BackupWorker.kt`).
  bool get photosOnWifi => _photosOnWifi;
  var _photosOnWifi = true;

  /// The name [photosOnWifi] is kept under in the file.
  static const photosOnWifiKey = 'photosOnWifi';

  /// When the last backup reached Google Drive.
  DateTime? get driveBackedUp => _driveBackedUp;
  DateTime? _driveBackedUp;

  /// The ledger's revision in that backup.
  int? get driveRevision => _driveRevision;
  int? _driveRevision;

  /// The Google account the backups go to, as Drive names it (its
  /// address); null before it is known.
  String? get driveAccount => _driveAccount;
  String? _driveAccount;

  /// Notes the Google account Drive is linked to; null forgets it.
  void driveAccountIs(String? account) {
    _driveAccount = account;
    notifyListeners();
    _save();
  }

  /// Notes a backup of the ledger at [revision] kept on Google Drive.
  void driveBackup(DateTime at, int revision) {
    _driveBackedUp = at;
    _driveRevision = revision;
    notifyListeners();
    _save();
  }

  void update({
    Appearance? appearance,
    Vibration? vibration,
    bool? dueAlerts,
    bool? dailyNudge,
    int? nudgeHour,
    int? nudgeMinute,
    bool? exactReminders,
    bool? phoneDaily,
    bool? started,
    bool? widgetShown,
    bool? driveLinked,
    bool? drivePhotos,
    bool? photosOnWifi,
    bool? googleBackup,
    WidgetFigures? widgetFigures,
    bool? updateChecks,
    bool? budgetAlerts,
    int? brokerDiscount,
    AutoLock? autoLock,
  }) {
    _appearance = appearance ?? _appearance;
    _vibration = vibration ?? _vibration;
    _dueAlerts = dueAlerts ?? _dueAlerts;
    _dailyNudge = dailyNudge ?? _dailyNudge;
    _nudgeHour = (nudgeHour ?? _nudgeHour).clamp(0, 23);
    _nudgeMinute = (nudgeMinute ?? _nudgeMinute).clamp(0, 59);
    _exactReminders = exactReminders ?? _exactReminders;
    _phoneDaily = phoneDaily ?? _phoneDaily;
    _started = started ?? _started;
    _widgetShown = widgetShown ?? _widgetShown;
    _driveLinked = driveLinked ?? _driveLinked;
    _drivePhotos = drivePhotos ?? _drivePhotos;
    _photosOnWifi = photosOnWifi ?? _photosOnWifi;
    _googleBackup = googleBackup ?? _googleBackup;
    _widgetFigures = widgetFigures ?? _widgetFigures;
    _updateChecks = updateChecks ?? _updateChecks;
    _budgetAlerts = budgetAlerts ?? _budgetAlerts;
    _brokerDiscount = _discountIn(brokerDiscount ?? _brokerDiscount);
    _autoLock = autoLock ?? _autoLock;
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
          'vibration': _vibration.name,
          'dueAlerts': _dueAlerts,
          'dailyNudge': _dailyNudge,
          'nudgeHour': _nudgeHour,
          'started': _started,
          'widgetShown': _widgetShown,
          'driveLinked': _driveLinked,
          'drivePhotos': _drivePhotos,
          photosOnWifiKey: _photosOnWifi,
          'googleBackup': _googleBackup,
          'driveBackedUp': _driveBackedUp?.toUtc().toIso8601String(),
          'driveRevision': _driveRevision,
          'driveAccount': _driveAccount,
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
          'updateLaterUntil': _updateLaterUntil?.toUtc().toIso8601String(),
          'updateSkipped': _updateSkipped,
          'brokerDiscount': _brokerDiscount,
          'autoLock': _autoLock.name,
        }),
        flush: true,
      );
      next.renameSync(file.path);
    } on Object catch (error, stack) {
      // Kept in memory for this run; the next change tries again.
      ErrorLog.instance.record(ErrorSteps.preferencesWrite, error, stack);
    }
  }
}
