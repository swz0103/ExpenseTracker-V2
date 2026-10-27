import 'package:flutter/foundation.dart';

import '../../../core/connector.dart';
import '../../backup/model/drive_sync.dart';
import '../../backup/model/keeper.dart';
import '../../reminders/model/calendar_sync.dart';
import '../../entries/model/receipt_photos.dart';
import '../../../core/ledger/ledger.dart';
import '../../reminders/model/notifications.dart';
import '../../../core/preferences.dart';
import '../../../core/quick_action.dart';
import '../../../core/screen_privacy.dart';

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
    this.sample,
    this.receipts,
    this.drive,
    this.market,
  });

  final Keeper? keeper;
  final CalendarSync? calendar;
  final ScreenPrivacy? privacy;
  final Preferences? preferences;
  final Notifier? notifier;

  /// What a shortcut, the widget or a notification asked for, taken (set
  /// back to null) once acted on.
  final ValueNotifier<QuickAction?>? quick;

  /// The preview's made-up book, made afresh to start over from; none for
  /// a real ledger.
  final Ledger Function()? sample;

  /// The phone's receipt photos; none in the preview, which hides them.
  final ReceiptPhotos? receipts;

  /// Backups on Google Drive, on Android.
  final DriveSync? drive;

  /// Closing prices and rates; none in the preview.
  final Connector? market;
}
