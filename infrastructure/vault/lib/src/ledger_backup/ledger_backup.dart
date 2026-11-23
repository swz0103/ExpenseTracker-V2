import 'dart:convert';
import 'dart:io';
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
    this.book,
    this.layout,
    this.version = BackupHeader.current,
  });

  static const format = 'ExpenseTracker-backup';

  /// The version this app writes. 4: the keyring is [Keyring.exported],
  /// without the app password's slot, and a file larger than a chunk is
  /// split over several. 5: the header also carries the book's version
  /// and the store's layout ([book], [layout]).
  static const current = 5;

  /// The versions this app reads: every one it has written since backups
  /// were kept for good (docs/adr/0010-data-that-lasts.md). A version is
  /// added when the format changes and never taken out; reading an older
  /// one brings it up to [current].
  static const readable = {3, 4, 5};

  /// The keys of a header of each version: exactly these, no more.
  static const _keys = {
    'format',
    'version',
    'backupId',
    'createdAt',
    'keyring',
    'backupEpoch',
    'revision',
    'rows',
  };
  static const _keysFrom5 = {..._keys, 'book', 'layout'};

  /// The version this backup was written in. A version 3 backup carries
  /// the app password's slot, so it opens with that password too.
  final int version;

  final String backupId;
  final DateTime createdAt;

  /// Wrapped keys only; opening them needs the recovery code or the
  /// backup passphrase (and, in version 3, the app password).
  final Keyring keyring;
  final int backupEpoch;

  /// The ledger's [EncryptedDatabase.revision] when this backup was taken: a later
  /// backup of a changed ledger has a larger one.
  final int revision;

  /// How many records the backup holds.
  final int rows;

  /// The book's version when this backup was taken (what the store kept
  /// under [EncryptedDatabase.bookVersionKey]); null in a backup before
  /// version 5, and for a book that had none. A restore keeps it, so a
  /// book already brought up is not brought up again.
  final int? book;

  /// The store's layout ([EncryptedDatabase.schema]) when this backup was
  /// taken; null in a backup before version 5.
  final int? layout;

  Map<String, Object?> toJson() => {
    'format': format,
    'version': version,
    'backupId': backupId,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'keyring': keyring.encode(),
    'backupEpoch': backupEpoch,
    'revision': revision,
    'rows': rows,
    if (version >= 5) ...{'book': book, 'layout': layout},
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
    final version = json['version'];
    if (version is! int || !readable.contains(version)) {
      throw const BackupException(BackupProblem.unsupportedVersion);
    }
    final keys = version >= 5 ? _keysFrom5 : _keys;
    if (json.length != keys.length || !keys.containsAll(json.keys)) {
      throw const BackupException(BackupProblem.invalidFormat, 'header');
    }
    final BackupHeader header;
    try {
      header = BackupHeader(
        backupId: json['backupId']! as String,
        createdAt: DateTime.parse(json['createdAt']! as String),
        keyring: Keyring.parse(json['keyring']! as String),
        backupEpoch: json['backupEpoch']! as int,
        revision: json['revision']! as int,
        rows: json['rows']! as int,
        // Version 5: the book's version, null for a book that had none;
        // the layout, always.
        book: json['book'] as int?,
        layout: version >= 5 ? json['layout']! as int : null,
        version: version,
      );
    } on Object {
      throw const BackupException(BackupProblem.invalidFormat, 'header');
    }
    // From version 4 on the app password never leaves the phone.
    if (version >= 4 && header.keyring.hasPassword) {
      throw const BackupException(BackupProblem.invalidFormat, 'header');
    }
    return header;
  }
}

/// Backup format v5: every record of the ledger, then any files kept
/// beside it, such as receipt photos.
///
/// File: an 8-byte magic, then length-prefixed frames. Frame 0 is the
/// header in plain JSON. Every later frame is one gzip-compressed JSON chunk
/// sealed with AES-256-GCM under the keyring's backup key; its AAD binds
/// the header digest and the chunk's position, so chunks cannot be swapped,
/// dropped, reordered or moved to another backup. The last chunk states
/// the totals, so a truncated file is detected.
///
/// No frame is larger than [maxFrame], on writing as on reading, so every
/// backup written can be read: records go into chunks of at most
/// [chunkBytes] of text, and a file into pieces of at most [pieceBytes],
/// each piece but the last marked `more`.
abstract final class LedgerBackup {
  static final _magic = ascii.encode('ETV2BK3\n');

  /// The largest frame a backup may hold.
  static const maxFrame = 64 * 1024 * 1024;

  /// The most bytes of a file one chunk carries: base64 makes it 4/3 as
  /// large, and gzip of the worst (random) bytes adds little, so a piece's
  /// frame stays far under [maxFrame].
  static const pieceBytes = 16 * 1024 * 1024;

  /// The most text (UTF-16 code units) of records one chunk carries: even
  /// were every unit escaped by JSON as six bytes, a chunk stays under
  /// [maxFrame]. A single record larger than that is refused on writing.
  static const chunkBytes = 8 * 1024 * 1024;
  static final _cipher = AesGcm.with256bits();

  /// Writes a backup of [store] to [file]. The records are read in one
  /// read of the store, so the backup is one consistent state.
  ///
  /// Reading every record, then hashing, compressing and sealing them and
  /// the photos, is seconds of work for a large book: all of it runs on a
  /// worker isolate ([EncryptedDatabase.readApart]), so the screen keeps
  /// moving and the records never come back to the caller's isolate
  /// (D41). The store is busy only while the records are read; a write
  /// asked for meanwhile waits for [EncryptedDatabase.idle].
  static Future<BackupHeader> write({
    required EncryptedDatabase store,
    required UnlockedKeyring keys,
    required File file,
    required String backupId,
    required DateTime createdAt,
    int chunkSize = 1000,
    Map<String, File> files = const {},
    int pieceBytes = pieceBytes,
    int chunkBytes = chunkBytes,
  }) async {
    final epoch = keys.currentBackupEpoch;
    return store.readApart(
      _framesOf(
        path: file.path,
        backupId: backupId,
        createdAt: createdAt,
        keyring: keys.keyring.exported,
        epoch: epoch,
        keyBytes: List<int>.of(keys.backupKey(epoch)),
        sizes: (count: chunkSize, piece: pieceBytes, text: chunkBytes),
        files: {
          for (final MapEntry(key: name, value: source) in files.entries)
            name: source.path,
        },
      ),
    );
  }

  /// What the worker does with the records read ([write]): the header,
  /// then every frame. Built from plain values only (no store, no
  /// unlocked keys), so the closure sent to the worker carries nothing
  /// else.
  static Future<BackupHeader> Function(StoreSnapshot snapshot) _framesOf({
    required String path,
    required String backupId,
    required DateTime createdAt,
    required Keyring keyring,
    required int epoch,
    required List<int> keyBytes,
    required ({int count, int piece, int text}) sizes,
    required Map<String, String> files,
  }) => (snapshot) async {
    final header = BackupHeader(
      backupId: backupId,
      createdAt: createdAt,
      keyring: keyring,
      backupEpoch: epoch,
      revision: snapshot.revision,
      rows: snapshot.rows.length,
      book: snapshot.book,
      layout: snapshot.layout,
    );
    final headerBytes = utf8.encode(jsonEncode(header.toJson()));
    await _writeFrames(
      path,
      headerBytes,
      keyBytes,
      snapshot.rows,
      sizes,
      files,
    );
    return header;
  };

  static Future<void> _writeFrames(
    String path,
    List<int> headerBytes,
    List<int> keyBytes,
    List<StoredRow> rows,
    ({int count, int piece, int text}) sizes,
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
        // One typed buffer: a frame of boxed ints would be eight times
        // its size, and garbage the screen's isolate pays for too.
        final nonce = box.nonce.length;
        final sealed = box.cipherText.length;
        _frame(
          sink,
          Uint8List(nonce + sealed + box.mac.bytes.length)
            ..setAll(0, box.nonce)
            ..setAll(nonce, box.cipherText)
            ..setAll(nonce + sealed, box.mac.bytes),
        );
      }

      // Records: at most sizes.count of them, and sizes.text of their
      // text, a chunk.
      var chunk = <List<String>>[];
      var text = 0;
      for (final row in rows) {
        final item = [row.shelf, row.id, row.body];
        final size = row.shelf.length + row.id.length + row.body.length;
        if (chunk.isNotEmpty &&
            (chunk.length >= sizes.count || text + size > sizes.text)) {
          await seal({'type': 'rows', 'items': chunk});
          chunk = [];
          text = 0;
        }
        chunk.add(item);
        text += size;
      }
      if (chunk.isNotEmpty) await seal({'type': 'rows', 'items': chunk});
      // Each file in pieces, read one piece at a time.
      for (final MapEntry(key: name, value: source) in files.entries) {
        final handle = await File(source).open();
        try {
          final length = await handle.length();
          var at = 0;
          do {
            final piece = await handle.read(sizes.piece);
            at += piece.length;
            await seal({
              'type': 'file',
              'name': name,
              'data': base64Encode(piece),
              if (at < length) 'more': true,
            });
          } while (at < length);
        } finally {
          await handle.close();
        }
      }
      await seal({
        'type': 'end',
        'chunks': index,
        'rows': rows.length,
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
    required EncryptedDatabase into,
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
      // Taken from a store of a later layout than this build keeps: what
      // it held beyond the records could be lost here.
      if ((header.layout ?? 0) > EncryptedDatabase.schema) {
        throw const BackupException(BackupProblem.unsupportedVersion);
      }
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
      // The file whose pieces are being read, until its last piece.
      String? piecesOf;
      final pieces = BytesBuilder(copy: false);
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
            // On a worker isolate: a large backup restores without
            // holding the screen still (DAT-03).
            await into.writeApart([
              for (final (shelf, id, body) in items)
                RowChange.put(shelf, id, body),
            ]);
            rows += items.length;
          case 'file':
            final name = chunk['name'];
            final data = chunk['data'];
            final more = chunk['more'] ?? false;
            if (name is! String ||
                data is! String ||
                more is! bool ||
                (piecesOf != null && piecesOf != name)) {
              throw const BackupException(BackupProblem.invalidFormat, 'file');
            }
            final List<int> bytes;
            try {
              bytes = base64Decode(data);
            } on FormatException {
              throw const BackupException(BackupProblem.invalidFormat, 'file');
            }
            pieces.add(bytes);
            if (more) {
              piecesOf = name;
              break;
            }
            piecesOf = null;
            files++;
            await onFile?.call(name, pieces.takeBytes());
          case 'end':
            if (piecesOf != null ||
                chunk['chunks'] != index - 1 ||
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
      // The book's version goes with its records (version 5 on), so the
      // book restored opens as it was kept: not brought up again, and no
      // copy is kept before an upgrade that does nothing (D26). A backup
      // without it leaves none, and the app brings the book up.
      if (header.book case final book?) {
        into.write(
          (w) => w.setMeta(EncryptedDatabase.bookVersionKey, book),
          counts: false,
        );
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
    // Refused here rather than written: the reader would refuse it.
    if (bytes.length > maxFrame) {
      throw const BackupException(BackupProblem.invalidContent, 'too large');
    }
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
    if (length > LedgerBackup.maxFrame) {
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
