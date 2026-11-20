import 'dart:io';

import 'package:expense_tracker/src/features/backup/model/phone_backup.dart';

/// A folder kept in memory.
final class FakeFolder implements FolderPort {
  final files = <String, String>{};
  var allowedNow = true;
  var picks = true;
  var rejects = false;

  @override
  Future<({String uri, String name})?> pick() async {
    if (rejects) throw const FolderRejected();
    return picks ? (uri: 'content://tree/backups', name: '備份') : null;
  }

  @override
  Future<bool> allowed(String uri) async => allowedNow;

  @override
  Future<void> forget(String uri) async => allowedNow = false;

  @override
  Future<List<FolderFile>> list(String uri) async => [
    for (final name in files.keys)
      (id: name, name: name, modified: DateTime(2026)),
  ];

  @override
  Future<void> write(String uri, File file, String name) async =>
      files[name] = file.readAsStringSync();

  @override
  Future<void> delete(String uri, String id) async => files.remove(id);
}
