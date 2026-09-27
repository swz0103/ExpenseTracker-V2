import 'dart:convert';
import 'dart:io';

import 'package:backup_envelope_probe/envelope.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:storage_generation_probe/generation_store.dart';
import 'package:storage_generation_probe/lock_wait.dart';

import 'ledger_store.dart';

enum SafetyBackupProblem { destination, verification, storage }

final class SafetyBackupUnavailable implements Exception {
  const SafetyBackupUnavailable(this.problem);
  final SafetyBackupProblem problem;
  @override
  String toString() => 'SafetyBackupUnavailable(${problem.name})';
}

/// Contains a new per-backup recovery secret; never log or persist this object.
final class VerifiedSafetyBackup {
  const VerifiedSafetyBackup(this.file, this.source, this.recoveryKey);
  final File file;

  /// Identity of the source generation. Its installation fingerprint is NOT
  /// a digest of this backup after subsequent financial postings.
  final GenerationReceipt source;
  final String recoveryKey;
}

/// Limited host probe for current schema 3 only. The destination must be an
/// existing, application-owned directory outside the generation store.
/// No migration, upgrade receipt, credential retention or cleanup is performed.
Future<VerifiedSafetyBackup> createSafetyBackup(
  LedgerStore store,
  Directory destination,
  PublicId backupId, {
  required String password,
  LockWaitCancellation? cancellation,
  Future<void> Function(String, File)? checkpoint,
}) async {
  late VerifiedSafetyBackup result;
  Exception? failure;
  await store.generations.withCurrent<void>((sourceFile, key, receipt) async {
    try {
      if (await FileSystemEntity.type(destination.path, followLinks: false) !=
          FileSystemEntityType.directory) {
        throw const SafetyBackupUnavailable(SafetyBackupProblem.destination);
      }
      final directory = await destination.resolveSymbolicLinks();
      final sourceDirectory = await store.generations.directory
          .resolveSymbolicLinks();
      // A backup must not add unknown files to the generation control directory.
      final normalized = Platform.isWindows
          ? directory.toLowerCase()
          : directory;
      final sourceRoot = Platform.isWindows
          ? sourceDirectory.toLowerCase()
          : sourceDirectory;
      if (normalized == sourceRoot ||
          normalized.startsWith('$sourceRoot${Platform.pathSeparator}')) {
        throw const SafetyBackupUnavailable(SafetyBackupProblem.destination);
      }
      final file = File('$directory/${backupId.value}.envelope');
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw const SafetyBackupUnavailable(SafetyBackupProblem.destination);
      }
      // The payload adapter refuses unknown versions before opening Drift. Keep
      // the lifecycle lock through snapshot, durable write and both readbacks.
      final snapshot = await LedgerPayload().inspect(sourceFile, key, receipt);
      final codec = EnvelopeCodec();
      final created = await codec.create(
        utf8.encode(snapshot),
        password: password,
      );
      await file.create(exclusive: true);
      await file.writeAsString(created.envelope, flush: true);
      await checkpoint?.call('written', file);
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
              FileSystemEntityType.file ||
          await file.length() > EnvelopeCodec.maxEnvelopeCharacters) {
        throw const SafetyBackupUnavailable(SafetyBackupProblem.verification);
      }
      final saved = await file.readAsString();
      if (saved != created.envelope ||
          utf8.decode(await codec.openWithPassword(saved, password)) !=
              snapshot ||
          utf8.decode(
                await codec.openWithRecovery(saved, created.recoveryKey),
              ) !=
              snapshot) {
        throw const SafetyBackupUnavailable(SafetyBackupProblem.verification);
      }
      await checkpoint?.call('verified', file);
      result = VerifiedSafetyBackup(file, receipt, created.recoveryKey);
    } on SafetyBackupUnavailable catch (error) {
      failure = error;
    } on BackupException catch (error) {
      failure = error;
    } on FileSystemException {
      // Preserve any partial artifact. A later attempt cannot overwrite it.
      failure = const SafetyBackupUnavailable(SafetyBackupProblem.storage);
    }
  }, cancellation: cancellation);
  // Report known backup failures outside the coordinator, which intentionally
  // sanitizes unexpected callback failures as generation recovery problems.
  if (failure != null) throw failure!;
  return result;
}
