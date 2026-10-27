import '../../features/reminders/model/calendar_sync.dart';
import '../../features/reminders/model/reminders.dart';
import 'channel.dart';

typedef _Row = Map<Object?, Object?>;

/// The phone's calendars through `CalendarBridge.kt`. Each reminder is an
/// event at 9:00 on its day, reminding then and, when asked, days before.
final class AndroidCalendar implements CalendarPort {
  const AndroidCalendar();

  @override
  Future<bool> access() async =>
      await platformChannel.invokeMethod<bool>('calendarAccess') ?? false;

  @override
  Future<List<CalendarChoice>> calendars() async {
    final rows = await platformChannel.invokeListMethod<_Row>('calendars');
    return [
      for (final row in rows ?? const <_Row>[])
        CalendarChoice(
          (row['id']! as num).toInt(),
          row['name']! as String,
          row['account']! as String,
        ),
    ];
  }

  @override
  Future<int> replace(
    int calendar,
    DateTime from,
    List<Reminder> reminders,
  ) async {
    int at(DateTime day, int hour) =>
        DateTime(day.year, day.month, day.day, hour).millisecondsSinceEpoch;
    final written = await platformChannel.invokeMethod<int>(
      'replaceCalendarEvents',
      {
        'calendar': calendar,
        'from': at(from, 0),
        'events': [
          for (final r in reminders)
            {
              'key': r.key,
              'title': r.title,
              'note': r.note,
              'start': at(r.day, 9),
              'remind': [0, if (r.daysAhead > 0) r.daysAhead * 24 * 60],
            },
        ],
      },
    );
    return written ?? 0;
  }
}
