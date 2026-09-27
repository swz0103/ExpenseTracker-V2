import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:entry_drafts/entry_drafts.dart';
import 'package:foundation_values/foundation_values.dart';

/// Local staging only. Portable financial backup requires resolving this slot.
/// File publication is a flushed encrypted sibling followed by atomic rename.
final class LocalDraftStore {
  LocalDraftStore(
    this.directory,
    this.identity,
    this.generation,
    this.workspace,
    this.readKey,
    this.writeKey, {
    this.checkpoint,
  });
  final Directory directory;
  final PublicId identity, generation;
  final WorkspaceId workspace;
  final Future<String?> Function(String) readKey;
  final Future<void> Function(String, String) writeKey;
  final void Function(String)? checkpoint;
  File get file => File('${directory.path}/manual-draft.enc');
  File get stage => File('${directory.path}/manual-draft.pending');
  String get slot => 'manual_draft_key_${identity.value}';
  List<int> get aad => utf8.encode(
    'expense-v2/manual-draft-v1/$identity/$generation/$workspace',
  );
  Future<void> _tail = Future.value();
  Future<void> get drained => _tail;

  Future<SecretKey> _key({required bool create}) async {
    var raw = await readKey(slot);
    if (raw == null) {
      if (!create || await file.exists() || await stage.exists()) {
        throw DraftUnavailable();
      }
      raw = base64Encode(
        await (await AesGcm.with256bits().newSecretKey()).extractBytes(),
      );
      await writeKey(slot, raw);
      if (await readKey(slot) != raw) throw DraftUnavailable();
    }
    final bytes = base64Decode(raw);
    if (bytes.length != 32) throw DraftUnavailable();
    return SecretKey(bytes);
  }

  Future<EntryDraft?> read() async {
    await _tail;
    if (!await file.exists()) {
      // Preserve unacknowledged first-publication input until explicit discard.
      if (await stage.exists()) throw DraftUnavailable();
      return null;
    }
    if (await file.length() > 65536) throw DraftUnavailable();
    try {
      final outer = jsonDecode(await file.readAsString()) as List;
      if (outer.length != 4 || outer[0] != 'local-draft-aes256gcm-v1') {
        throw DraftUnavailable();
      }
      final nonce = base64Decode(outer[1] as String);
      final cipher = base64Decode(outer[2] as String);
      final mac = base64Decode(outer[3] as String);
      if (nonce.length != 12 || mac.length != 16 || cipher.length > 16384) {
        throw DraftUnavailable();
      }
      final bytes = await AesGcm.with256bits().decrypt(
        SecretBox(cipher, nonce: nonce, mac: Mac(mac)),
        secretKey: await _key(create: false),
        aad: aad,
      );
      final text = utf8.decode(bytes);
      if (text == 'null') return null;
      final result = EntryDraft.decode(text);
      if (result.operation.workspace != workspace) throw DraftUnavailable();
      return result;
    } catch (_) {
      throw DraftUnavailable();
    }
  }

  Future<void> write(EntryDraft? draft) {
    final result = _tail.then((_) => _write(draft));
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> _write(EntryDraft? draft) async {
    if (draft != null && draft.operation.workspace != workspace) {
      throw DraftUnavailable();
    }
    final text = draft?.encode() ?? 'null';
    if (utf8.encode(text).length > 16384) throw DraftUnavailable();
    final key = await _key(create: true);
    final box = await AesGcm.with256bits().encrypt(
      utf8.encode(text),
      secretKey: key,
      aad: aad,
    );
    final encoded = jsonEncode([
      'local-draft-aes256gcm-v1',
      base64Encode(box.nonce),
      base64Encode(box.cipherText),
      base64Encode(box.mac.bytes),
    ]);
    await stage.writeAsString(encoded, flush: true);
    if (await stage.readAsString() != encoded) throw DraftUnavailable();
    checkpoint?.call('draft-staged');
    await stage.rename(file.path);
    checkpoint?.call('draft-published');
  }

  /// Explicit user discard is the only path allowed to remove an unreadable slot.
  Future<void> discard() async {
    await _tail;
    if (await file.exists()) await file.delete();
    if (await stage.exists()) await stage.delete();
    final key = base64Encode(
      await (await AesGcm.with256bits().newSecretKey()).extractBytes(),
    );
    await writeKey(slot, key);
    if (await readKey(slot) != key) throw DraftUnavailable();
  }
}

final class DraftUnavailable implements Exception {}

final class DraftNeedsResolution implements Exception {}
