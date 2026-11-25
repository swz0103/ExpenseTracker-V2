import 'dart:convert';
import 'dart:io';

/// Where a file to hand over is written until the person has it, in the
/// app's folder [directory]; emptied at each start (leftovers.dart).
Directory exportsIn(Directory directory) =>
    Directory('${directory.path}/exports');

/// Hands [bytes] to the person as the file [name] through [export] (the
/// phone's save dialog), written into [folder] only until then. False
/// when they cancel.
Future<bool> handOver(
  Directory folder,
  String name,
  List<int> bytes,
  Future<bool> Function(String path, String name) export,
) async {
  await folder.create(recursive: true);
  final file = File('${folder.path}/$name');
  await file.writeAsBytes(bytes, flush: true);
  try {
    return await export(file.path, name);
  } finally {
    if (file.existsSync()) await file.delete();
  }
}

/// Hands text over as a file named as asked, through [export], written
/// into the exports of the app's folder [directory] only until then: as
/// the backup manager does, and as the lock screen does with no ledger
/// open.
Future<bool> Function(String name, String text) textHandOver(
  Directory directory,
  Future<bool> Function(String path, String name) export,
) =>
    (name, text) =>
        handOver(exportsIn(directory), name, utf8.encode(text), export);
