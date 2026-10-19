import 'dart:io';

import 'package:vault/backup_security.dart';
import 'package:flutter/services.dart';
import 'package:core/foundation_values.dart';

import 'calendar_sync.dart';
import 'model/reminders.dart';
import 'startup.dart';

/// What the Android side of the app provides: its private files folder
/// and a Keystore key that needs the fingerprint or face to be used
/// (`MainActivity.kt`).
const platformChannel = MethodChannel('expense_tracker/platform');

/// The app's private folder on Android, which no other app can read.
Future<Directory> androidFilesDirectory() async {
  final path = await platformChannel.invokeMethod<String>('filesDir');
  if (path == null) throw StateError('No files folder.');
  return Directory(path);
}

/// This install's device unlock, when the phone can confirm a fingerprint
/// or face; null otherwise. Its id is made once and kept beside the
/// ledger, so a reinstall enrols a new key.
Future<DeviceUnlock?> androidDeviceUnlock(Directory directory) async {
  final usable = await platformChannel.invokeMethod<bool>('canUseBiometrics');
  if (usable != true) return null;
  final file = File('${directory.path}/device-id');
  if (!file.existsSync()) {
    await directory.create(recursive: true);
    await file.writeAsString('android-${PublicId.generate().value}');
  }
  return DeviceUnlock(
    (await file.readAsString()).trim(),
    const KeystoreDeviceKey(),
    hasKey: () async =>
        await platformChannel.invokeMethod<bool>('hasDeviceKey') ?? false,
  );
}

/// Wraps the ledger key with an Android Keystore key bound to biometric
/// confirmation; [context] is bound in as AES-GCM associated data.
final class KeystoreDeviceKey implements DeviceKeyWrapper {
  const KeystoreDeviceKey();

  @override
  Future<List<int>> wrap(List<int> secret, List<int> context) =>
      _call('wrap', secret, context);

  @override
  Future<List<int>> unwrap(List<int> wrapped, List<int> context) =>
      _call('unwrap', wrapped, context);

  Future<List<int>> _call(
    String method,
    List<int> data,
    List<int> context,
  ) async {
    final result = await platformChannel.invokeMethod<Uint8List>(method, {
      'data': Uint8List.fromList(data),
      'context': Uint8List.fromList(context),
    });
    if (result == null) throw StateError('The device key gave nothing.');
    return result;
  }
}

/// Lets the person save a copy of the file at [path], named [name],
/// wherever they choose (Downloads, Google Drive, ...). False when they
/// cancel.
Future<bool> androidExportFile(String path, String name) async {
  final saved = await platformChannel.invokeMethod<bool>('exportFile', {
    'path': path,
    'name': name,
  });
  return saved ?? false;
}

/// Lets the person choose a file and returns a copy the app can read, or
/// null when they cancel.
Future<String?> androidPickFile() =>
    platformChannel.invokeMethod<String>('pickFile');

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
