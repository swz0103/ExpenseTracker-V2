import 'dart:convert';
import 'dart:io';

import 'package:backup_envelope_probe/envelope.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:modular_persistence_probe/database.dart';

import 'authenticated_chunked_snapshot.dart';
import 'snapshot.dart';

/// Owned fixture directory only. Caller must close every DB handle before switching.
final class RestoreStore {
  RestoreStore(this.directory, {this.openDatabase, SnapshotCodec? snapshot})
    : _snapshot = snapshot ?? SnapshotCodec();
  final Directory directory;
  final ProbeDatabase Function(File)? openDatabase;
  static final _busy = <String>{};
  File _file(String name) => File('${directory.absolute.path}/$name');
  File get current => _file('current.db');
  final SnapshotCodec _snapshot;

  Future<CreatedBackup> backup(ProbeDatabase source, String password) async =>
      EnvelopeCodec().create(
        await _snapshot.capture(source),
        password: password,
      );

  Future<CreatedAuthenticatedChunkedSnapshot> backupChunked(
    ProbeDatabase source,
    Directory target, {
    required String password,
    String? recoveryKey,
    AuthenticatedChunkedSnapshotStore store =
        const AuthenticatedChunkedSnapshotStore(),
  }) => _snapshot.captureAuthenticatedChunked(
    source,
    target,
    password: password,
    recoveryKey: recoveryKey,
    store: store,
  );

  Future<void> restore(
    String envelope, {
    String? password,
    String? recoveryKey,
    void Function(String)? checkpoint,
  }) => _locked(() async {
    await _recover();
    if ((password == null) == (recoveryKey == null))
      throw ArgumentError('Exactly one unlock credential is required.');
    final codec = EnvelopeCodec();
    final bytes = password != null
        ? await codec.openWithPassword(envelope, password)
        : await codec.openWithRecovery(envelope, recoveryKey!);
    try {
      await _snapshot.stage(
        bytes,
        _file('stage.db'),
        openDatabase: openDatabase,
      );
      await _promoteStage(checkpoint);
    } catch (_) {
      await _recover();
      rethrow;
    }
  });

  Future<void> restoreChunked(
    Directory authenticated, {
    String? password,
    String? recoveryKey,
    AuthenticatedChunkedSnapshotStore store =
        const AuthenticatedChunkedSnapshotStore(),
    void Function(String)? checkpoint,
  }) => _locked(() async {
    await _recover();
    if ((password == null) == (recoveryKey == null)) {
      throw ArgumentError('Exactly one unlock credential is required.');
    }
    final expectedTables = _snapshot.tableNames;
    final opened = password != null
        ? await store.readWithPassword(
            source: authenticated,
            expectedTables: expectedTables,
            password: password,
          )
        : await store.readWithRecovery(
            source: authenticated,
            expectedTables: expectedTables,
            recoveryKey: recoveryKey!,
          );
    try {
      await _snapshot.stageAuthenticatedChunked(
        opened,
        _file('stage.db'),
        openDatabase: openDatabase,
      );
      await _promoteStage(checkpoint);
    } catch (_) {
      await _recover();
      rethrow;
    }
  });

  Future<void> _promoteStage(void Function(String)? checkpoint) async {
    checkpoint?.call('validated');
    final hadPrevious = await current.exists();
    await _file('journal.json').writeAsString(
      jsonEncode({'version': 1, 'hadPrevious': hadPrevious}),
      flush: true,
    );
    checkpoint?.call('prepared');
    if (hadPrevious) await _move(current, _file('previous.db'));
    checkpoint?.call('oldMoved');
    await _move(_file('stage.db'), current);
    checkpoint?.call('newMoved');
    // Commit point. Previous databases remain preserved for explicit retention policy.
    await _file('journal.json').delete();
  }

  Future<void> recover() => _locked(_recover);

  Future<void> _recover() async {
    final journal = _file('journal.json');
    final previous = _file('previous.db');
    if (await journal.exists()) {
      if (await journal.length() > 1024)
        throw StateError('Invalid recovery journal.');
      final state = jsonDecode(await journal.readAsString());
      if (state is! Map ||
          state.length != 2 ||
          state['version'] != 1 ||
          state['hadPrevious'] is! bool)
        throw StateError('Invalid recovery journal.');
      if (state['hadPrevious'] == true) {
        if (await previous.exists()) {
          await _retain(current, 'uncommitted');
          await _move(previous, current);
        } else if (!await current.exists()) {
          throw StateError('Original database missing; recovery stopped.');
        }
      } else {
        if (await previous.exists())
          throw StateError('Unexpected previous database.');
        await _retain(current, 'uncommitted');
      }
      await journal.delete();
    }
    await _retain(_file('stage.db'), 'uncommitted');
    await _retain(previous, 'previous');
  }

  Future<void> _retain(File file, String prefix) async {
    if (await file.exists())
      await _move(file, _file('$prefix-${PublicId.generate().value}.db'));
  }

  Future<void> _move(File source, File destination) async {
    if (await FileSystemEntity.type(destination.path, followLinks: false) !=
        FileSystemEntityType.notFound)
      throw StateError('Refusing to overwrite a recovery file.');
    await source.rename(destination.absolute.path);
  }

  Future<void> _locked(Future<void> Function() work) async {
    await directory.create(recursive: true);
    final root = await directory.resolveSymbolicLinks();
    final identity = Platform.isWindows ? root.toLowerCase() : root;
    if (!_busy.add(identity)) throw StateError('Restore already running.');
    RandomAccessFile? lock;
    var acquired = false;
    try {
      for (final name in [
        'current.db',
        'previous.db',
        'stage.db',
        'journal.json',
        'restore.lock',
      ]) {
        final type = await FileSystemEntity.type(
          _file(name).path,
          followLinks: false,
        );
        if (type != FileSystemEntityType.notFound &&
            type != FileSystemEntityType.file)
          throw StateError('Unexpected restore path type.');
      }
      // This prototype only switches closed standalone files, not live WAL stores.
      for (final name in [
        'current.db-wal',
        'current.db-shm',
        'current.db-journal',
        'stage.db-wal',
        'stage.db-shm',
        'stage.db-journal',
        'previous.db-wal',
        'previous.db-shm',
        'previous.db-journal',
      ]) {
        if (await FileSystemEntity.type(_file(name).path, followLinks: false) !=
            FileSystemEntityType.notFound)
          throw StateError('Database sidecars present; close handles first.');
      }
      lock = await _file('restore.lock').open(mode: FileMode.append);
      await lock.lock(FileLock.exclusive);
      acquired = true;
      await work();
    } finally {
      try {
        if (acquired) await lock!.unlock();
      } finally {
        await lock?.close();
        _busy.remove(identity);
      }
    }
  }
}
