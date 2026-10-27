import 'dart:io';

import 'channel.dart';

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
