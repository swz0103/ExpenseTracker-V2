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
    final chunkFiles = _chunkFiles(manifest, expectedTables);
    final expectedEncrypted = {
      'metadata.json',
      'manifest.etv2',
      for (final chunk in chunkFiles)
        '${chunk.substring(0, chunk.length - 7)}.etv2',
    };
    final entities = source.listSync(followLinks: false);
    if (entities.length != expectedEncrypted.length ||
        entities.any(
          (entity) =>
              FileSystemEntity.typeSync(entity.path, followLinks: false) !=
                  FileSystemEntityType.file ||
              !expectedEncrypted.contains(entity.uri.pathSegments.last),
        )) {
      throw const BackupException(BackupError.invalidFormat);
    }

    final temporary = _temporaryFor(target);
    temporary.createSync(recursive: true);
    try {
      await File('${temporary.path}${Platform.pathSeparator}manifest.json')
          .writeAsBytes(manifest, flush: true);
      await File('${temporary.path}${Platform.pathSeparator}manifest.sha256')
          .writeAsString(await _digest(manifest), flush: true);
      for (final chunkName in chunkFiles) {
        final purpose = chunkName.substring(0, chunkName.length - 7);
        final envelope = await _readFile(
          source,
          '$purpose.etv2',
          ChunkEnvelopeCodec.maxEnvelopeCharacters,
        );
        final bytes = await session.open(envelope, purpose: purpose);
        await File('${temporary.path}${Platform.pathSeparator}$chunkName')
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

List<String> _chunkFiles(List<int> manifest, List<String> expectedTables) {
  try {
    final root = jsonDecode(utf8.decode(manifest));
    if (root is! Map<String, dynamic> ||
        root.length != 6 ||
        root['format'] != 'ledger-chunked-probe' ||
        root['version'] != 1 ||
        root['tables'] is! List) {
      throw const BackupException(BackupError.invalidFormat);
    }
    final tables = root['tables'] as List;
    if (tables.length != expectedTables.length) {
      throw const BackupException(BackupError.invalidFormat);
    }
    final files = <String>[];
    var ordinal = 0;
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
            rawChunk['file'] != expected) {
          throw const BackupException(BackupError.invalidFormat);
        }
        files.add(expected);
        ordinal++;
      }
    }
    return files;
  } on FormatException {
    throw const BackupException(BackupError.invalidFormat);
  }
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
