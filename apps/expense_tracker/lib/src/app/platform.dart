import 'dart:io';
import 'dart:ui' show Codec, ImmutableBuffer;

import 'package:core/foundation_values.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:vault/backup_security.dart';

import '../features/backup/model/drive_backup.dart';
import '../features/reminders/model/calendar_sync.dart';
import '../features/entries/model/receipt_photos.dart';
import '../features/reminders/model/reminders.dart';
import '../features/reminders/model/notifications.dart';
import '../core/quick_action.dart';
import '../features/lock/model/startup.dart';

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

/// The app's cache folder on Android, where the camera, the photo picker
/// and the file picker leave their copies.
Future<Directory> androidCacheDirectory() async {
  final path = await platformChannel.invokeMethod<String>('cacheDir');
  if (path == null) throw StateError('No cache folder.');
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

/// Hides the app from screenshots, recordings and the recent-apps preview
/// while [on] (Android's `FLAG_SECURE`).
Future<void> androidSecureScreen(bool on) =>
    platformChannel.invokeMethod<void>('secureScreen', {'on': on});

/// Lets the person choose a file and returns a copy the app can read, or
/// null when they cancel.
Future<String?> androidPickFile() =>
    platformChannel.invokeMethod<String>('pickFile');

/// An access token for the app's own files on Google Drive; null when the
/// person did not allow it, or, without [interactive], has not yet.
Future<String?> androidDriveToken({required bool interactive}) =>
    platformChannel.invokeMethod<String>('driveToken', {
      'interactive': interactive,
    });

/// Tells Google to forget [token], which it refused or the person no
/// longer wants used.
Future<void> androidClearDriveToken(String token) =>
    platformChannel.invokeMethod<void>('clearDriveToken', {'token': token});

/// Backups on Google Drive through the phone's Google account.
DriveBackup androidDrive() => DriveBackup(
  const IoDriveHttp(),
  token: androidDriveToken,
  forget: androidClearDriveToken,
);

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

/// Receipt photos in the app's private `receipts` folder, each sealed
/// with the ledger's [FileBox], so a photo is as private as the ledger.
/// The phone makes a photo smaller first (`MainActivity.kt`). Photos kept
/// before sealing (`.jpg`) still show.
final class AndroidReceipts implements ReceiptPhotos {
  const AndroidReceipts(this.directory, this.box);

  final Directory directory;
  final FileBox box;

  Directory get _folder => Directory('${directory.path}/receipts');

  @override
  Future<String?> take({required bool camera}) async {
    final ready = await platformChannel.invokeMethod<String>('takePhoto', {
      'camera': camera,
    });
    if (ready == null) return null;
    final source = File(ready);
    try {
      final name = '${DateTime.now().millisecondsSinceEpoch}.etr';
      await _folder.create(recursive: true);
      final sealed = await box.seal(name, await source.readAsBytes());
      await File('${_folder.path}/$name').writeAsBytes(sealed, flush: true);
      return name;
    } finally {
      if (source.existsSync()) await source.delete();
    }
  }

  @override
  ImageProvider image(String name) {
    final file = File('${_folder.path}/$name');
    return name.endsWith('.jpg') ? FileImage(file) : _SealedImage(file, box);
  }
}

/// A sealed photo, opened as it is drawn; the plain bytes stay in memory.
final class _SealedImage extends ImageProvider<_SealedImage> {
  const _SealedImage(this.file, this.box);

  final File file;
  final FileBox box;

  @override
  Future<_SealedImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    _SealedImage key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(codec: _open(decode), scale: 1);

  Future<Codec> _open(ImageDecoderCallback decode) async {
    final name = file.path.split('/').last;
    final plain = await box.open(name, await file.readAsBytes());
    return decode(await ImmutableBuffer.fromUint8List(plain));
  }

  @override
  bool operator ==(Object other) =>
      other is _SealedImage && other.file.path == file.path;

  @override
  int get hashCode => file.path.hashCode;
}

/// Notifications through `Reminders.kt`: each alert is an alarm that
/// posts it, kept across restarts of the phone. Each goes with its time on
/// the wall clock as well as its instant, so the phone can work the alarm
/// out again when the time zone or the clock changes.
final class AndroidNotifications implements NotifyPort {
  const AndroidNotifications();

  @override
  Future<bool> access() async =>
      await platformChannel.invokeMethod<bool>('notificationAccess') ?? false;

  @override
  Future<void> schedule(List<Alert> alerts) =>
      platformChannel.invokeMethod<void>('scheduleNotifications', {
        'alerts': [
          for (final a in alerts)
            {
              'at': a.at.millisecondsSinceEpoch,
              'y': a.at.toLocal().year,
              'm': a.at.toLocal().month,
              'd': a.at.toLocal().day,
              'hour': a.at.toLocal().hour,
              'minute': a.at.toLocal().minute,
              'title': a.title,
              'text': a.text,
              'quick': a.quick?.name,
            },
        ],
      });
}

/// What a home-screen shortcut, the widget or a notification asked for:
/// `expense` or `income` opens the composer. Held until the app is open
/// to act on it.
final quickAction = ValueNotifier<QuickAction?>(null);

/// Takes the action the app was opened with, then listens for those
/// that arrive while it runs. Each action arrives once: the phone keeps
/// one for `takeQuickAction` until that call, and only after it sends
/// later ones as `quickAction` (`MainActivity.kt`). The handler is set
/// first, so none sent after the take is missed.
Future<void> listenForQuickActions() async {
  platformChannel.setMethodCallHandler((call) async {
    if (call.method == 'quickAction')
      quickAction.value = QuickAction.named(call.arguments as String?);
  });
  final first = await platformChannel.invokeMethod<String>('takeQuickAction');
  if (QuickAction.named(first) case final action?) {
    quickAction.value = action;
  }
}
