import 'dart:io';

import 'package:flutter/services.dart';

import '../../features/backup/model/phone_backup.dart';
import 'platform_channel.dart';
import '../../core/formatting/json_fields.dart';

/// A folder chosen once with Android's folder chooser
/// (`FolderHandler.kt`).
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
    final folder = JsonFields.from(picked);
    return (uri: folder.need<String>('uri'), name: folder.text('name') ?? '');
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
      for (final file in files.map(JsonFields.from))
        (
          id: file.need<String>('id'),
          name: file.text('name') ?? '',
          modified: DateTime.fromMillisecondsSinceEpoch(
            file.whole('modified') ?? 0,
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
