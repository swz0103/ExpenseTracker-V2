import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'file_box.dart';
import 'keyring.dart';

/// Requests written while the ledger is locked, such as 「確認」 tapped on
/// a notification, kept until the ledger opens. Anything may write one
/// with the public key, which is kept in the clear; only the open ledger
/// can read them, with the private key, which is sealed with the ledger's
/// own key. A writer cannot read what it or anyone else wrote.
///
/// Each item is sealed for the inbox key: a new X25519 key pair for the
/// item, the shared secret through HKDF-SHA256 (salted with both public
/// keys) to an AES-256-GCM key. On disk, one JSON file per item:
/// `{"v":1,"e":<the item's public key>,"n":<nonce>,"c":<ciphertext and
/// tag>}`, all base64. The Android side (InboxWriter.kt) writes the same.
final class InboxSeal {
  InboxSeal._();

  static const version = 1;
  static final info = utf8.encode('ExpenseTracker inbox v1');
  static final _exchange = X25519();
  static final _cipher = AesGcm.with256bits();

  static Future<SecretKey> _key(
    SecretKey shared,
    List<int> itemPublic,
    List<int> inboxPublic,
  ) => Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
    secretKey: shared,
    nonce: [...itemPublic, ...inboxPublic],
    info: info,
  );

  /// Seals [plain] for the inbox whose public key is [inboxPublic]. The
  /// item's key pair and nonce are new each time unless given, for tests.
  static Future<String> seal(
    List<int> inboxPublic,
    List<int> plain, {
    SimpleKeyPair? itemKeys,
    List<int>? nonce,
  }) async {
    final keys = itemKeys ?? await _exchange.newKeyPair();
    final itemPublic = (await keys.extractPublicKey()).bytes;
    final shared = await _exchange.sharedSecretKey(
      keyPair: keys,
      remotePublicKey: SimplePublicKey(inboxPublic, type: KeyPairType.x25519),
    );
    final key = await _key(shared, itemPublic, inboxPublic);
    final box = await _cipher.encrypt(
      plain,
      secretKey: key,
      nonce: nonce ?? _cipher.newNonce(),
      aad: info,
    );
    return jsonEncode({
      'v': version,
      'e': base64.encode(itemPublic),
      'n': base64.encode(box.nonce),
      'c': base64.encode([...box.cipherText, ...box.mac.bytes]),
    });
  }

  /// Opens an item sealed for [inboxKeys]; throws [FormatException] for
  /// one that is not an item, and [SecretBoxAuthenticationError] for one
  /// sealed for another key or changed.
  static Future<Uint8List> open(SimpleKeyPair inboxKeys, String item) async {
    final Object? json;
    try {
      json = jsonDecode(item);
    } on FormatException {
      throw const FormatException('Not an inbox item.');
    }
    if (json is! Map<String, Object?> || json['v'] != version) {
      throw const FormatException('Not an inbox item.');
    }
    final Map<String, Object?> fields = json;
    List<int> bytes(String name, {int? length}) {
      final value = fields[name];
      if (value is! String) throw const FormatException('Not an inbox item.');
      final decoded = base64.decode(value);
      if (length != null && decoded.length != length) {
        throw const FormatException('Not an inbox item.');
      }
      return decoded;
    }

    final itemPublic = bytes('e', length: 32);
    final nonce = bytes('n', length: 12);
    final sealed = bytes('c');
    if (sealed.length < 16) throw const FormatException('Not an inbox item.');
    final inboxPublic = (await inboxKeys.extractPublicKey()).bytes;
    final shared = await _exchange.sharedSecretKey(
      keyPair: inboxKeys,
      remotePublicKey: SimplePublicKey(itemPublic, type: KeyPairType.x25519),
    );
    final key = await _key(shared, itemPublic, inboxPublic);
    final plain = await _cipher.decrypt(
      SecretBox(
        sealed.sublist(0, sealed.length - 16),
        nonce: nonce,
        mac: Mac(sealed.sublist(sealed.length - 16)),
      ),
      secretKey: key,
      aad: info,
    );
    return Uint8List.fromList(plain);
  }
}

/// One item read from the inbox: its file name, to remove it once dealt
/// with, and what it says; null when it could not be opened (sealed for
/// another ledger, or damaged).
typedef InboxItem = ({String name, Uint8List? plain});

/// The inbox of the ledger in [directory]: `inbox.pub` (the public key,
/// base64), `inbox.key` (the private key, sealed by [FileBox]) and the
/// items in `inbox/`.
final class LedgerInbox {
  LedgerInbox._(this.directory, this._keys);

  final Directory directory;
  final SimpleKeyPair _keys;

  static File _public(Directory d) => File('${d.path}/inbox.pub');
  static File _private(Directory d) => File('${d.path}/inbox.key');
  static Directory folder(Directory d) => Directory('${d.path}/inbox');

  /// The inbox of the open ledger [keys]: its key pair, made the first
  /// time, or again when the kept one does not open with this ledger
  /// (after a restore of another ledger); the public key is written
  /// afresh each time, so a writer always has this ledger's.
  static Future<LedgerInbox> open(
    Directory directory,
    UnlockedKeyring keys,
  ) async {
    final box = await FileBox.derive(keys, 'inbox');
    final privateFile = _private(directory);
    SimpleKeyPair? kept;
    if (privateFile.existsSync()) {
      try {
        final seed = await box.open('inbox.key', privateFile.readAsBytesSync());
        kept = await X25519().newKeyPairFromSeed(seed);
      } on Object {
        // Sealed by another ledger: a new pair below.
      }
    }
    final pair = kept ?? await X25519().newKeyPair();
    if (kept == null) {
      final seed = await pair.extractPrivateKeyBytes();
      await _write(privateFile, await box.seal('inbox.key', seed));
    }
    final public = (await pair.extractPublicKey()).bytes;
    await _write(_public(directory), utf8.encode(base64.encode(public)));
    return LedgerInbox._(directory, pair);
  }

  /// Written beside, then renamed over: a reader never sees half a file.
  static Future<void> _write(File file, List<int> bytes) async {
    await file.parent.create(recursive: true);
    final next = File('${file.path}.${Random.secure().nextInt(1 << 30)}.new');
    await next.writeAsBytes(bytes, flush: true);
    await next.rename(file.path);
  }

  /// Every item waiting, oldest first (names start with the time written).
  Future<List<InboxItem>> read() async {
    final items = folder(directory);
    if (!items.existsSync()) return const [];
    final files = [
      for (final f in items.listSync())
        if (f is File && f.path.endsWith('.json')) f,
    ]..sort((a, b) => a.path.compareTo(b.path));
    return [
      for (final file in files)
        (
          name: file.uri.pathSegments.last,
          plain: await _openOrNull(file.readAsStringSync()),
        ),
    ];
  }

  Future<Uint8List?> _openOrNull(String text) async {
    try {
      return await InboxSeal.open(_keys, text);
    } on Object {
      return null;
    }
  }

  /// Takes an item away once dealt with.
  Future<void> remove(String name) async {
    final file = File('${folder(directory).path}/$name');
    if (file.existsSync()) await file.delete();
  }

  /// Writes [plain] into the inbox of the ledger in [directory] with the
  /// public key alone, as a writer without the ledger does.
  static Future<void> post(Directory directory, List<int> plain) async {
    final public = base64.decode(_public(directory).readAsStringSync().trim());
    final item = await InboxSeal.seal(public, plain);
    final name =
        '${DateTime.now().toUtc().millisecondsSinceEpoch}-'
        '${Random.secure().nextInt(1 << 30)}.json';
    await _write(File('${folder(directory).path}/$name'), utf8.encode(item));
  }
}
