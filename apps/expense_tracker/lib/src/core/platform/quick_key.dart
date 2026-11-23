import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:vault/backup_security.dart';

/// The key of a ledger opened without a password, kept beside it sealed
/// by the phone's Keystore ([keystore]), never in plain form: on Android a
/// key that needs no fingerprint, so the ledger opens by itself while a
/// copy of the folder alone opens nothing.
final class QuickKey {
  QuickKey(this.directory, this.keystore);

  final Directory directory;
  final DeviceKeyWrapper keystore;

  static final _context = utf8.encode('expense_tracker/quick-open');

  /// The sealed key.
  File get sealed => File('${directory.path}/quick-open.sealed');

  /// Where versions before 0.23 kept the key in plain form. Read once,
  /// sealed, then overwritten and deleted ([secret]).
  File get plain => File('${directory.path}/quick-open.key');

  /// A new sealed key written before the keys are reset, named over
  /// [sealed] after.
  File get next => File('${sealed.path}.next');

  /// A sealed key kept aside until the ledger it opens exists.
  File get pending => File('${sealed.path}.new');

  File get _plainPending => File('${plain.path}.new');

  /// Whether a key is kept: the ledger has no password.
  bool get exists => sealed.existsSync() || plain.existsSync();

  /// Seals [secret] into [file], written in full before anything names it.
  Future<void> write(File file, String secret) async {
    final blob = await keystore.wrap(utf8.encode(secret), _context);
    await file.writeAsBytes(blob, flush: true);
  }

  /// The key sealed in [file].
  Future<String> read(File file) async =>
      utf8.decode(await keystore.unwrap(await file.readAsBytes(), _context));

  /// Seals [secret] aside, then names it the key.
  Future<void> keep(String secret) async {
    await write(pending, secret);
    await pending.rename(sealed.path);
  }

  /// The key. One kept in plain form by an earlier version is sealed now,
  /// and the plain file overwritten and deleted.
  Future<String> secret() async {
    if (plain.existsSync()) {
      final secret = (await plain.readAsString()).trim();
      await keep(secret);
      await shred(plain);
      return secret;
    }
    return read(sealed);
  }

  /// Drops every copy of the key, the plain one overwritten first.
  Future<void> forget() async {
    await shred(plain);
    for (final file in [sealed, next, pending]) {
      if (await file.exists()) await file.delete();
    }
  }

  /// A set-up without a password stopped part way: the key kept aside
  /// is the ledger's when the ledger was made ([ledgerExists]), and
  /// nothing otherwise. A plain one left by an earlier version is never
  /// kept for a ledger not made: it is overwritten and removed.
  void settle({required bool ledgerExists}) {
    if (pending.existsSync()) {
      if (ledgerExists && !exists) {
        pending.renameSync(sealed.path);
      } else {
        pending.deleteSync();
      }
    }
    final plainPending = _plainPending;
    if (plainPending.existsSync()) {
      if (ledgerExists && !exists) {
        // Sealed when the ledger opens ([secret]).
        plainPending.renameSync(plain.path);
      } else {
        plainPending
          ..writeAsBytesSync(Uint8List(plainPending.lengthSync()), flush: true)
          ..deleteSync();
      }
    }
  }

  /// Overwrites [file] with zeros before deleting it, so its words are
  /// not left in the free space of the file system it was on.
  static Future<void> shred(File file) async {
    if (!file.existsSync()) return;
    final length = await file.length();
    await file.writeAsBytes(Uint8List(length), flush: true);
    await file.delete();
  }
}
