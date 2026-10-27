import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:test/test.dart';
import 'package:vault/backup_security.dart';

/// Worked out with another X25519, HKDF and AES-GCM (Python's
/// `cryptography`), and checked on the Android side too
/// (InboxWriterTest.kt): the same item opens on both.
const _inboxPrivate = 'AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA=';
const _inboxPublic = 'B6N8vBQgk8i3VdwbEOhstCY3StFqqFPtC9/AsrhtHHw=';
const _itemPrivate = 'ZWZnaGlqa2xtbm9wcXJzdHV2d3h5ent8fX5/gIGCg4Q=';
const _itemPublic = 'VxR2nRFr92Q2rnS8eT0sMK0ZA8WaxSc4BcfiaYtBDDY=';
const _nonce = 'ycrLzM3Oz9DR0tPU';
const _sealed =
    'HtcnNKNt1m7fmuETvVKWVJ3vZ/vHeIkMg/P2uPSSG9B9+le7i4vK/y4ynueKJGtErAxwnhvKL8EPCyzdLwQ5gAkm+vGCSw==';
const _plain = '{"kind":"confirm","recurring":"r1","day":"2026-10-05"}';

void main() {
  final codec = KeyringCodec(kdf: PasswordKdf.insecureForTests);
  late Directory directory;

  setUp(() => directory = Directory.systemTemp.createTempSync('inbox-'));
  tearDown(() => directory.deleteSync(recursive: true));

  Future<SimpleKeyPair> pair(String seed) =>
      X25519().newKeyPairFromSeed(base64.decode(seed));

  test('the worked example seals and opens the same', () async {
    final inbox = await pair(_inboxPrivate);
    expect(base64.encode((await inbox.extractPublicKey()).bytes), _inboxPublic);
    final item = await InboxSeal.seal(
      base64.decode(_inboxPublic),
      utf8.encode(_plain),
      itemKeys: await pair(_itemPrivate),
      nonce: base64.decode(_nonce),
    );
    expect(jsonDecode(item), {
      'v': 1,
      'e': _itemPublic,
      'n': _nonce,
      'c': _sealed,
    });
    expect(utf8.decode(await InboxSeal.open(inbox, item)), _plain);
  });

  test('an item opens only with its inbox key, and unchanged', () async {
    final inbox = await pair(_inboxPrivate);
    final other = await X25519().newKeyPair();
    final item = await InboxSeal.seal(
      base64.decode(_inboxPublic),
      utf8.encode(_plain),
    );
    await expectLater(InboxSeal.open(other, item), throwsA(anything));
    final json = jsonDecode(item) as Map<String, Object?>;
    final bytes = base64.decode(json['c']! as String);
    bytes[0] ^= 1;
    final changed = jsonEncode({...json, 'c': base64.encode(bytes)});
    await expectLater(InboxSeal.open(inbox, changed), throwsA(anything));
    await expectLater(InboxSeal.open(inbox, '{"v":2}'), throwsFormatException);
  });

  test(
    'a writer posts with the public key; the ledger reads and removes',
    () async {
      final keys = (await codec.create('inbox password')).unlocked;
      final inbox = await LedgerInbox.open(directory, keys);
      await LedgerInbox.post(directory, utf8.encode('first'));
      await LedgerInbox.post(directory, utf8.encode('second'));
      File('${LedgerInbox.folder(directory).path}/0-junk.json')
          .writeAsStringSync('not an item');

      final items = await inbox.read();
      expect(items, hasLength(3));
      expect(items.first.plain, isNull, reason: 'the junk sorts first');
      expect(
        [for (final i in items.skip(1)) utf8.decode(i.plain!)],
        ['first', 'second'],
      );
      for (final i in items) {
        await inbox.remove(i.name);
      }
      expect(await inbox.read(), isEmpty);
    },
  );

  test('the same ledger keeps its key; another ledger makes its own', () async {
    final keys = (await codec.create('inbox password')).unlocked;
    await LedgerInbox.open(directory, keys);
    final public = File('${directory.path}/inbox.pub').readAsStringSync();
    await LedgerInbox.post(directory, utf8.encode('kept'));

    final again = await LedgerInbox.open(directory, keys);
    expect(File('${directory.path}/inbox.pub').readAsStringSync(), public);
    expect(utf8.decode((await again.read()).single.plain!), 'kept');

    // Another ledger restored here: its own pair; the old item no longer
    // opens and is left to be cleared.
    final other = (await codec.create('other password')).unlocked;
    final theirs = await LedgerInbox.open(directory, other);
    expect(
      File('${directory.path}/inbox.pub').readAsStringSync(),
      isNot(public),
    );
    expect((await theirs.read()).single.plain, isNull);
  });
}
