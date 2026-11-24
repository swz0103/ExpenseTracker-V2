import 'dart:convert';
import 'dart:io';

import 'package:expense_tracker/src/features/backup/model/phone_backup.dart';

/// A folder kept in memory.
final class FakeFolder implements FolderPort {
  /// Each file's content as text; [bytes] holds what was written.
  final files = <String, String>{};

  /// Each written file's bytes; one put into [files] by hand reads as its
  /// text.
  final bytes = <String, List<int>>{};

  /// When each file was last written, as the folder says; 2026-01-01 for
  /// one not given.
  final modifiedAt = <String, DateTime>{};
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
      (id: name, name: name, modified: modifiedAt[name] ?? DateTime(2026)),
  ];

  @override
  Future<void> write(String uri, File file, String name) async {
    bytes[name] = file.readAsBytesSync();
    files[name] = utf8.decode(bytes[name]!, allowMalformed: true);
  }

  @override
  Future<void> delete(String uri, String id) async {
    files.remove(id);
    bytes.remove(id);
  }

  @override
  Future<List<int>> head(String uri, String id, int count) async {
    final whole = bytes[id] ?? utf8.encode(files[id] ?? '');
    return whole.length > count ? whole.sublist(0, count) : whole;
  }
}
