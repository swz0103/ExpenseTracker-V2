import 'dart:convert';
import 'dart:io';

import 'package:backup_envelope_probe/chunk_envelope.dart';
import 'package:backup_envelope_probe/envelope.dart';
import 'package:cryptography/cryptography.dart';

import 'chunked_snapshot.dart';

final class CreatedAuthenticatedChunkedSnapshot {
  const CreatedAuthenticatedChunkedSnapshot({
    required this.recoveryKey,
    required this.summary,
  });

  final String recoveryKey;
  final ChunkedSnapshotSummary summary;
}

final class OpenedAuthenticatedChunkedSnapshot {
  const OpenedAuthenticatedChunkedSnapshot({
    required this.summary,
    required this.rows,
  });

  final ChunkedSnapshotSummary summary;
  final Stream<ChunkedSnapshotRow> rows;
}

/// Authenticated directory wrapper for the bounded chunk prototype.
///
/// The key metadata wraps one random data key with independent password and
/// recovery slots. The encrypted manifest is authenticated as `manifest`; each
/// encrypted chunk is authenticated with its ordinal filename as AAD. Opening
/// recreates a plaintext bounded container in a caller-owned temporary target;
/// production wiring must consume rows directly and never retain that target.
final class AuthenticatedChunkedSnapshotStore {
  const AuthenticatedChunkedSnapshotStore({
    this.plainStore = const ChunkedSnapshotStore(),
  });

  final ChunkedSnapshotStore plainStore;

  Future<CreatedAuthenticatedChunkedSnapshot> write({
    required Directory target,
    required int schema,
    required Map<String, Stream<Map<String, Object?>>> tables,
    required String password,
    String? recoveryKey,
  }) async {
    if (schema < 1 ||
        schema > 10000 ||
        tables.isEmpty ||
        plainStore.maxChunkBytes < 128 ||
        plainStore.maxChunkBytes > ChunkEnvelopeCodec.maxChunkBytes ||
        plainStore.maxRowsPerChunk < 1 ||
        plainStore.maxTotalRows < plainStore.maxRowsPerChunk ||
        plainStore.maxTotalBytes < plainStore.maxChunkBytes) {
      throw const BackupException(BackupError.invalidFormat);
    }
    final names = tables.keys.toList(growable: false);
    if (names.toSet().length != names.length ||
        names.any(
          (name) => !RegExp(r'^[a-z][a-z0-9_]{0,63}$').hasMatch(name),
        )) {
      throw const BackupException(BackupError.invalidFormat);
    }
    _requireMissing(target);
    final temporary = _temporaryFor(target);
    temporary.createSync(recursive: true);
    try {
      final created = await ChunkEnvelopeCodec().create(
        password: password,
        recoveryKey: recoveryKey,
      );
      await File('${temporary.path}${Platform.pathSeparator}metadata.json')
          .writeAsString(created.metadata, flush: true);
      final tableManifests = <Object>[];
      var totalRows = 0;
      var totalBytes = 0;
      var ordinal = 0;
      for (final entry in tables.entries) {
        final chunks = <Object>[];
        var buffer = <int>[];
        var rows = 0;

        Future<void> flush() async {
          if (rows == 0) return;
          final purpose = 'chunk-${ordinal.toString().padLeft(8, '0')}';
          await File('${temporary.path}${Platform.pathSeparator}$purpose.etv2')
              .writeAsString(
                await created.session.seal(buffer, purpose: purpose),
                flush: true,
              );
          chunks.add({
            'ordinal': ordinal,
            'file': '$purpose.ndjson',
            'rows': rows,
            'bytes': buffer.length,
            'sha256': await _digest(buffer),
          });
          totalBytes += buffer.length;
          ordinal++;
          buffer = <int>[];
          rows = 0;
        }

        await for (final row in entry.value) {
          final encoded = utf8.encode(
            '${jsonEncode(_authenticatedCanonical(row))}\n',
          );
          if (encoded.length > plainStore.maxChunkBytes) {
            throw const BackupException(BackupError.limitExceeded);
          }
          if (rows > 0 &&
              (rows == plainStore.maxRowsPerChunk ||
                  buffer.length + encoded.length > plainStore.maxChunkBytes)) {
            await flush();
          }
          buffer.addAll(encoded);
          rows++;
          totalRows++;
          if (totalRows > plainStore.maxTotalRows ||
              totalBytes + buffer.length > plainStore.maxTotalBytes) {
            throw const BackupException(BackupError.limitExceeded);
          }
        }
        await flush();
        tableManifests.add({'name': entry.key, 'chunks': chunks});
      }
      final manifest = utf8.encode(
        jsonEncode({
          'format': 'ledger-chunked-probe',
          'version': 1,
          'schema': schema,
          'tables': tableManifests,
          'totalRows': totalRows,
          'totalBytes': totalBytes,
        }),
      );
      await File('${temporary.path}${Platform.pathSeparator}manifest.etv2')
          .writeAsString(
            await created.session.seal(manifest, purpose: 'manifest'),
            flush: true,
          );
      final opened = await _openReader(temporary, names, created.session);
      await opened.rows.drain<void>();
      await temporary.rename(target.path);
      return CreatedAuthenticatedChunkedSnapshot(
        recoveryKey: created.recoveryKey,
        summary: opened.summary,
      );
    } catch (_) {
      if (temporary.existsSync()) temporary.deleteSync(recursive: true);
      rethrow;
    }
  }

  Future<CreatedAuthenticatedChunkedSnapshot> seal({
    required Directory source,
    required Directory target,
    required List<String> expectedTables,
    required String password,
    String? recoveryKey,
  }) async {
    final summary = await plainStore.verify(
      source,
      expectedTables: expectedTables,
    );
    _requireMissing(target);
    final temporary = _temporaryFor(target);
    temporary.createSync(recursive: true);
    try {
      final created = await ChunkEnvelopeCodec().create(
        password: password,
        recoveryKey: recoveryKey,
      );
      await File('${temporary.path}${Platform.pathSeparator}metadata.json')
          .writeAsString(created.metadata, flush: true);
      final manifest = await File(
        '${source.path}${Platform.pathSeparator}manifest.json',
      ).readAsBytes();
      await File('${temporary.path}${Platform.pathSeparator}manifest.etv2')
          .writeAsString(
            await created.session.seal(manifest, purpose: 'manifest'),
            flush: true,
          );
      final chunks =
          source
              .listSync(followLinks: false)
              .whereType<File>()
              .where((file) => file.uri.pathSegments.last.startsWith('chunk-'))
              .toList()
            ..sort((left, right) => left.path.compareTo(right.path));
      for (final chunk in chunks) {
        final plainName = chunk.uri.pathSegments.last;
        final purpose = plainName.substring(0, plainName.length - 7);
        final encryptedName = '$purpose.etv2';
        await File('${temporary.path}${Platform.pathSeparator}$encryptedName')
            .writeAsString(
              await created.session.seal(
                await chunk.readAsBytes(),
                purpose: purpose,
              ),
              flush: true,
            );
      }
      await temporary.rename(target.path);
      return CreatedAuthenticatedChunkedSnapshot(
        recoveryKey: created.recoveryKey,
        summary: summary,
      );
    } catch (_) {
      if (temporary.existsSync()) temporary.deleteSync(recursive: true);
      rethrow;
    }
  }

  Future<ChunkedSnapshotSummary> openWithPassword({
    required Directory source,
    required Directory target,
    required List<String> expectedTables,
    required String password,
  }) async {
    final metadata = await _metadata(source);
    final session = await ChunkEnvelopeCodec().openWithPassword(
      metadata,
      password,
    );
    return _open(source, target, expectedTables, session);
  }

  Future<ChunkedSnapshotSummary> openWithRecovery({
    required Directory source,
    required Directory target,
    required List<String> expectedTables,
    required String recoveryKey,
  }) async {
    final metadata = await _metadata(source);
    final session = await ChunkEnvelopeCodec().openWithRecovery(
      metadata,
      recoveryKey,
    );
    return _open(source, target, expectedTables, session);
  }

  Future<OpenedAuthenticatedChunkedSnapshot> readWithPassword({
    required Directory source,
    required List<String> expectedTables,
    required String password,
  }) async => _openReader(
    source,
    expectedTables,
    await ChunkEnvelopeCodec().openWithPassword(
      await _metadata(source),
      password,
    ),
  );

  Future<OpenedAuthenticatedChunkedSnapshot> readWithRecovery({
    required Directory source,
    required List<String> expectedTables,
    required String recoveryKey,
  }) async => _openReader(
    source,
    expectedTables,
    await ChunkEnvelopeCodec().openWithRecovery(
      await _metadata(source),
      recoveryKey,
    ),
  );

  Future<OpenedAuthenticatedChunkedSnapshot> _openReader(
    Directory source,
    List<String> expectedTables,
    ChunkEnvelopeSession session,
  ) async {
    final manifest = await session.open(
      await _readFile(
        source,
        'manifest.etv2',
        ChunkEnvelopeCodec.maxEnvelopeCharacters,
      ),
      purpose: 'manifest',
    );
    final parsed = _parseManifest(manifest, expectedTables, plainStore);
    _validateEncryptedEntities(source, parsed.chunks);
    return OpenedAuthenticatedChunkedSnapshot(
      summary: parsed.summary,
      rows: _readAuthenticatedRows(source, parsed, session),
    );
  }

  Future<ChunkedSnapshotSummary> _open(
    Directory source,
    Directory target,
    List<String> expectedTables,
    ChunkEnvelopeSession session,
  ) async {
    _requireMissing(target);
    final manifestEnvelope = await _readFile(
      source,
      'manifest.etv2',
      ChunkEnvelopeCodec.maxEnvelopeCharacters,
    );
    final manifest = await session.open(manifestEnvelope, purpose: 'manifest');
    final parsed = _parseManifest(manifest, expectedTables, plainStore);
    _validateEncryptedEntities(source, parsed.chunks);

    final temporary = _temporaryFor(target);
    temporary.createSync(recursive: true);
    try {
      await File('${temporary.path}${Platform.pathSeparator}manifest.json')
          .writeAsBytes(manifest, flush: true);
      await File('${temporary.path}${Platform.pathSeparator}manifest.sha256')
          .writeAsString(await _digest(manifest), flush: true);
      for (final chunk in parsed.chunks) {
        final purpose = chunk.purpose;
        final envelope = await _readFile(
          source,
          '$purpose.etv2',
          ChunkEnvelopeCodec.maxEnvelopeCharacters,
        );
        final bytes = await session.open(envelope, purpose: purpose);
        await File('${temporary.path}${Platform.pathSeparator}${chunk.file}')
            .writeAsBytes(bytes, flush: true);
      }
      final summary = await plainStore.verify(
        temporary,
        expectedTables: expectedTables,
      );
      await temporary.rename(target.path);
      return summary;
    } catch (_) {
      if (temporary.existsSync()) temporary.deleteSync(recursive: true);
      rethrow;
    }
  }

  Future<String> _metadata(Directory source) =>
      _readFile(source, 'metadata.json', 16384);
}

final class _AuthenticatedManifest {
  const _AuthenticatedManifest({required this.summary, required this.chunks});

  final ChunkedSnapshotSummary summary;
  final List<_AuthenticatedChunk> chunks;
}

final class _AuthenticatedChunk {
  const _AuthenticatedChunk({
    required this.table,
    required this.file,
    required this.rows,
    required this.bytes,
    required this.sha256,
  });

  final String table;
  final String file;
  final int rows;
  final int bytes;
  final String sha256;
  String get purpose => file.substring(0, file.length - 7);
}

_AuthenticatedManifest _parseManifest(
  List<int> manifest,
  List<String> expectedTables,
  ChunkedSnapshotStore limits,
) {
  try {
    final root = jsonDecode(utf8.decode(manifest));
    if (root is! Map<String, dynamic> ||
        root.length != 6 ||
        root['format'] != 'ledger-chunked-probe' ||
        root['version'] != 1 ||
        root['schema'] is! int ||
        root['schema'] < 1 ||
        root['schema'] > 10000 ||
        root['tables'] is! List ||
        root['totalRows'] is! int ||
        root['totalBytes'] is! int) {
      throw const BackupException(BackupError.invalidFormat);
    }
    final tables = root['tables'] as List;
    if (tables.length != expectedTables.length) {
      throw const BackupException(BackupError.invalidFormat);
    }
    final chunks = <_AuthenticatedChunk>[];
    var ordinal = 0;
    var totalRows = 0;
    var totalBytes = 0;
    for (var index = 0; index < tables.length; index++) {
      final table = tables[index];
      if (table is! Map<String, dynamic> ||
          table.length != 2 ||
          table['name'] != expectedTables[index] ||
          table['chunks'] is! List) {
        throw const BackupException(BackupError.invalidFormat);
      }
      for (final rawChunk in table['chunks'] as List) {
        final expected = 'chunk-${ordinal.toString().padLeft(8, '0')}.ndjson';
        if (rawChunk is! Map<String, dynamic> ||
            rawChunk.length != 5 ||
            rawChunk['ordinal'] != ordinal ||
            rawChunk['file'] != expected ||
            rawChunk['rows'] is! int ||
            rawChunk['bytes'] is! int ||
            rawChunk['sha256'] is! String ||
            rawChunk['rows'] < 1 ||
            rawChunk['rows'] > limits.maxRowsPerChunk ||
            rawChunk['bytes'] < 1 ||
            rawChunk['bytes'] > limits.maxChunkBytes ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(rawChunk['sha256'])) {
          throw const BackupException(BackupError.invalidFormat);
        }
        chunks.add(
          _AuthenticatedChunk(
            table: expectedTables[index],
            file: expected,
            rows: rawChunk['rows'] as int,
            bytes: rawChunk['bytes'] as int,
            sha256: rawChunk['sha256'] as String,
          ),
        );
        totalRows += rawChunk['rows'] as int;
        totalBytes += rawChunk['bytes'] as int;
        if (totalRows > limits.maxTotalRows ||
            totalBytes > limits.maxTotalBytes) {
          throw const BackupException(BackupError.limitExceeded);
        }
        ordinal++;
      }
    }
    if (root['totalRows'] != totalRows || root['totalBytes'] != totalBytes) {
      throw const BackupException(BackupError.invalidFormat);
    }
    return _AuthenticatedManifest(
      summary: ChunkedSnapshotSummary(
        schema: root['schema'] as int,
        totalRows: totalRows,
        totalBytes: totalBytes,
        chunkCount: ordinal,
      ),
      chunks: chunks,
    );
  } on FormatException {
    throw const BackupException(BackupError.invalidFormat);
  }
}

void _validateEncryptedEntities(
  Directory source,
  List<_AuthenticatedChunk> chunks,
) {
  final expected = {
    'metadata.json',
    'manifest.etv2',
    for (final chunk in chunks) '${chunk.purpose}.etv2',
  };
  final entities = source.listSync(followLinks: false);
  if (entities.length != expected.length ||
      entities.any(
        (entity) =>
            FileSystemEntity.typeSync(entity.path, followLinks: false) !=
                FileSystemEntityType.file ||
            !expected.contains(entity.uri.pathSegments.last),
      )) {
    throw const BackupException(BackupError.invalidFormat);
  }
}

Stream<ChunkedSnapshotRow> _readAuthenticatedRows(
  Directory source,
  _AuthenticatedManifest manifest,
  ChunkEnvelopeSession session,
) async* {
  for (final chunk in manifest.chunks) {
    final bytes = await session.open(
      await _readFile(
        source,
        '${chunk.purpose}.etv2',
        ChunkEnvelopeCodec.maxEnvelopeCharacters,
      ),
      purpose: chunk.purpose,
    );
    if (bytes.length != chunk.bytes || await _digest(bytes) != chunk.sha256) {
      throw const BackupException(BackupError.authenticationFailed);
    }
    final lines = const LineSplitter().convert(utf8.decode(bytes));
    if (lines.length != chunk.rows) {
      throw const BackupException(BackupError.invalidFormat);
    }
    for (final line in lines) {
      final row = jsonDecode(line);
      if (row is! Map<String, dynamic> ||
          jsonEncode(_authenticatedCanonical(row)) != line) {
        throw const BackupException(BackupError.invalidFormat);
      }
      yield ChunkedSnapshotRow(table: chunk.table, values: row);
    }
  }
}

Object? _authenticatedCanonical(Object? value) => switch (value) {
  Map<Object?, Object?> map => _authenticatedCanonicalMap(map),
  List<Object?> list => [
    for (final item in list) _authenticatedCanonical(item),
  ],
  String() || int() || bool() || null => value,
  _ => throw const BackupException(BackupError.invalidFormat),
};

Map<String, Object?> _authenticatedCanonicalMap(Map<Object?, Object?> map) {
  if (map.keys.any((key) => key is! String)) {
    throw const BackupException(BackupError.invalidFormat);
  }
  final keys = map.keys.cast<String>().toList()..sort();
  return {for (final key in keys) key: _authenticatedCanonical(map[key])};
}

Future<String> _readFile(Directory source, String name, int maxLength) async {
  if (FileSystemEntity.typeSync(source.path, followLinks: false) !=
      FileSystemEntityType.directory) {
    throw const BackupException(BackupError.invalidFormat);
  }
  final file = File('${source.path}${Platform.pathSeparator}$name');
  if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
          FileSystemEntityType.file ||
      file.lengthSync() > maxLength) {
    throw const BackupException(BackupError.limitExceeded);
  }
  return file.readAsString();
}

void _requireMissing(Directory target) {
  if (FileSystemEntity.typeSync(target.path, followLinks: false) !=
      FileSystemEntityType.notFound) {
    throw StateError('Authenticated snapshot target already exists');
  }
}

Directory _temporaryFor(Directory target) =>
    Directory('${target.path}.tmp-${DateTime.now().microsecondsSinceEpoch}');

Future<String> _digest(List<int> bytes) async =>
    (await Sha256().hash(bytes)).bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
