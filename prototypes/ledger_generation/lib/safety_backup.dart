import 'dart:convert';
import 'dart:io';

import 'package:backup_envelope_probe/envelope.dart';
import 'package:crypto/crypto.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:storage_generation_probe/generation_store.dart';
import 'package:storage_generation_probe/lock_wait.dart';
import 'package:validated_restore_probe/snapshot.dart';

import 'ledger_store.dart';

part 'category_upgrade.dart';

enum SafetyBackupProblem { destination, verification, storage }

final class SafetyBackupUnavailable implements Exception {
  const SafetyBackupUnavailable(this.problem);
  final SafetyBackupProblem problem;
  @override
  String toString() => 'SafetyBackupUnavailable(${problem.name})';
}

/// Contains a recovery secret; never log or persist this object.
final class VerifiedSafetyBackup {
  const VerifiedSafetyBackup(
    this.file,
    this.source,
    this.recoveryKey,
    this.envelopeDigest,
  );
  final File file;

  /// Installation fingerprint is not the live financial snapshot digest.
  final GenerationReceipt source;
  final String recoveryKey;

  /// Digest of the exact encrypted bytes successfully read back and verified.
  final String envelopeDigest;
}

/// Saves a new backup under one lifecycle lease; existing files are not replaced.
Future<VerifiedSafetyBackup> createSafetyBackup(
  LedgerStore store,
  Directory destination,
  PublicId backupId, {
  required String password,
  String? recoveryKey,
  LockWaitCancellation? cancellation,
  Future<void> Function(String, File)? checkpoint,
}) async {
  late VerifiedSafetyBackup result;
  Exception? failure;
  await store.generations.withCurrent<void>((file, key, receipt) async {
    try {
      final snapshot = await LedgerPayload(
        categoryAware: store.categoryAware,
        categoryReferences: store.categoryReferences,
        tagsAware: store.tagsAware,
        merchantsAware: store.merchantsAware,
        transfersAware: store.transfersAware,
        fxTransfersAware: store.fxTransfersAware,
        refundsAware: store.refundsAware,
        reversalsAware: store.reversalsAware,
        notesAware: store.notesAware,
        correctionsAware: store.correctionsAware,
        tombstonesAware: store.tombstonesAware,
      ).inspect(file, key, receipt);
      result = await _persistSafetyBackup(
        store,
        destination,
        backupId,
        receipt,
        snapshot,
        password: password,
        recoveryKey: recoveryKey,
        checkpoint: checkpoint,
      );
    } on SafetyBackupUnavailable catch (error) {
      failure = error;
    } on BackupException catch (error) {
      failure = error;
    } on FileSystemException {
      failure = const SafetyBackupUnavailable(SafetyBackupProblem.storage);
    }
  }, cancellation: cancellation);
  if (failure != null) throw failure!;
  return result;
}

Future<VerifiedSafetyBackup> _persistSafetyBackup(
  LedgerStore store,
  Directory destination,
  PublicId backupId,
  GenerationReceipt source,
  String snapshot, {
  required String password,
  String? recoveryKey,
  bool reuseExisting = false,
  Future<void> Function(String, File)? checkpoint,
}) async {
  if (await FileSystemEntity.type(destination.path, followLinks: false) !=
      FileSystemEntityType.directory)
    throw const SafetyBackupUnavailable(SafetyBackupProblem.destination);
  final directory = await destination.resolveSymbolicLinks();
  final sourceDirectory = await store.generations.directory
      .resolveSymbolicLinks();
  final normalized = Platform.isWindows ? directory.toLowerCase() : directory;
  final sourceRoot = Platform.isWindows
      ? sourceDirectory.toLowerCase()
      : sourceDirectory;
  if (normalized == sourceRoot ||
      normalized.startsWith('$sourceRoot${Platform.pathSeparator}'))
    throw const SafetyBackupUnavailable(SafetyBackupProblem.destination);
  final file = File('$directory/${backupId.value}.envelope');
  final type = await FileSystemEntity.type(file.path, followLinks: false);
  final codec = EnvelopeCodec();
  CreatedBackup? created;
  if (type == FileSystemEntityType.notFound) {
    created = await codec.create(
      utf8.encode(snapshot),
      password: password,
      recoveryKey: recoveryKey,
    );
    recoveryKey = created.recoveryKey;
    await file.create(exclusive: true);
    await checkpoint?.call('created', file);
    await file.writeAsString(created.envelope, flush: true);
    await checkpoint?.call('written', file);
  } else if (!reuseExisting ||
      type != FileSystemEntityType.file ||
      recoveryKey == null) {
    throw const SafetyBackupUnavailable(SafetyBackupProblem.destination);
  }
  if (await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.file ||
      await file.length() > EnvelopeCodec.maxEnvelopeCharacters)
    throw const SafetyBackupUnavailable(SafetyBackupProblem.verification);
  final savedBytes = await file.readAsBytes();
  if (savedBytes.length > EnvelopeCodec.maxEnvelopeCharacters)
    throw const SafetyBackupUnavailable(SafetyBackupProblem.verification);
  final saved = utf8.decode(savedBytes);
  // Hash the persisted bytes, before UTF-8 decoding can discard a BOM.
  final digest = sha256.convert(savedBytes).toString();
  if ((created != null &&
          digest != sha256.convert(utf8.encode(created.envelope)).toString()) ||
      utf8.decode(await codec.openWithPassword(saved, password)) != snapshot ||
      utf8.decode(await codec.openWithRecovery(saved, recoveryKey)) != snapshot)
    throw const SafetyBackupUnavailable(SafetyBackupProblem.verification);
  await checkpoint?.call('verified', file);
  return VerifiedSafetyBackup(file, source, recoveryKey, digest);
}
