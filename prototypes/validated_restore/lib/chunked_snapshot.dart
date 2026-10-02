import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';

final class InvalidChunkedSnapshot implements Exception {
  const InvalidChunkedSnapshot();
}

final class ChunkedSnapshotSummary {
  const ChunkedSnapshotSummary({
    required this.schema,
    required this.totalRows,
    required this.totalBytes,
    required this.chunkCount,
  });

  final int schema;
  final int totalRows;
  final int totalBytes;
  final int chunkCount;
}

/// File-backed prototype for the next portable snapshot container.
///
/// Chunks and the manifest have independent integrity digests. They are not a
/// substitute for authenticated encryption: a production container must bind
/// the complete manifest with the password/recovery data key. The manifest is
/// written last and the temporary directory is renamed only after validation.
/// This container does not replace the released single-envelope format yet.
final class ChunkedSnapshotStore {
  const ChunkedSnapshotStore({
    this.maxChunkBytes = 1024 * 1024,
    this.maxRowsPerChunk = 1000,
    this.maxTotalRows = 1000000,
    this.maxTotalBytes = 512 * 1024 * 1024,
  });

  final int maxChunkBytes;
  final int maxRowsPerChunk;
  final int maxTotalRows;
  final int maxTotalBytes;

  Future<ChunkedSnapshotSummary> write({
    required Directory target,
    required int schema,
    required Map<String, Stream<Map<String, Object?>>> tables,
  }) async {
    _validateLimits();
    if (schema < 1 || schema > 10000 || tables.isEmpty) {
      throw const InvalidChunkedSnapshot();
    }
    final names = tables.keys.toList(growable: false);
    if (names.toSet().length != names.length ||
        names.any((name) => !_validName(name))) {
      throw const InvalidChunkedSnapshot();
    }
    if (FileSystemEntity.typeSync(target.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw StateError('Chunked snapshot target already exists');
    }
    final temporary = Directory(
      '${target.path}.tmp-${DateTime.now().microsecondsSinceEpoch}',
    );
    temporary.createSync(recursive: true);
    try {
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
          final fileName = 'chunk-${ordinal.toString().padLeft(8, '0')}.ndjson';
          final digest = await _digest(buffer);
          await File('${temporary.path}${Platform.pathSeparator}$fileName')
              .writeAsBytes(buffer, flush: true);
          chunks.add({
            'ordinal': ordinal,
            'file': fileName,
            'rows': rows,
            'bytes': buffer.length,
            'sha256': digest,
          });
          totalBytes += buffer.length;
          ordinal++;
          buffer = <int>[];
          rows = 0;
        }

        await for (final row in entry.value) {
          final encoded = utf8.encode('${jsonEncode(_canonical(row))}\n');
          if (encoded.length > maxChunkBytes) {
            throw const InvalidChunkedSnapshot();
          }
          if (rows > 0 &&
              (rows == maxRowsPerChunk ||
                  buffer.length + encoded.length > maxChunkBytes)) {
            await flush();
          }
          buffer.addAll(encoded);
          rows++;
          totalRows++;
          if (totalRows > maxTotalRows ||
              totalBytes + buffer.length > maxTotalBytes) {
            throw const InvalidChunkedSnapshot();
          }
        }
        await flush();
        tableManifests.add({'name': entry.key, 'chunks': chunks});
      }
      final manifest = {
        'format': 'ledger-chunked-probe',
        'version': 1,
        'schema': schema,
        'tables': tableManifests,
        'totalRows': totalRows,
        'totalBytes': totalBytes,
      };
      final manifestBytes = utf8.encode(jsonEncode(manifest));
      await File('${temporary.path}${Platform.pathSeparator}manifest.json')
          .writeAsBytes(manifestBytes, flush: true);
      await File('${temporary.path}${Platform.pathSeparator}manifest.sha256')
          .writeAsString(await _digest(manifestBytes), flush: true);
      final summary = await verify(temporary, expectedTables: names);
      await temporary.rename(target.path);
      return summary;
    } catch (_) {
      if (temporary.existsSync()) temporary.deleteSync(recursive: true);
      rethrow;
    }
  }

  Future<ChunkedSnapshotSummary> verify(
    Directory source, {
    required List<String> expectedTables,
  }) async {
    _validateLimits();
    if (expectedTables.isEmpty ||
        expectedTables.toSet().length != expectedTables.length ||
        expectedTables.any((name) => !_validName(name)) ||
        FileSystemEntity.typeSync(source.path, followLinks: false) !=
            FileSystemEntityType.directory) {
      throw const InvalidChunkedSnapshot();
    }
    try {
      final entities = source.listSync(followLinks: false);
      if (entities.any(
        (entity) =>
            FileSystemEntity.typeSync(entity.path, followLinks: false) !=
            FileSystemEntityType.file,
      )) {
        throw const InvalidChunkedSnapshot();
      }
      final manifestFile = File(
        '${source.path}${Platform.pathSeparator}manifest.json',
      );
      final manifestDigestFile = File(
        '${source.path}${Platform.pathSeparator}manifest.sha256',
      );
      if (!manifestFile.existsSync() ||
          !manifestDigestFile.existsSync() ||
          manifestFile.lengthSync() > 1024 * 1024) {
        throw const InvalidChunkedSnapshot();
      }
      final manifestBytes = await manifestFile.readAsBytes();
      final manifestDigest = await manifestDigestFile.readAsString();
      if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(manifestDigest) ||
          await _digest(manifestBytes) != manifestDigest) {
        throw const InvalidChunkedSnapshot();
      }
      final root = jsonDecode(utf8.decode(manifestBytes));
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
        throw const InvalidChunkedSnapshot();
      }
      final rawTables = root['tables'] as List;
      if (rawTables.length != expectedTables.length) {
        throw const InvalidChunkedSnapshot();
      }
      var totalRows = 0;
      var totalBytes = 0;
      var expectedOrdinal = 0;
      final seenFiles = <String>{'manifest.json', 'manifest.sha256'};
      for (var tableIndex = 0; tableIndex < rawTables.length; tableIndex++) {
        final table = rawTables[tableIndex];
        if (table is! Map<String, dynamic> ||
            table.length != 2 ||
            table['name'] != expectedTables[tableIndex] ||
            table['chunks'] is! List) {
          throw const InvalidChunkedSnapshot();
        }
        for (final rawChunk in table['chunks'] as List) {
          if (rawChunk is! Map<String, dynamic> ||
              rawChunk.length != 5 ||
              rawChunk['ordinal'] != expectedOrdinal ||
              rawChunk['file'] is! String ||
              rawChunk['rows'] is! int ||
              rawChunk['bytes'] is! int ||
              rawChunk['sha256'] is! String) {
            throw const InvalidChunkedSnapshot();
          }
          final fileName = rawChunk['file'] as String;
          if (fileName !=
                  'chunk-${expectedOrdinal.toString().padLeft(8, '0')}.ndjson' ||
              !seenFiles.add(fileName)) {
            throw const InvalidChunkedSnapshot();
          }
          final file = File('${source.path}${Platform.pathSeparator}$fileName');
          if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
              FileSystemEntityType.file) {
            throw const InvalidChunkedSnapshot();
          }
          final bytes = await file.readAsBytes();
          final rows = rawChunk['rows'] as int;
          if (bytes.isEmpty ||
              bytes.length != rawChunk['bytes'] ||
              bytes.length > maxChunkBytes ||
              rows < 1 ||
              rows > maxRowsPerChunk ||
              await _digest(bytes) != rawChunk['sha256']) {
            throw const InvalidChunkedSnapshot();
          }
          final lines = const LineSplitter().convert(utf8.decode(bytes));
          if (lines.length != rows) throw const InvalidChunkedSnapshot();
          for (final line in lines) {
            final row = jsonDecode(line);
            if (row is! Map<String, dynamic> ||
                jsonEncode(_canonical(row)) != line) {
              throw const InvalidChunkedSnapshot();
            }
          }
          totalRows += rows;
          totalBytes += bytes.length;
          if (totalRows > maxTotalRows || totalBytes > maxTotalBytes) {
            throw const InvalidChunkedSnapshot();
          }
          expectedOrdinal++;
        }
      }
      if (entities.length != seenFiles.length ||
          root['totalRows'] != totalRows ||
          root['totalBytes'] != totalBytes) {
        throw const InvalidChunkedSnapshot();
      }
      return ChunkedSnapshotSummary(
        schema: root['schema'] as int,
        totalRows: totalRows,
        totalBytes: totalBytes,
        chunkCount: expectedOrdinal,
      );
    } on InvalidChunkedSnapshot {
      rethrow;
    } catch (_) {
      throw const InvalidChunkedSnapshot();
    }
  }

  void _validateLimits() {
    if (maxChunkBytes < 128 ||
        maxRowsPerChunk < 1 ||
        maxTotalRows < maxRowsPerChunk ||
        maxTotalBytes < maxChunkBytes) {
      throw const InvalidChunkedSnapshot();
    }
  }
}

bool _validName(String value) =>
    RegExp(r'^[a-z][a-z0-9_]{0,63}$').hasMatch(value);

Object? _canonical(Object? value) => switch (value) {
  Map<Object?, Object?> map => _canonicalMap(map),
  List<Object?> list => [for (final item in list) _canonical(item)],
  String() || int() || bool() || null => value,
  _ => throw const InvalidChunkedSnapshot(),
};

Map<String, Object?> _canonicalMap(Map<Object?, Object?> map) {
  if (map.keys.any((key) => key is! String)) {
    throw const InvalidChunkedSnapshot();
  }
  final keys = map.keys.cast<String>().toList()..sort();
  return {for (final key in keys) key: _canonical(map[key])};
}

Future<String> _digest(List<int> bytes) async =>
    (await Sha256().hash(bytes)).bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
