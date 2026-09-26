import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:encrypted_storage_probe/encrypted_database.dart';
import 'package:foundation_values/foundation_values.dart';

import 'key_slots.dart';

/// INSECURE fixture adapter for subprocess tests. Never use with real data.
/// Plaintext keys in an owned temporary directory are not platform secure storage.
final class FixtureKeySlots implements KeySlots {
  FixtureKeySlots(this.directory);
  final Directory directory;

  Future<File> _file(PublicId slot, {bool creating = false}) async {
    var type = await FileSystemEntity.type(directory.path, followLinks: false);
    if (creating && type == FileSystemEntityType.notFound) {
      await directory.create();
      type = await FileSystemEntity.type(directory.path, followLinks: false);
    }
    if (type != FileSystemEntityType.directory)
      throw StateError('Slot unavailable');
    final file = File('${directory.path}/${slot.value}.key');
    final fileType = await FileSystemEntity.type(file.path, followLinks: false);
    if (fileType != FileSystemEntityType.notFound &&
        fileType != FileSystemEntityType.file) {
      throw StateError('Slot unavailable');
    }
    return file;
  }

  @override
  Future<void> create(PublicId slot) async {
    final file = await _file(slot, creating: true);
    // All cooperating callers hold the store's lifecycle lock.
    if (await file.exists()) throw StateError('Slot already exists');
    final random = Random.secure();
    final encoded =
        'v1:${base64Encode(List.generate(32, (_) => random.nextInt(256)))}';
    await file.writeAsString(encoded, flush: true);
    if (await file.readAsString() != encoded)
      throw StateError('Slot readback failed');
    await read(slot);
  }

  @override
  Future<StorageKey> read(PublicId slot) async {
    final file = await _file(slot);
    if (!await file.exists() || await file.length() != 47)
      throw StateError('Slot unavailable');
    final encoded = await file.readAsString();
    if (!encoded.startsWith('v1:')) throw StateError('Slot unavailable');
    final bytes = base64Decode(encoded.substring(3));
    if (bytes.length != 32 || 'v1:${base64Encode(bytes)}' != encoded) {
      throw StateError('Slot unavailable');
    }
    return StorageKey(bytes);
  }
}
