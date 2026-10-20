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
    } on Object {
      // An unreadable file leaves the defaults.
    }
  }

  final File? _file;

  Appearance get appearance => _appearance;
  var _appearance = Appearance.system;

  /// 震動回饋: a tick on choices, a tap on saving.
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

  void update({
    Appearance? appearance,
    bool? haptics,
    bool? dueAlerts,
    bool? dailyNudge,
    int? nudgeHour,
  }) {
    _appearance = appearance ?? _appearance;
    _haptics = haptics ?? _haptics;
    _dueAlerts = dueAlerts ?? _dueAlerts;
    _dailyNudge = dailyNudge ?? _dailyNudge;
    _nudgeHour = (nudgeHour ?? _nudgeHour).clamp(0, 23);
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
        }),
        flush: true,
      );
    } on Object {
      // Kept in memory for this run; the next change tries again.
    }
  }
}
