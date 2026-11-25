import '../../features/reminders/model/calendar_sync.dart';
import 'platform_channel.dart';
import '../../core/formatting/json_fields.dart';

typedef _Row = Map<Object?, Object?>;

/// The phone's calendars through `CalendarBridge.kt`, which reads and
/// writes the app's events as it is told; what they say and when is
/// decided in [CalendarSync].
final class AndroidCalendar implements CalendarPort {
  const AndroidCalendar();

  @override
  Future<bool> access() async =>
      await platformChannel.invokeMethod<bool>('calendarAccess') ?? false;

  @override
  Future<List<CalendarChoice>> calendars() async {
    final rows = await platformChannel.invokeListMethod<_Row>('calendars');
    return [
      for (final row in [
        for (final row in rows ?? const <_Row>[]) JsonFields.from(row),
      ])
        CalendarChoice(
          row.need<num>('id').toInt(),
          row.need<String>('name'),
          row.need<String>('account'),
        ),
    ];
  }

  /// The start of [day] on the phone's clock, in milliseconds.
  static int _startOf(DateTime day) =>
      DateTime(day.year, day.month, day.day).millisecondsSinceEpoch;

  /// [event] as the phone writes it.
  static Map<String, Object?> eventFields(CalendarEvent event) => {
    'id': ?event.id,
    'key': event.key,
    'title': event.title,
    'note': event.note,
    'start': event.start.millisecondsSinceEpoch,
    'remind': event.remind,
  };

  @override
  Future<List<CalendarEvent>> events(int calendar, DateTime from) async {
    final rows = await platformChannel.invokeListMethod<_Row>(
      'calendarEvents',
      {'calendar': calendar, 'from': _startOf(from), 'mark': CalendarSync.mark},
    );
    return [
      for (final row in [
        for (final row in rows ?? const <_Row>[]) JsonFields.from(row),
      ])
        CalendarEvent(
          id: row.need<num>('id').toInt(),
          key: row.need<String>('key'),
          title: row.need<String>('title'),
          note: row.need<String>('note'),
          start: DateTime.fromMillisecondsSinceEpoch(
            row.need<num>('start').toInt(),
          ),
          remind: row.wholes('remind') ?? const [],
        ),
    ];
  }

  @override
  Future<int> apply(int calendar, CalendarChanges changes) async =>
      await platformChannel.invokeMethod<int>('applyCalendarChanges', {
        'calendar': calendar,
        'insert': [for (final e in changes.insert) eventFields(e)],
        'update': [for (final e in changes.update) eventFields(e)],
        'delete': changes.delete,
        'mark': CalendarSync.mark,
        'length': CalendarSync.eventLength.inMilliseconds,
      }) ??
      0;
}
