import 'dart:io';
import 'dart:math' show max;

import 'package:storage/storage.dart';
import 'package:vault/backup_security.dart';

enum VaultProblem {
  /// [LedgerVault.create] found a ledger already on this device.
  alreadyExists,

  /// No ledger on this device yet.
  missing,

  /// The keyring file cannot be read.
  damagedKeyring,

  /// A keyring for another ledger was offered.
  otherLedger,

  /// A restored database failed its checks; nothing was kept.
  damagedRestore,

  /// The keyring is here but the ledger's database is gone: opening would
  /// start an empty ledger as if nothing had been kept, so it is refused.
  missingDatabase,
}

final class VaultException implements Exception {
  const VaultException(this.problem);

  final VaultProblem problem;

  @override
  String toString() => 'VaultException(${problem.name})';
}

/// An unlocked ledger: its keys and its open database.
final class OpenVault {
  OpenVault._(this._vault, this._keys, this.store);

  final LedgerVault _vault;
  UnlockedKeyring _keys;
  final EncryptedDatabase store;

  UnlockedKeyring get keys => _keys;

  /// Stores a changed keyring, such as a new password or device, and uses
  /// it from now on.
  Future<void> updateKeys(UnlockedKeyring keys) async {
    await _vault.save(keys);
    _keys = keys;
  }

  void close() => store.close();
}

/// The ledger's files on this device: `keyring.json` next to `ledger.db`.
///
/// The keyring holds the database key wrapped by the password, the
/// recovery code and any device keys, so the database opens even if the
/// device key is lost, and nothing secret is kept in plain form. The
/// keyring file is replaced atomically.
final class LedgerVault {
  LedgerVault(
    this.directory, {
    required this.codec,
    this.now = DateTime.now,
    this.noteFailed,
  });

  final Directory directory;
  final KeyringCodec codec;

  /// The time a damaged database is set aside at ([setAsideDamaged]):
  /// the app's clock, where the app is put together.
  final DateTime Function() now;

  /// Told when the note that records were kept here ([_recordsKept])
  /// could not be written as a write was kept: the write stands, and the
  /// note is tried again at the next write and the next opening.
  final void Function(Object error, StackTrace stack)? noteFailed;

  File get keyringFile => File('${directory.path}/keyring.json');
  File get databaseFile => File('${directory.path}/ledger.db');
  File get _pending => File('${directory.path}/keyring.json.new');

  /// Kept once records were first written to the database here: without
  /// it, a database of no bytes was cut short before it held anything (a
  /// first launch interrupted), and opens as a new book (D102).
  File get _recordsKept => File('${directory.path}/ledger.db.kept');

  /// Kept when the journal's tables were found damaged: the next opening
  /// makes the database again from its records first ([salvage]).
  File get _journalDamaged => File('${directory.path}/journal.damaged');

  /// A ledger is here: its keyring, or a complete replacement that a
  /// crash left before the rename. A half-written first keyring is not a
  /// ledger, so setup can start again.
  bool get exists => keyringFile.existsSync() || _completePending();

  bool _completePending() {
    if (!_pending.existsSync()) return false;
    try {
      Keyring.parse(_pending.readAsStringSync());
      return true;
    } on KeyringException {
      return false;
    } on FormatException {
      return false;
    }
  }

  /// First launch. Returns the vault and the recovery code, which is shown
  /// once and never stored.
  Future<(OpenVault, String)> create(String password) async {
    _requireAbsent();
    final created = await codec.create(password);
    return (await adopt(created.unlocked), created.recoveryCode);
  }

  /// A new device restoring a backup: the keyring comes from the backup
  /// header, already unlocked with the password or recovery code.
  Future<OpenVault> adopt(UnlockedKeyring keys) async {
    _requireAbsent();
    await directory.create(recursive: true);
    if (await databaseFile.exists()) await databaseFile.delete();
    // A new ledger: no records were written to it yet, nor a journal
    // found damaged in it.
    if (await _recordsKept.exists()) await _recordsKept.delete();
    if (await _journalDamaged.exists()) await _journalDamaged.delete();
    // The database first, then the keyring: a keyring without a database
    // then always means the database was lost (see [missingDatabase]).
    _openStore(databaseFile, keys).close();
    await _write(keys.keyring);
    return _open(keys);
  }

  Future<OpenVault> unlockWithPassword(String password) async {
    final keyring = await _keyring();
    return _openKept(await codec.unlockWithPassword(keyring, password));
  }

  Future<OpenVault> unlockWithRecovery(String recoveryCode) async {
    final keyring = await _keyring();
    return _openKept(await codec.unlockWithRecovery(keyring, recoveryCode));
  }

  /// Opens with the backup passphrase, as a ledger restored from a backup
  /// does until a password is set for it.
  Future<OpenVault> unlockWithPassphrase(String passphrase) async {
    final keyring = await _keyring();
    return _openKept(await codec.unlockWithPassphrase(keyring, passphrase));
  }

  Future<OpenVault> unlockWithDevice(
    String deviceId,
    DeviceKeyWrapper wrapper,
  ) async {
    final keyring = await _keyring();
    return _openKept(await codec.unlockWithDevice(keyring, deviceId, wrapper));
  }

  /// Opens the ledger again with [keys] it was open with a moment ago,
  /// as when a restore from settings is given up: nothing is typed again.
  /// The keys must be this ledger's as it is kept now.
  Future<OpenVault> reopen(UnlockedKeyring keys) async {
    final keyring = await _keyring();
    if (keyring.id != keys.keyring.id) {
      throw const VaultException(VaultProblem.otherLedger);
    }
    return _openKept(keys);
  }

  /// Stores a changed keyring: a new password, recovery code, device or
  /// backup key. It must belong to this ledger.
  Future<void> save(UnlockedKeyring keys) async {
    final current = await _keyring();
    if (current.id != keys.keyring.id) {
      throw const VaultException(VaultProblem.otherLedger);
    }
    await _write(keys.keyring);
  }

  void _requireAbsent() {
    if (exists) throw const VaultException(VaultProblem.alreadyExists);
  }

  File get _staging => File('${directory.path}/ledger.db.restore');

  /// The sealed receipt photos kept beside the ledger, each sealed by a
  /// [FileBox] of purpose `receipts` under its file name.
  Directory get receiptsDirectory => Directory('${directory.path}/receipts');

  /// Files a [restore] or [resetKeys] puts beside the ledger, each at its
  /// path under [directory] (such as `receipts/r1.etr`). Written while
  /// the staging database is filled, and moved into place with it, after
  /// its check: never before, so a restore that fails keeps the photos
  /// here as they were.
  Directory get stagedFiles => Directory('${directory.path}/files.restore');

  /// The files [stagedFiles] replaced, until the move is done.
  Directory get _replacedFiles => Directory('${directory.path}/files.replaced');

  /// Finishes, or undoes, what a crash during [restore], [resetKeys] or
  /// [_write] left part way, so the keyring, the database and the files
  /// beside it belong together:
  ///
  /// - the copy still waiting beside a database: the restore had not
  ///   begun replacing, so the copy, its files and its keyring go and the
  ///   ledger here stays as it was;
  /// - the copy waiting and no database: the old one was already gone,
  ///   so the copy goes into place, then its files, with the keyring
  ///   written for it;
  /// - no copy and a complete new keyring: the database is the new one
  ///   (or the same, for a changed password), so its files go into place
  ///   and the new keyring is used.
  Future<void> _settle() async {
    if (await _staging.exists()) {
      if (!await databaseFile.exists() && _completePending()) {
        await _staging.rename(databaseFile.path);
      } else {
        await _dropStagedFiles();
        await _deleteDatabase(_staging);
        if (await keyringFile.exists() && await _pending.exists()) {
          await _pending.delete();
        }
        return;
      }
    }
    if (_completePending()) {
      await _placeStagedFiles();
      if (await keyringFile.exists()) await _pending.rename(keyringFile.path);
    } else {
      // Files of a copy that never went into place.
      await _dropStagedFiles();
    }
  }

  /// Moves every file of [stagedFiles] into place, the one it replaces
  /// first aside into [_replacedFiles], then lets those go. Done again
  /// after a crash, it picks up where it stopped.
  Future<void> _placeStagedFiles() async {
    final staged = stagedFiles;
    if (await staged.exists()) {
      final files = [
        for (final entity in staged.listSync(recursive: true))
          if (entity is File) entity,
      ]..sort((a, b) => a.path.compareTo(b.path));
      for (final file in files) {
        final path = file.path.substring(staged.path.length + 1);
        final target = File('${directory.path}/$path');
        if (await target.exists()) {
          final aside = File('${_replacedFiles.path}/$path');
          await aside.parent.create(recursive: true);
          await target.rename(aside.path);
        }
        await target.parent.create(recursive: true);
        await file.rename(target.path);
      }
      await staged.delete(recursive: true);
    }
    if (await _replacedFiles.exists()) {
      await _replacedFiles.delete(recursive: true);
    }
  }

  Future<void> _dropStagedFiles() async {
    if (await stagedFiles.exists()) await stagedFiles.delete(recursive: true);
    if (await _replacedFiles.exists()) {
      await _replacedFiles.delete(recursive: true);
    }
  }

  Future<Keyring> _keyring() async {
    await _settle();
    if (!await keyringFile.exists()) {
      // A crash during the replace leaves only the new file behind.
      if (!_completePending()) {
        throw const VaultException(VaultProblem.missing);
      }
      await _placeStagedFiles();
      await _pending.rename(keyringFile.path);
    }
    try {
      return Keyring.parse(await keyringFile.readAsString());
    } on KeyringException {
      throw const VaultException(VaultProblem.damagedKeyring);
    } on FormatException {
      throw const VaultException(VaultProblem.damagedKeyring);
    }
  }

  /// Writes the new file in full, then renames it over the old one, so a
  /// crash leaves either the old keyring or the new one, never half.
  Future<void> _write(Keyring keyring) async {
    await _pending.writeAsString(keyring.encode(), flush: true);
    await _pending.rename(keyringFile.path);
  }

  /// Restores a backup as this device's ledger, all or nothing. [fill]
  /// writes into a staging database, which must pass SQLite's integrity
  /// check, and puts the files the backup carries into [stagedFiles].
  /// Only then is its keyring written beside the old one, the database
  /// renamed into place, then the files, and the keyring, which is what
  /// makes a ledger exist, named last. A failure before the check leaves
  /// things as they were, the photos too; a crash after it is finished on
  /// the next open ([_settle]).
  ///
  /// With [replacing], a closed ledger already here is replaced, as when
  /// a backup is restored from settings: until the copy has passed its
  /// check the old ledger is untouched, and a failure before then keeps
  /// it. The app keeps a backup of it first.
  Future<OpenVault> restore(
    UnlockedKeyring keys,
    Future<void> Function(EncryptedDatabase staging) fill, {
    bool replacing = false,
  }) async {
    if (!replacing) _requireAbsent();
    await _replace(keys, fill);
    // The backup is in place: copies set aside as damaged before it are
    // let go of but the newest few (D102), and a journal found damaged
    // went with the database it was in.
    await pruneDamagedCopies();
    if (await _journalDamaged.exists()) await _journalDamaged.delete();
    return _open(keys);
  }

  /// Replaces every key of the ledger [open] with [next]
  /// ([UnlockedKeyring.reset]): the database is copied, record by record,
  /// into a new one encrypted with the new database key, and the receipt
  /// photos and the inbox key are sealed again under it, the same staged
  /// and checked way as [restore], so a crash at any step leaves either
  /// the old ledger with its old keys or the new one with its new keys.
  /// [open] is closed once the copy has passed its check; on a failure
  /// before then it stays open and nothing changed.
  ///
  /// Afterwards the old keyring, as an older backup carries it, opens
  /// only the old keys: no longer this database or these photos.
  Future<OpenVault> resetKeys(OpenVault open, UnlockedKeyring next) async {
    final old = open.keys;
    if (open._vault != this || next.keyring.id != old.keyring.id) {
      throw const VaultException(VaultProblem.otherLedger);
    }
    await _replace(next, (staging) async {
      final rows = open.store.rows();
      // Written on a worker isolate, so a large book does not hold the
      // screen still while it is copied (DAT-03).
      await staging.writeApart([
        for (final row in rows) RowChange.put(row.shelf, row.id, row.body),
      ]);
      // The book's version goes with its records, so the book re-keyed is
      // not brought up again, nor copied first as before an upgrade. The
      // layout needs nothing: both files are at this build's.
      if (open.store.meta(EncryptedDatabase.bookVersionKey) case final book?) {
        staging.write(
          (w) => w.setMeta(EncryptedDatabase.bookVersionKey, book),
          counts: false,
        );
      }
      await _sealAgain(old, next);
    }, beforeSwap: open.close);
    return _open(next);
  }

  /// Seals the receipt photos and the inbox key again, from the box of
  /// [old] to that of [next], into [stagedFiles]. A file the old box does
  /// not open (not this ledger's) is left as it is.
  Future<void> _sealAgain(UnlockedKeyring old, UnlockedKeyring next) async {
    final receipts = receiptsDirectory;
    if (await receipts.exists()) {
      final from = await FileBox.derive(old, 'receipts');
      final to = await FileBox.derive(next, 'receipts');
      for (final entity in receipts.listSync()) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        final List<int> plain;
        try {
          plain = await from.open(name, await entity.readAsBytes());
        } on Object {
          continue;
        }
        final staged = File('${stagedFiles.path}/receipts/$name');
        await staged.parent.create(recursive: true);
        await staged.writeAsBytes(await to.seal(name, plain), flush: true);
      }
    }
    // The inbox's private key (LedgerInbox), so what was posted while
    // locked still opens.
    const inboxKey = 'inbox.key';
    final inbox = File('${directory.path}/$inboxKey');
    if (await inbox.exists()) {
      try {
        final from = await FileBox.derive(old, 'inbox');
        final to = await FileBox.derive(next, 'inbox');
        final seed = await from.open(inboxKey, await inbox.readAsBytes());
        await stagedFiles.create(recursive: true);
        await File('${stagedFiles.path}/$inboxKey')
            .writeAsBytes(await to.seal(inboxKey, seed), flush: true);
      } on Object {
        // Not this ledger's: the inbox makes a new one when it opens.
      }
    }
  }

  /// Fills a staging database and [stagedFiles], checks it, then puts
  /// both in place with [keys]' keyring (see [restore]). [beforeSwap]
  /// runs once the copy is checked, before anything here changes.
  ///
  /// With [keepOld], the database replaced is set aside as damaged
  /// ([setAsideDamaged]) rather than let go of.
  Future<void> _replace(
    UnlockedKeyring keys,
    Future<void> Function(EncryptedDatabase staging) fill, {
    void Function()? beforeSwap,
    bool keepOld = false,
  }) async {
    await directory.create(recursive: true);
    final staging = _staging;
    await _dropStagedFiles();
    await _deleteDatabase(staging);
    var committed = false;
    try {
      final store = _openStore(staging, keys);
      try {
        await fill(store);
        // On a worker: a large copy is checked without holding the
        // screen still.
        if (await store.workApart(_checked) != 'ok') {
          throw const VaultException(VaultProblem.damagedRestore);
        }
      } finally {
        store.close();
      }
      if (await File('${staging.path}-wal').exists()) {
        throw const VaultException(VaultProblem.damagedRestore);
      }
      // The new keyring is written in full before the database changes,
      // and named last: a crash between any two steps leaves what
      // [_settle] can finish or undo, never a keyring, a database and
      // files that do not belong together.
      await _pending.writeAsString(keys.keyring.encode(), flush: true);
      beforeSwap?.call();
      committed = true;
      if (keepOld) {
        await setAsideDamaged();
      } else {
        await _deleteDatabase(databaseFile);
      }
      await staging.rename(databaseFile.path);
      // The copy holds records: a database here of no bytes from now on is
      // damage, not a first launch cut short.
      await _noteRecordsKept();
      await _placeStagedFiles();
      await _pending.rename(keyringFile.path);
    } on Object {
      // Once the old database is gone, only going forward is left: the
      // next open finishes it ([_settle]).
      if (!committed) {
        await _dropStagedFiles();
        await _deleteDatabase(staging);
        // Written by this call, for a copy that does not go in.
        if (await _pending.exists()) await _pending.delete();
        if (!exists) await _deleteDatabase(databaseFile);
      }
      rethrow;
    }
  }

  /// Opens the ledger kept here, which must still have its database. One
  /// set aside as damaged, and not yet replaced by a backup, is still
  /// damaged (D94): opening never starts an empty book in its place.
  ///
  /// A database of no bytes that never held a record ([_recordsKept]) is
  /// a first launch cut short: it opens as the new book it was to be. One
  /// whose journal was found damaged is made again from its records first
  /// ([salvage]).
  Future<OpenVault> _openKept(UnlockedKeyring keys) async {
    if (!await databaseFile.exists()) {
      if (damagedCopies().isNotEmpty) {
        throw const StorageUnavailable(StorageProblem.damaged);
      }
      throw const VaultException(VaultProblem.missingDatabase);
    }
    if (!await _recordsKept.exists() &&
        await databaseFile.length() == 0 &&
        EncryptedDatabase.cutShort(databaseFile)) {
      await _deleteDatabase(databaseFile);
    } else if (await _journalDamaged.exists()) {
      // Made again where the records can be read; else opened as it is,
      // and found damaged as it is read.
      await salvage(keys);
    }
    return _open(keys);
  }

  /// Notes that the journal's tables of the database here were found
  /// damaged, so the next opening makes it again from its records
  /// ([salvage]), should this session not get to it.
  Future<void> noteJournalDamaged() async {
    await directory.create(recursive: true);
    await _journalDamaged.writeAsString('', flush: true);
  }

  /// Makes the database here again from its records alone, closed (D102):
  /// a page found damaged in the journal's tables, which are derived from
  /// the records and posted afresh when missing, costs nothing kept.
  /// Every record and the book's version are read from it on a worker,
  /// so a large book does not hold the screen still, and written into a
  /// new database, checked and put in its place as a restore is
  /// ([restore]). The old file is set aside as damaged
  /// ([setAsideDamaged]), so it can still be sent for a look; once the
  /// book made again has opened, the copies are let go of but the newest
  /// [keptDamagedCopies] and those set aside since the book last opened
  /// ([pruneDamagedCopies]). Whether it was made again: false when the
  /// records themselves cannot be read whole, the database then left
  /// exactly as it was.
  Future<bool> salvage(UnlockedKeyring keys) async {
    final (List<RowChange>, int?) kept;
    try {
      final old = _openStore(databaseFile, keys);
      try {
        kept = await old.readApart(_keptOf);
      } finally {
        old.close();
      }
    } on StorageUnavailable catch (error) {
      if (error.problem == StorageProblem.damaged) return false;
      rethrow;
    }
    final (changes, book) = kept;
    await _replace(keys, (staging) async {
      await staging.writeApart(changes);
      if (book != null) {
        staging.write(
          (w) => w.setMeta(EncryptedDatabase.bookVersionKey, book),
          counts: false,
        );
      }
    }, keepOld: true);
    if (await _journalDamaged.exists()) await _journalDamaged.delete();
    _salvagedUnopened = true;
    return true;
  }

  /// A book made again ([salvage]) and not yet opened: once it opens, the
  /// copies set aside are let go of but the newest few.
  var _salvagedUnopened = false;

  /// The records of [snapshot] as changes that put them in a new
  /// database, and the book's version: run on the worker that read them.
  static Future<(List<RowChange>, int?)> _keptOf(
    StoreSnapshot snapshot,
  ) async => (
    [
      for (final row in snapshot.rows)
        RowChange.put(row.shelf, row.id, row.body),
    ],
    snapshot.book,
  );

  /// [ApartStore.integrityCheck], run on the worker.
  static Future<String> _checked(ApartStore store) async =>
      store.integrityCheck();

  Future<OpenVault> _open(UnlockedKeyring keys) async {
    try {
      final store = _openStore(databaseFile, keys);
      try {
        // Kept by a version before the note: a book written to has them
        // (read from the store's own numbers, not its records).
        if (store.revision > 0) await _noteRecordsKept();
      } on Object {
        store.close();
        rethrow;
      }
      if (_salvagedUnopened) {
        try {
          await pruneDamagedCopies();
          _salvagedUnopened = false;
        } on FileSystemException {
          // Let go of at the next opening, or the next restore.
        }
      }
      // The book opened: copies set aside before now may be let go of.
      _asideSinceOpen.clear();
      return OpenVault._(this, keys, store);
    } on StorageUnavailable catch (error) {
      if (error.problem == StorageProblem.damaged) {
        // Kept aside as it is, never written over nor erased: a restore
        // then puts the backup where it was.
        await setAsideDamaged();
        rethrow;
      }
      if (error.problem != StorageProblem.oldFormat) rethrow;
    }
    // A ledger from before records were kept as rows cannot be read: it
    // is set aside, never erased, and the keys open a new, empty one.
    for (final suffix in ['', '-wal', '-shm']) {
      final part = File('${databaseFile.path}$suffix');
      if (await part.exists()) {
        await part.rename('${directory.path}/ledger-v2.db$suffix');
      }
    }
    return OpenVault._(this, keys, _openStore(databaseFile, keys));
  }

  /// Every key here comes from the keyring's authenticated unwrap: the
  /// database's own, so a first page it does not open is damage, not a
  /// wrong key (EncryptedDatabase.open).
  EncryptedDatabase _openStore(File file, UnlockedKeyring keys) =>
      EncryptedDatabase.open(
        file,
        StorageKey(keys.databaseKey),
        keyVouched: true,
        written: file.path == databaseFile.path ? _noteRecordsKeptNow : null,
        writtenFailed: noteFailed,
      );

  /// Notes that the database here has held records ([_recordsKept]).
  Future<void> _noteRecordsKept() async {
    if (!await _recordsKept.exists()) {
      await _recordsKept.writeAsString('', flush: true);
    }
  }

  /// [_noteRecordsKept] from a write as it is kept, before the next.
  void _noteRecordsKeptNow() {
    if (!_recordsKept.existsSync()) {
      _recordsKept.writeAsStringSync('', flush: true);
    }
  }

  /// How a database set aside as damaged is named, before its number
  /// and time.
  static const _damagedPrefix = 'ledger-damaged-';

  /// A copy's number, after [_damagedPrefix]: one more than any copy
  /// here, so the order copies were set aside in never hangs on the
  /// phone's clock, which can be set back (review 25).
  static final _numbered = RegExp(r'^ledger-damaged-n(\d+)-');

  /// How many digits a copy's number is written with, so names sort as
  /// numbers do in a file list.
  static const _numberDigits = 6;

  /// How many copies set aside as damaged a restore leaves, the newest
  /// ([pruneDamagedCopies]).
  static const keptDamagedCopies = 2;

  /// The copies set aside since the book here last opened: never let go
  /// of, the newest damage being the one to send for a look whatever
  /// the clock said (review 25). Held in memory: a restart before the
  /// next opening leaves the next prune to keep the newest few only.
  final _asideSinceOpen = <String>{};

  /// Lets go of the copies set aside as damaged but the newest
  /// [keptDamagedCopies], each with its log: once a backup is restored,
  /// older ones are of no more use than the newest to send for a look.
  /// One set aside since the book last opened is kept all the same.
  Future<void> pruneDamagedCopies() async {
    final copies = damagedCopies();
    if (copies.length <= keptDamagedCopies) return;
    for (final copy in copies.take(copies.length - keptDamagedCopies)) {
      if (_asideSinceOpen.contains(copy.path)) continue;
      await _deleteDatabase(copy);
    }
  }

  /// Sets the database here aside as damaged (D94), with its log, under
  /// a name of the next number and the time it was ([damagedCopies]):
  /// never erased, so it can still be sent for a look; the ledger then
  /// has no database until a backup is restored. Its path; null when
  /// there was none to set aside.
  Future<File?> setAsideDamaged() async {
    if (!await databaseFile.exists()) return null;
    // 2026-11-24T09:58:50.578Z, with no colon, which some file systems
    // refuse.
    final at = now().toUtc().toIso8601String().replaceAll(':', '-');
    var number = damagedCopies().fold(0, (high, f) => max(high, _numberOf(f)));
    File aside;
    do {
      number++;
      final digits = '$number'.padLeft(_numberDigits, '0');
      aside = File('${directory.path}/${_damagedPrefix}n$digits-$at.db');
    } while (await aside.exists());
    for (final suffix in ['', '-wal', '-shm']) {
      final part = File('${databaseFile.path}$suffix');
      if (await part.exists()) await part.rename('${aside.path}$suffix');
    }
    _asideSinceOpen.add(aside.path);
    return aside;
  }

  /// The number [copy] was set aside under; 0 for one named by a version
  /// before copies were numbered, which came before every numbered one.
  static int _numberOf(File copy) {
    final match = _numbered.firstMatch(copy.uri.pathSegments.last);
    return match == null ? 0 : int.parse(match.group(1)!);
  }

  /// The databases set aside as damaged here ([setAsideDamaged]), oldest
  /// first: by their number, then (those named before numbers) by name.
  List<File> damagedCopies() {
    if (!directory.existsSync()) return const [];
    return [
      for (final entity in directory.listSync())
        if (entity is File &&
            entity.uri.pathSegments.last.startsWith(_damagedPrefix) &&
            entity.path.endsWith('.db'))
          entity,
    ]..sort((a, b) {
      final byNumber = _numberOf(a).compareTo(_numberOf(b));
      return byNumber != 0 ? byNumber : a.path.compareTo(b.path);
    });
  }

  static Future<void> _deleteDatabase(File file) async {
    for (final suffix in ['', '-wal', '-shm', '-journal']) {
      final part = File('${file.path}$suffix');
      if (await part.exists()) await part.delete();
    }
  }
}
