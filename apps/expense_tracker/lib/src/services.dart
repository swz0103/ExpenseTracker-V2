import 'book/keeper.dart';
import 'calendar_sync.dart';
import 'screen_privacy.dart';

/// What the phone and the open ledger offer the screens beyond the book:
/// keys and backups, the calendar for due dates, hiding the screens. Each
/// is absent in the preview.
final class Services {
  const Services({this.keeper, this.calendar, this.privacy});

  final Keeper? keeper;
  final CalendarSync? calendar;
  final ScreenPrivacy? privacy;
}
