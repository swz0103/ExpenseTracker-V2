import 'package:flutter/foundation.dart';

import 'book/keeper.dart';
import 'calendar_sync.dart';
import 'notifications.dart';
import 'preferences.dart';
import 'screen_privacy.dart';

/// What the phone and the open ledger offer the screens beyond the book:
/// keys and backups, the calendar for due dates, hiding the screens,
/// notifications, the person's preferences and the shortcuts that open
/// the composer. Each is absent in the preview but the preferences.
final class Services {
  const Services({
    this.keeper,
    this.calendar,
    this.privacy,
    this.preferences,
    this.notifier,
    this.quick,
  });

  final Keeper? keeper;
  final CalendarSync? calendar;
  final ScreenPrivacy? privacy;
  final Preferences? preferences;
  final Notifier? notifier;

  /// What a shortcut, the widget or a notification asked for: `expense`
  /// or `income`, taken (set back to null) once acted on.
  final ValueNotifier<String?>? quick;
}
