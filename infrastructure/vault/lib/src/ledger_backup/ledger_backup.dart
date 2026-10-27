import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:storage/storage.dart';
import 'package:vault/backup_security.dart';

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

  /// The content decrypted but is not a ledger the app can read.
  invalidContent,
}

final class BackupException implements Exception {
  const BackupException(this.problem, [this.detail = '']);

  final BackupProblem problem;

  /// A non-secret hint for diagnostics, such as a record's shelf.
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
    required this.revision,
    required this.rows,
  });

  static const format = 'ExpenseTracker-backup';
  static const version = 3;

  final String backupId;
  final DateTime createdAt;

  /// Wrapped keys only; opening them needs the password, the recovery code
  /// or a device key.
  final Keyring keyring;
  final int backupEpoch;

  /// The ledger's [RowStore.revision] when this backup was taken: a later
  /// backup of a changed ledger has a larger one.
  final int revision;

  /// How many records the backup holds.
  final int rows;

  Map<String, Object?> toJson() => {
    'format': format,
    'version': version,
    'backupId': backupId,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'keyring': keyring.encode(),
    'backupEpoch': backupEpoch,
    'revision': revision,
    'rows': rows,
  };

  static BackupHeader parse(List<int> bytes) {
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw const BackupException(BackupProblem.invalidFormat, 'header');
    }
    if (json is! Map<String, Object?> || json['format'] != format) {
      throw const BackupException(BackupProblem.invalidFormat, 'header');
    }
    if (json['version'] != version) {
      throw const BackupException(BackupProblem.unsupportedVersion);
    }
    const keys = {
      'format',
      'version',
      'backupId',
      'createdAt',
      'keyring',
      'backupEpoch',
      'revision',
      'rows',
    };
    if (json.length != keys.length || !keys.containsAll(json.keys)) {
      throw const BackupException(BackupProblem.invalidFormat, 'header');
    }
    try {
      return BackupHeader(
        backupId: json['backupId']! as String,
        createdAt: DateTime.parse(json['createdAt']! as String),
        keyring: Keyring.parse(json['keyring']! as String),
        backupEpoch: json['backupEpoch']! as int,
        revision: json['revision']! as int,
        rows: json['rows']! as int,
      );
    } on Object {
      throw const BackupException(BackupProblem.invalidFormat, 'header');
    }
  }
}

/// Backup format v3: every record of the ledger, then any files kept
/// beside it, such as receipt photos.
///
/// File: an 8-byte magic, then length-prefixed frames. Frame 0 is the
/// header in plain JSON. Every later frame is one gzip-compressed JSON chunk
/// sealed with AES-256-GCM under the keyring's backup key; its AAD binds
/// the header digest and the chunk's position, so chunks cannot be swapped,
/// dropped, reordered or moved to another backup. The last chunk states
/// the totals, so a truncated file is detected.
abstract final class LedgerBackup {
  static final _magic = ascii.encode('ETV2BK3\n');
  static const _maxFrame = 64 * 1024 * 1024;
  static final _cipher = AesGcm.with256bits();

  /// Writes a backup of [store] to [file]. The records are read at once,
  /// so the backup is one consistent state.
  static Future<BackupHeader> write({
    required RowStore store,
    required UnlockedKeyring keys,
    required File file,
    required String backupId,
    required DateTime createdAt,
    int chunkSize = 1000,
    Map<String, File> files = const {},
  }) async {
    final rows = store.rows();
    final epoch = keys.currentBackupEpoch;
    final header = BackupHeader(
      backupId: backupId,
      createdAt: createdAt,
      keyring: keys.keyring,
      backupEpoch: epoch,
      revision: store.revision,
      rows: rows.length,
    );
    final headerBytes = utf8.encode(jsonEncode(header.toJson()));
    final keyBytes = List<int>.of(keys.backupKey(epoch));
    final items = [
      for (final row in rows) [row.shelf, row.id, row.body],
    ];
    final path = file.path;
    final paths = {
      for (final MapEntry(key: name, value: source) in files.entries)
        name: source.path,
    };
    // Hashing, compressing and sealing every record and photo is seconds
    // of pure-Dart work for a book with many photos: done on a worker
    // isolate, so the screen keeps moving. The records were read above,
    // so the backup is still one consistent state.
    await Isolate.run(
      () => _writeFrames(path, headerBytes, keyBytes, items, chunkSize, paths),
    );
    return header;
  }

  static Future<void> _writeFrames(
    String path,
    List<int> headerBytes,
    List<int> keyBytes,
    List<List<String>> items,
    int chunkSize,
    Map<String, String> files,
  ) async {
    final key = SecretKey(keyBytes);
    final digest = (await Sha256().hash(headerBytes)).bytes;
    final sink = File(path).openWrite();
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

      for (var at = 0; at < items.length; at += chunkSize) {
        await seal({
          'type': 'rows',
          'items': items.skip(at).take(chunkSize).toList(),
        });
      }
      for (final MapEntry(key: name, value: source) in files.entries) {
        await seal({
          'type': 'file',
          'name': name,
          'data': base64Encode(await File(source).readAsBytes()),
        });
      }
      await seal({
        'type': 'end',
        'chunks': index,
        'rows': items.length,
        if (files.isNotEmpty) 'files': files.length,
      });
      await sink.flush();
    } finally {
      await sink.close();
    }
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

  /// Restores [file] into the empty store [into]. [keys] must be the
  /// backup's own keyring, unlocked; see [readHeader].
  ///
  /// [accept] sees every record first and throws for one the app cannot
  /// read, which fails the restore as [BackupProblem.invalidContent].
  /// When this throws, [into] may hold part of the backup; discard that
  /// store file instead of using it.
  ///
  /// Each file the backup carries is handed to [onFile] by name; without
  /// one they are skipped.
  static Future<BackupHeader> restore({
    required File file,
    required UnlockedKeyring keys,
    required RowStore into,
    void Function(String shelf, String id, String body)? accept,
    Future<void> Function(String name, List<int> bytes)? onFile,
  }) async {
    if (into.count != 0) {
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
      var rows = 0;
      var files = 0;
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
          case 'rows':
            final items = _items(chunk);
            for (final (shelf, id, body) in items) {
              try {
                accept?.call(shelf, id, body);
              } on Object {
                throw BackupException(BackupProblem.invalidContent, shelf);
              }
            }
            into.write((w) {
              for (final (shelf, id, body) in items) {
                w.put(shelf, id, body);
              }
            });
            rows += items.length;
          case 'file':
            final name = chunk['name'];
            final data = chunk['data'];
            if (name is! String || data is! String) {
              throw const BackupException(BackupProblem.invalidFormat, 'file');
            }
            files++;
            await onFile?.call(name, base64Decode(data));
          case 'end':
            if (chunk['chunks'] != index - 1 ||
                chunk['rows'] != rows ||
                (chunk['files'] ?? 0) != files) {
              throw const BackupException(BackupProblem.invalidFormat, 'end');
            }
            ended = true;
          default:
            throw const BackupException(BackupProblem.invalidFormat, 'chunk');
        }
      }
      if (!ended || rows != header.rows) {
        throw const BackupException(BackupProblem.invalidFormat, 'truncated');
      }
      return header;
    } finally {
      await reader.close();
    }
  }

  static List<int> _aad(List<int> digest, int index) => [
    ...ascii.encode('ETV2BK/3/'),
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

  static List<(String, String, String)> _items(Map<String, Object?> chunk) {
    final items = chunk['items'];
    if (items is! List) {
      throw const BackupException(BackupProblem.invalidFormat, 'items');
    }
    return [
      for (final item in items)
        if (item case [final String shelf, final String id, final String body])
          (shelf, id, body)
        else
          throw const BackupException(BackupProblem.invalidFormat, 'item'),
    ];
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
