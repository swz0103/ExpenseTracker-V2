import 'dart:io';

import 'package:flutter/services.dart';

import '../../features/backup/model/phone_backup.dart';
import 'channel.dart';

/// A folder chosen once with Android's folder chooser
/// (`FolderPart.kt`).
final class AndroidFolder implements FolderPort {
  const AndroidFolder();

  @override
  Future<({String uri, String name})?> pick() async {
    final Map<String, Object?>? picked;
    try {
      picked = await platformChannel.invokeMapMethod<String, Object?>(
        'pickFolder',
      );
    } on PlatformException catch (error) {
      if (error.code == 'rejected') throw const FolderRejected();
      rethrow;
    }
    if (picked == null) return null;
    return (
      uri: picked['uri']! as String,
      name: picked['name'] as String? ?? '',
    );
  }

  @override
  Future<bool> allowed(String uri) async =>
      await platformChannel.invokeMethod<bool>('folderAllowed', {'uri': uri}) ??
      false;

  @override
  Future<void> forget(String uri) =>
      platformChannel.invokeMethod<void>('forgetFolder', {'uri': uri});

  @override
  Future<List<FolderFile>> list(String uri) async {
    final files =
        await platformChannel.invokeListMethod<Map<Object?, Object?>>(
          'listFolder',
          {'uri': uri},
        ) ??
        const [];
    return [
      for (final file in files)
        (
          id: file['id']! as String,
          name: file['name'] as String? ?? '',
          modified: DateTime.fromMillisecondsSinceEpoch(
            (file['modified'] as num?)?.toInt() ?? 0,
          ),
        ),
    ];
  }

  @override
  Future<void> write(String uri, File file, String name) =>
      platformChannel.invokeMethod<void>('writeToFolder', {
        'uri': uri,
        'path': file.path,
        'name': name,
      });

  @override
  Future<void> delete(String uri, String id) => platformChannel
      .invokeMethod<void>('deleteInFolder', {'uri': uri, 'id': id});
}
