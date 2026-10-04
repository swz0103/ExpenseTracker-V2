import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:app_core/app_core.dart';
import 'package:backup_security/backup_security.dart';
import 'package:cryptography/cryptography.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger_sqlcipher/ledger_sqlcipher.dart';
import 'package:storage_sqlcipher/storage_sqlcipher.dart';

/// Why a backup could not be read or restored. Never carries key material
/// or ledger content.
enum BackupProblem {
  /// Not a backup file, or a truncated or reordered one.
  invalidFormat,

  /// Written by a newer app.
  unsupportedVersion,

  /// The keys do not open this backup, or its content was altered.
  authenticationFailed,

  /// The target ledger already has data.
  targetNotEmpty,

  /// The content decrypted but does not replay into a valid ledger.
  invalidContent,
}

final class BackupException implements Exception {
  const BackupException(this.problem, [this.detail = '']);

  final BackupProblem problem;

  /// A non-secret hint for diagnostics, such as an event sequence number.
  final String detail;

  @override
  String toString() => 'BackupException(${problem.name} $detail)';
}

/// The authenticated facts about a backup. They are readable before any
/// key is entered, and every chunk is bound to them, so a restore can warn
/// when a backup is older than the ledger it would replace.
final class BackupHeader {
  const BackupHeader({
    required this.backupId,
    required this.createdAt,
    required this.keyring,
    required this.backupEpoch,
    required this.lastSeq,
    required this.events,
    required this.operations,
  });

  static const format = 'ExpenseTracker-backup';
  static const version = 2;

  final PublicId backupId;
  final UtcInstant createdAt;

  /// Wrapped keys only; opening them needs the password, the recovery code
  /// or a device key.
  final Keyring keyring;
  final int backupEpoch;

  /// The journal position this backup ends at. A later backup of the same
  /// ledger always has a larger value.
  final int lastSeq;
  final int events;
  final int operations;

  Map<String, Object?> toJson() => {
    'format': format,
    'version': version,
    'backupId': backupId.value,
    'createdAt': createdAt.toString(),
    'keyring': keyring.encode(),
    'backupEpoch': backupEpoch,
    'lastSeq': lastSeq,
    'events': events,
    'operations': operations,
  };

  static BackupHeader parse(List<int> bytes) {
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw const BackupException(BackupProblem.invalidFormat, 'header');
    }
    const keys = {
      'format',
      'version',
      'backupId',
      'createdAt',
      'keyring',
      'backupEpoch',
      'lastSeq',
      'events',
      'operations',
    };
    if (json is! Map<String, Object?> ||
        json.length != keys.length ||
        !keys.containsAll(json.keys) ||
        json['format'] != format) {
      throw const BackupException(BackupProblem.invalidFormat, 'header');
    }
    if (json['version'] != version) {
      throw const BackupException(BackupProblem.unsupportedVersion);
    }
    try {
      return BackupHeader(
        backupId: PublicId.parse(json['backupId']! as String),
        createdAt: UtcInstant.parse(json['createdAt']! as String),
        keyring: Keyring.parse(json['keyring']! as String),
        backupEpoch: json['backupEpoch']! as int,
        lastSeq: json['lastSeq']! as int,
        events: json['events']! as int,
        operations: json['operations']! as int,
      );
    } on Object {
      throw const BackupException(BackupProblem.invalidFormat, 'header');
    }
  }
}

/// Backup format v2.
///
/// File: an 8-byte magic, then length-prefixed frames. Frame 0 is the
/// header in plain JSON. Every later frame is one gzip-compressed JSON chunk
/// sealed with AES-256-GCM under the keyring's backup key; its AAD binds
/// the header digest and the chunk's position, so chunks cannot be swapped,
/// dropped, reordered or moved to another backup. The last chunk states
/// the totals, so a truncated file is detected.
///
/// Capture never validates business rules: a backup must be possible even
/// when something in the ledger is wrong. Restore replays every event
/// through the domain codecs into an empty store, which is where problems
/// are found.
abstract final class LedgerBackup {
  static final _magic = ascii.encode('ETV2BK2\n');
  static const _maxFrame = 64 * 1024 * 1024;
  static final _cipher = AesGcm.with256bits();

  /// Writes a backup of [store] to [file]. The capture holds the store's
  /// write lock, so it reads one consistent state; run it through the
  /// app's command queue like any other write.
  static Future<BackupHeader> write({
    required SqlCipherStore store,
    required UnlockedKeyring keys,
    required File file,
    required PublicId backupId,
    required UtcInstant createdAt,
    int chunkSize = 1000,
  }) => store.write(
    (_) => _capture(store, keys, file, backupId, createdAt, chunkSize),
  );

  static Future<BackupHeader> _capture(
    SqlCipherStore store,
    UnlockedKeyring keys,
    File file,
    PublicId backupId,
    UtcInstant createdAt,
    int chunkSize,
  ) async {
    final epoch = keys.currentBackupEpoch;
    final key = SecretKey(keys.backupKey(epoch));
    final header = BackupHeader(
      backupId: backupId,
      createdAt: createdAt,
      keyring: keys.keyring,
      backupEpoch: epoch,
      lastSeq: _lastSeq(store),
      events: store.eventCount,
      operations: store.operationCount,
    );
    final headerBytes = utf8.encode(jsonEncode(header.toJson()));
    final digest = (await Sha256().hash(headerBytes)).bytes;
    final sink = file.openWrite();
    var index = 0;
    try {
      sink.add(_magic);
      _frame(sink, headerBytes);
      Future<void> seal(Map<String, Object?> chunk) async {
        index++;
        final plain = gzip.encode(utf8.encode(jsonEncode(chunk)));
        final box = await _cipher.encrypt(
          plain,
          secretKey: key,
          aad: _aad(digest, index),
        );
        _frame(sink, [...box.nonce, ...box.cipherText, ...box.mac.bytes]);
      }

      var after = 0;
      var events = 0;
      while (true) {
        final page = store.journal(afterSeq: after, limit: chunkSize);
        if (page.isEmpty) break;
        await seal({
          'type': 'events',
          'items': [for (final event in page) _event(event)],
        });
        events += page.length;
        after = page.last.seq;
      }
      var operations = 0;
      for (var offset = 0; ; offset += chunkSize) {
        final page = store.operations(offset: offset, limit: chunkSize);
        if (page.isEmpty) break;
        await seal({
          'type': 'operations',
          'items': [for (final operation in page) _operation(operation)],
        });
        operations += page.length;
      }
      if (events != header.events || operations != header.operations) {
        throw StateError('The ledger changed during the backup.');
      }
      await seal({
        'type': 'end',
        'chunks': index,
        'events': events,
        'operations': operations,
      });
      await sink.flush();
    } finally {
      await sink.close();
    }
    return header;
  }

  /// Reads the header without any key, for choosing a backup and showing
  /// how old it is.
  static Future<BackupHeader> readHeader(File file) async {
    final reader = await _FrameReader.open(file);
    try {
      final first = await reader.next();
      if (first == null) {
        throw const BackupException(BackupProblem.invalidFormat, 'empty');
      }
      return BackupHeader.parse(first);
    } finally {
      await reader.close();
    }
  }

  /// Restores [file] into the empty ledger [into]. [keys] must be the
  /// backup's own keyring, unlocked; see [readHeader].
  ///
  /// When this throws, [into] may hold part of the backup; discard that
  /// store file instead of using it.
  static Future<BackupHeader> restore({
    required File file,
    required UnlockedKeyring keys,
    required LedgerStore into,
  }) async {
    final intoStore = into.store;
    if (intoStore.eventCount != 0 || intoStore.operationCount != 0) {
      throw const BackupException(BackupProblem.targetNotEmpty);
    }
    final reader = await _FrameReader.open(file);
    try {
      final headerBytes = await reader.next();
      if (headerBytes == null) {
        throw const BackupException(BackupProblem.invalidFormat, 'empty');
      }
      final header = BackupHeader.parse(headerBytes);
      if (header.keyring.id != keys.keyring.id) {
        throw const BackupException(BackupProblem.authenticationFailed);
      }
      final Uint8List backupKey;
      try {
        backupKey = keys.backupKey(header.backupEpoch);
      } on RangeError {
        throw const BackupException(BackupProblem.authenticationFailed);
      }
      final key = SecretKey(backupKey);
      final digest = (await Sha256().hash(headerBytes)).bytes;
      var index = 0;
      var events = 0;
      var operations = 0;
      var ended = false;
      while (true) {
        final frame = await reader.next();
        if (frame == null) break;
        if (ended) {
          throw const BackupException(BackupProblem.invalidFormat, 'tail');
        }
        index++;
        final chunk = await _open(frame, key, _aad(digest, index));
        switch (chunk['type']) {
          case 'events':
            final items = _items(chunk);
            await into.write((transaction) async {
              for (final item in items) {
                await LedgerReplay.apply(transaction, _readEvent(item));
              }
            });
            events += items.length;
          case 'operations':
            final items = _items(chunk);
            await into.write((transaction) async {
              for (final item in items) {
                await transaction.recordOperation(_readOperation(item));
              }
            });
            operations += items.length;
          case 'end':
            if (chunk['chunks'] != index - 1 ||
                chunk['events'] != events ||
                chunk['operations'] != operations) {
              throw const BackupException(BackupProblem.invalidFormat, 'end');
            }
            ended = true;
          default:
            throw const BackupException(BackupProblem.invalidFormat, 'chunk');
        }
      }
      if (!ended ||
          events != header.events ||
          operations != header.operations) {
        throw const BackupException(BackupProblem.invalidFormat, 'truncated');
      }
      return header;
    } on ReplayException catch (error) {
      throw BackupException(BackupProblem.invalidContent, '#${error.seq}');
    } on BackupException {
      rethrow;
    } on Object catch (error) {
      throw BackupException(
        BackupProblem.invalidContent,
        '${error.runtimeType}',
      );
    } finally {
      await reader.close();
    }
  }

  static int _lastSeq(SqlCipherStore store) {
    final rows = store.select('SELECT max(seq) AS seq FROM events');
    return (rows.single['seq'] as int?) ?? 0;
  }

  static List<int> _aad(List<int> digest, int index) => [
    ...ascii.encode('ETV2BK/2/'),
    ...digest,
    ...(ByteData(4)..setUint32(0, index)).buffer.asUint8List(),
  ];

  static void _frame(IOSink sink, List<int> bytes) {
    sink.add((ByteData(4)..setUint32(0, bytes.length)).buffer.asUint8List());
    sink.add(bytes);
  }

  static Future<Map<String, Object?>> _open(
    List<int> frame,
    SecretKey key,
    List<int> aad,
  ) async {
    if (frame.length < 28) {
      throw const BackupException(BackupProblem.invalidFormat, 'frame');
    }
    final List<int> plain;
    try {
      plain = await _cipher.decrypt(
        SecretBox(
          frame.sublist(12, frame.length - 16),
          nonce: frame.sublist(0, 12),
          mac: Mac(frame.sublist(frame.length - 16)),
        ),
        secretKey: key,
        aad: aad,
      );
    } on SecretBoxAuthenticationError {
      throw const BackupException(BackupProblem.authenticationFailed);
    }
    try {
      return jsonDecode(utf8.decode(gzip.decode(plain)))
          as Map<String, Object?>;
    } on Object {
      throw const BackupException(BackupProblem.invalidFormat, 'chunk');
    }
  }

  static List<Map<String, Object?>> _items(Map<String, Object?> chunk) {
    final items = chunk['items'];
    if (items is! List) {
      throw const BackupException(BackupProblem.invalidFormat, 'items');
    }
    return [
      for (final item in items)
        if (item is Map<String, Object?>)
          item
        else
          throw const BackupException(BackupProblem.invalidFormat, 'item'),
    ];
  }

  static Map<String, Object?> _event(StoredEvent event) => {
    'seq': event.seq,
    'id': event.id.value,
    'workspace': event.workspace.toString(),
    'kind': event.kind,
    'payload': event.payload,
  };

  static StoredEvent _readEvent(Map<String, Object?> json) {
    try {
      return StoredEvent(
        seq: json['seq']! as int,
        id: PublicId.parse(json['id']! as String),
        workspace: WorkspaceId.parse(json['workspace']! as String),
        kind: json['kind']! as String,
        payload: json['payload']! as String,
      );
    } on Object {
      throw const BackupException(BackupProblem.invalidFormat, 'event');
    }
  }

  static Map<String, Object?> _operation(RecordedOperation operation) => {
    'workspace': operation.key.workspace.toString(),
    'operation': operation.key.operation.toString(),
    'input': operation.input,
    'result': operation.result,
  };

  static RecordedOperation _readOperation(Map<String, Object?> json) {
    try {
      return RecordedOperation(
        key: OperationKey(
          WorkspaceId.parse(json['workspace']! as String),
          OperationId.parse(json['operation']! as String),
        ),
        input: json['input']! as String,
        result: json['result']! as String,
      );
    } on Object {
      throw const BackupException(BackupProblem.invalidFormat, 'operation');
    }
  }
}

/// Reads length-prefixed frames one at a time, so memory stays bounded by
/// the largest chunk.
final class _FrameReader {
  _FrameReader._(this._file);

  final RandomAccessFile _file;

  static Future<_FrameReader> open(File file) async {
    final handle = await file.open();
    final reader = _FrameReader._(handle);
    final magic = await handle.read(LedgerBackup._magic.length);
    if (!_same(magic, LedgerBackup._magic)) {
      await handle.close();
      throw const BackupException(BackupProblem.invalidFormat, 'magic');
    }
    return reader;
  }

  Future<List<int>?> next() async {
    final prefix = await _file.read(4);
    if (prefix.isEmpty) return null;
    if (prefix.length != 4) {
      throw const BackupException(BackupProblem.invalidFormat, 'length');
    }
    final length = ByteData.sublistView(prefix).getUint32(0);
    if (length > LedgerBackup._maxFrame) {
      throw const BackupException(BackupProblem.invalidFormat, 'size');
    }
    final bytes = await _file.read(length);
    if (bytes.length != length) {
      throw const BackupException(BackupProblem.invalidFormat, 'truncated');
    }
    return bytes;
  }

  Future<void> close() => _file.close();

  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
