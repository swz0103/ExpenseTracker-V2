// Exception to file length: each setting, the part (topic) a change to it
// tells, and how it is kept (plain, sealed, handed to the background jobs)
// are written together, over fields private to this file; a setting added
// in one of those places and not the others is lost or leaks unseen.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:core/foundation_values.dart' show PublicId;
import 'package:flutter/foundation.dart';
import 'package:ledger_trade_costs/calc/broker_discount.dart'
    show BrokerDiscountRange;
import 'package:vault/backup_security.dart' show DeviceKeyWrapper;

import '../formatting/json_fields.dart';
import '../ledger/trading.dart' show defaultBrokerDiscount;
import '../diagnostics/error_log.dart';
import '../diagnostics/error_steps.dart';
import 'app_files.dart';
import 'memory_keystore.dart';

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

/// The parts of [Preferences] that can be followed on their own
/// ([Preferences.watch]): a change tells only the part it is in, so a
/// backup noted in the background does not plan the reminders again, nor
/// a theme chosen write the widget.
enum PreferenceTopic {
  /// [Preferences.appearance], [Preferences.vibration].
  look,

  /// The reminders and budget notifications chosen, and the nudge's time.
  reminders,

  /// What the home-screen widget shows, and that its way was shown.
  homeWidget,

  /// The phone's backup folder, its rhythm and its last backup.
  phoneBackup,

  /// Google Drive: linked, with the photos, on Wi-Fi, its last backup and
  /// the account.
  driveBackup,

  /// Whether the app looks for a newer version by itself.
  updates,

  /// 總覽's blocks.
  overview,

  /// [Preferences.autoLock].
  lock,

  /// [Preferences.brokerDiscount].
  trading,

  /// [Preferences.started], the first-start tour.
  start,
}

/// How this phone shows the app: colours, taps felt, notifications. Kept
/// beside the ledger in files of its own, so it holds from the lock
/// screen on; the preview keeps it in memory.
///
/// What could say who the person is (the Google account, the phone folder
/// and its name, the budgets a notification was posted for) is sealed with
/// the phone's Keystore ([AppFiles.preferencesSealed]); the plain file
/// ([AppFiles.preferences]) holds choices only. The background jobs read
/// neither: they get [AppFiles.background], what they need and no more,
/// the folder in it sealed too.
///
/// Not a [Listenable] as a whole: a page follows the parts it reads
/// ([watch]). Each change is written a moment later, off the UI thread,
/// changes close together in one write ([saved]).
final class Preferences {
  /// Kept in memory only, as in the preview and most tests.
  Preferences() : _file = null, _keystore = MemoryKeystore.instance;

  Preferences._(this._file, this._keystore);

  /// The preferences kept in [file] (and the sealed part beside it),
  /// sealed with [keystore]; the defaults when there are none, and for a
  /// field that cannot be read.
  static Future<Preferences> open(
    File file, {
    DeviceKeyWrapper? keystore,
  }) async {
    final preferences = Preferences._(
      file,
      keystore ?? MemoryKeystore.instance,
    );
    await preferences._read();
    return preferences;
  }

  final File? _file;
  final DeviceKeyWrapper _keystore;

  /// What the private part is sealed for; a blob sealed for another use
  /// does not open as it.
  static final _privateContext = utf8.encode('expense_tracker/preferences');

  /// What the phone folder is sealed for in [AppFiles.background]; the
  /// background job opens it with the same (`QuickSeal.FOLDER_CONTEXT`).
  static const folderContext = 'expense_tracker/backup-folder';

  File? get _sealedFile => switch (_file) {
    final file? => File('${file.parent.path}/${AppFiles.preferencesSealed}'),
    null => null,
  };

  File? get _backgroundFile => switch (_file) {
    final file? => File('${file.parent.path}/${AppFiles.background}'),
    null => null,
  };

  Future<void> _read() async {
    final file = _file!;
    var again = false;
    var unread = false;
    try {
      if (await file.exists()) {
        final json = JsonFields.decode(await file.readAsString());
        _readPlain(json);
        // An older version kept these in the plain file: sealed now.
        again = _readPrivate(json);
      }
    } on Object catch (error, stack) {
      // An unreadable file leaves the defaults, and is not written over
      // until a setting is changed.
      unread = true;
      ErrorLog.instance.record(ErrorSteps.preferencesRead, error, stack);
    }
    final sealed = _sealedFile!;
    try {
      if (await sealed.exists()) {
        final bytes = await sealed.readAsBytes();
        final open = await _unwrapped(bytes);
        _readPrivate(JsonFields.decode(utf8.decode(open)));
        _privateWritten = _privateText();
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
    if (_phoneFolder != null && _phoneFolderId == null) {
      _phoneFolderId = PublicId.generate().value;
      again = true;
    }
    await _clearHalfWritten();
    if (unread) return;
    if (again || !await _backgroundFile!.exists()) _save();
  }

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
  Future<void> _clearHalfWritten() async {
    final names = [
      for (final kept in [_file!, _sealedFile!, _backgroundFile!])
        '${kept.uri.pathSegments.last}.',
    ];
    try {
      final folder = _file.parent;
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

  void _readPlain(JsonFields json) {
    // Field by field: one that cannot be read keeps its default and
    // costs none of the others.
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
    _photosOnWifi = json.flag('photosOnWifi') ?? true;
    _googleBackup = json.flag('googleBackup') ?? true;
    _driveBackedUp = DateTime.tryParse(json.text('driveBackedUp') ?? '');
    _driveRevision = json.whole('driveRevision');
    _nudgeMinute = json.whole('nudgeMinute') ?? 0;
    _exactReminders = json.flag('exactReminders') ?? false;
    _phoneDaily = json.flag('phoneDaily') ?? false;
    _phoneBackedUp = DateTime.tryParse(json.text('phoneBackedUp') ?? '');
    _phoneRevision = json.whole('phoneRevision');
    _overview = json.texts('overview');
    _budgetAlerts = json.flag('budgetAlerts') ?? false;
    _updateChecks = json.flag('updateChecks') ?? true;
    _updateCheckedAt = DateTime.tryParse(json.text('updateCheckedAt') ?? '');
    _updateLaterUntil = DateTime.tryParse(json.text('updateLaterUntil') ?? '');
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
  }

  /// The private fields in [json]; true when it had any.
  bool _readPrivate(JsonFields json) {
    final had = _privateKeys.any(json.json.containsKey);
    if (json.json.containsKey('driveAccount')) {
      _driveAccount = json.text('driveAccount');
    }
    if (json.json.containsKey('phoneFolder')) {
      _phoneFolder = json.text('phoneFolder');
      _phoneFolderName = json.text('phoneFolderName') ?? '';
      _phoneFolderId = json.text('phoneFolderId');
    }
    if (json.json.containsKey('budgetAlerted')) {
      _budgetAlerted = {...?json.texts('budgetAlerted')};
    }
    return had;
  }

  /// The fields that could say who the person is: never in the plain
  /// file once sealed.
  static const _privateKeys = [
    'driveAccount',
    'phoneFolder',
    'phoneFolderName',
    'phoneFolderId',
    'budgetAlerted',
  ];

  // ---- following ----

  final _topics = {for (final topic in PreferenceTopic.values) topic: _Topic()};

  /// Tells of a change to any of [topics] (none of the others): what a
  /// page or a job reads, and nothing more.
  Listenable watch(Set<PreferenceTopic> topics) {
    assert(topics.isNotEmpty, 'Watch the topics read.');
    return Listenable.merge([for (final topic in topics) _topics[topic]]);
  }

  /// What [topic] holds, to tell whether a change touched it.
  List<Object?> _of(PreferenceTopic topic) => switch (topic) {
    PreferenceTopic.look => [_appearance, _vibration],
    PreferenceTopic.reminders => [
      _dueAlerts,
      _dailyNudge,
      _nudgeHour,
      _nudgeMinute,
      _exactReminders,
      _budgetAlerts,
    ],
    PreferenceTopic.homeWidget => [_widgetFigures, _widgetShown],
    PreferenceTopic.phoneBackup => [
      _phoneFolder,
      _phoneFolderName,
      _phoneDaily,
      _phoneBackedUp,
      _phoneRevision,
    ],
    PreferenceTopic.driveBackup => [
      _driveLinked,
      _drivePhotos,
      _photosOnWifi,
      _googleBackup,
      _driveBackedUp,
      _driveRevision,
      _driveAccount,
    ],
    PreferenceTopic.updates => [_updateChecks],
    PreferenceTopic.overview => [_overview == null, ...?_overview],
    PreferenceTopic.lock => [_autoLock],
    PreferenceTopic.trading => [_brokerDiscount],
    PreferenceTopic.start => [_started],
  };

  /// Makes [change], tells the topics it changed, and keeps it.
  void _change(void Function() change) {
    final before = {
      for (final topic in PreferenceTopic.values) topic: _of(topic),
    };
    change();
    for (final topic in PreferenceTopic.values) {
      if (!listEquals(before[topic], _of(topic))) _topics[topic]!.tell();
    }
    _save();
  }

  // ---- the settings ----

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
  /// for the app; null when none was chosen. Sealed.
  String? get phoneFolder => _phoneFolder;
  String? _phoneFolder;

  /// The folder's name as the chooser showed it. Sealed.
  String get phoneFolderName => _phoneFolderName;
  var _phoneFolderName = '';

  /// An id of the chosen folder that says nothing of it, made when it is
  /// chosen: what the background job notes a delivery there by.
  String? get phoneFolderId => _phoneFolderId;
  String? _phoneFolderId;

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
  void overviewSet(List<String>? blocks) => _change(() {
    _overview = blocks == null ? null : List.unmodifiable(blocks);
  });

  /// Keeps backups in the folder [uri] named [name], or stops with null.
  void phoneFolderSet(String? uri, {String name = ''}) => _change(() {
    _privateChosen = true;
    if (uri != _phoneFolder) {
      _phoneFolderId = uri == null ? null : PublicId.generate().value;
    }
    _phoneFolder = uri;
    _phoneFolderName = uri == null ? '' : name;
    if (uri == null) {
      _phoneBackedUp = null;
      _phoneRevision = null;
    }
  });

  /// Notes a backup of the ledger at [revision] kept in the phone's
  /// folder.
  void phoneBackup(DateTime at, int revision) => _change(() {
    _phoneBackedUp = at;
    _phoneRevision = revision;
  });

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
  /// `<month>|<budget>|<level>`, so each comes once. Sealed: a budget is
  /// named by its category.
  Set<String> get budgetAlerted => Set.unmodifiable(_budgetAlerted);
  var _budgetAlerted = <String>{};

  /// Keeps [keys] as the budget notifications posted; those of earlier
  /// months are let go by the caller. Tells no one.
  void budgetAlertedSet(Set<String> keys) =>
      _change(() => _budgetAlerted = {...keys});

  /// Whether the app looks for a newer version by itself, at most daily.
  bool get updateChecks => _updateChecks;
  var _updateChecks = true;

  /// When it last looked.
  DateTime? get updateCheckedAt => _updateCheckedAt;
  DateTime? _updateCheckedAt;

  /// Notes that the app looked for a newer version at [at]. Tells no one.
  void updateChecked(DateTime at) => _change(() => _updateCheckedAt = at);

  /// Until when a newer version waits to be offered again: 晚一點再說
  /// puts it off to the next day.
  DateTime? get updateLaterUntil => _updateLaterUntil;
  DateTime? _updateLaterUntil;

  /// The build 略過這一版 passed over: offered again only when a newer
  /// one comes.
  int? get updateSkipped => _updateSkipped;
  int? _updateSkipped;

  /// Puts off offering a newer version until [until], or passes over
  /// [skip]; 設定 › 關於 offers it whatever these say. Tells no one.
  void updateLater({DateTime? until, int? skip}) => _change(() {
    _updateLaterUntil = until ?? _updateLaterUntil;
    _updateSkipped = skip ?? _updateSkipped;
  });

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
  /// the person turns it off (AND-05). The background job is handed it in
  /// [AppFiles.background].
  bool get photosOnWifi => _photosOnWifi;
  var _photosOnWifi = true;

  /// When the last backup reached Google Drive.
  DateTime? get driveBackedUp => _driveBackedUp;
  DateTime? _driveBackedUp;

  /// The ledger's revision in that backup.
  int? get driveRevision => _driveRevision;
  int? _driveRevision;

  /// The Google account the backups go to, as Drive names it (its
  /// address); null before it is known. Sealed.
  String? get driveAccount => _driveAccount;
  String? _driveAccount;

  /// Notes the Google account Drive is linked to; null forgets it.
  void driveAccountIs(String? account) => _change(() {
    _privateChosen = true;
    _driveAccount = account;
  });

  /// Notes a backup of the ledger at [revision] kept on Google Drive.
  void driveBackup(DateTime at, int revision) => _change(() {
    _driveBackedUp = at;
    _driveRevision = revision;
  });

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
  }) => _change(() {
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
  });

  // ---- keeping ----

  /// The write under way; null when none is.
  Future<void>? _saving;

  /// A change came while [_saving] was under way: written after it.
  var _again = false;

  /// The private part as last sealed, so an unchanged one is not sealed
  /// again; the folder as last sealed for the background job, and the
  /// background file as last written.
  String? _privateWritten;

  /// The sealed file did not open at the start: left as it is until the
  /// person chooses the account or the folder ([_privateChosen]), and then
  /// written over, a value cleared too, so that it never comes back.
  var _sealedUnread = false;

  /// The account or the folder was chosen (or cleared) since the start.
  var _privateChosen = false;
  (String, String)? _folderSealed;
  String? _backgroundWritten;

  /// Done once every change so far is written (or could not be): before
  /// the app is left, so the background jobs read what was chosen.
  Future<void> get saved => _saving ?? Future<void>.value();

  void _save() {
    if (_file == null) return;
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

  Map<String, Object?> _private() => {
    'driveAccount': _driveAccount,
    'phoneFolder': _phoneFolder,
    'phoneFolderName': _phoneFolderName,
    'phoneFolderId': _phoneFolderId,
    'budgetAlerted': _budgetAlerted.toList(),
  };

  String _privateText() => jsonEncode(_private());

  /// Nothing private is kept: no sealed part is needed.
  bool get _noPrivate =>
      _driveAccount == null && _phoneFolder == null && _budgetAlerted.isEmpty;

  Future<void> _writeOnce() async {
    final file = _file!;
    await file.parent.create(recursive: true);
    // The sealed part first: a stop between the two leaves the plain file
    // as it was, private fields and all, never neither.
    final sealedOk = await _writeSealed();
    await _replace(
      file,
      utf8.encode(
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
          'photosOnWifi': _photosOnWifi,
          'googleBackup': _googleBackup,
          'driveBackedUp': _driveBackedUp?.toUtc().toIso8601String(),
          'driveRevision': _driveRevision,
          'nudgeMinute': _nudgeMinute,
          'exactReminders': _exactReminders,
          'phoneDaily': _phoneDaily,
          'phoneBackedUp': _phoneBackedUp?.toUtc().toIso8601String(),
          'phoneRevision': _phoneRevision,
          'overview': _overview,
          'widgetFigures': _widgetFigures.name,
          'updateChecks': _updateChecks,
          'budgetAlerts': _budgetAlerts,
          'updateCheckedAt': _updateCheckedAt?.toUtc().toIso8601String(),
          'updateLaterUntil': _updateLaterUntil?.toUtc().toIso8601String(),
          'updateSkipped': _updateSkipped,
          'brokerDiscount': _brokerDiscount,
          'autoLock': _autoLock.name,
          // Not sealed this time (the Keystore refused): kept plain, as
          // before, rather than lost; sealed at the next change.
          if (!sealedOk) ..._private(),
        }),
      ),
    );
    await _writeBackground();
  }

  /// Seals the private part into its file when it changed; false when it
  /// could not be sealed.
  Future<bool> _writeSealed() async {
    final sealed = _sealedFile!;
    final text = _privateText();
    if (text == _privateWritten) return true;
    // Nothing chosen since the sealed file did not open: it stays, and
    // what is private now is kept plain beside it for this turn.
    if (_sealedUnread && !_privateChosen) return _noPrivate;
    try {
      if (_noPrivate) {
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
    final folder = _phoneFolder;
    String? sealedFolder;
    if (folder != null) {
      final kept = _folderSealed;
      if (kept != null && kept.$1 == folder) {
        sealedFolder = kept.$2;
      } else {
        sealedFolder = base64.encode(
          await _keystore.wrap(utf8.encode(folder), utf8.encode(folderContext)),
        );
        _folderSealed = (folder, sealedFolder);
      }
    }
    final text = jsonEncode(
      backgroundPlan(
        updateChecks: _updateChecks,
        drive: _driveLinked
            ? (
                photosOnWifi: _photosOnWifi,
                at: _driveBackedUp,
                revision: _driveRevision,
              )
            : null,
        phone: sealedFolder == null
            ? null
            : (
                folder: sealedFolder,
                id: _phoneFolderId!,
                daily: _phoneDaily,
                at: _phoneBackedUp,
                revision: _phoneRevision,
              ),
      ),
    );
    if (text == _backgroundWritten) return;
    await _replace(_backgroundFile!, utf8.encode(text));
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

/// One part of [Preferences] to follow.
final class _Topic extends ChangeNotifier {
  void tell() => notifyListeners();
}
