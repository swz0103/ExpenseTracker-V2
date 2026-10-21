import 'package:flutter/foundation.dart';

import 'book/drive_sync.dart';
import 'book/keeper.dart';
import 'calendar_sync.dart';
import 'compose/receipt_photos.dart';
import 'model/ledger.dart';
import 'notifications.dart';
import 'preferences.dart';
import 'quick_action.dart';
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
    this.sample,
    this.receipts,
    this.drive,
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
}
