import 'dart:convert';

import 'package:backup_envelope_probe/envelope.dart';
import 'package:cryptography/cryptography.dart';

const cloudBackupContentType = 'application/vnd.expensetracker.backup+json';

enum CloudBackupProviderFailure {
  authenticationRequired,
  permissionDenied,
  quotaExceeded,
  throttled,
  unavailable,
  uncertainResult,
}

final class CloudBackupProviderException implements Exception {
  const CloudBackupProviderException(this.failure);

  final CloudBackupProviderFailure failure;

  @override
  String toString() => 'CloudBackupProviderException(${failure.name})';
}

enum CloudBackupValidationFailure {
  invalidArtifact,
  reservationConflict,
  remoteMetadataMismatch,
  corruptDownload,
  credentialRejected,
}

final class CloudBackupValidationException implements Exception {
  const CloudBackupValidationException(this.failure);

  final CloudBackupValidationFailure failure;

  @override
  String toString() => 'CloudBackupValidationException(${failure.name})';
}

/// An encrypted portable envelope verified through both independent unlock
/// paths before it may enter a provider workflow. Credentials are not retained.
final class VerifiedBackupArtifact {
  VerifiedBackupArtifact._({
    required this.backupId,
    required this.envelope,
    required this.sha256,
    required this.byteLength,
    required this.createdAt,
  });

  final String backupId;
  final String envelope;
  final String sha256;
  final int byteLength;
  final DateTime createdAt;

  static Future<VerifiedBackupArtifact> verify({
    required String backupId,
    required String envelope,
    required String password,
    required String recoveryKey,
    required DateTime createdAt,
  }) async {
    _validateIdentifier(backupId, 'backupId');
    if (envelope.isEmpty) {
      throw const CloudBackupValidationException(
        CloudBackupValidationFailure.invalidArtifact,
      );
    }
    final codec = EnvelopeCodec();
    try {
      final passwordPayload = await codec.openWithPassword(envelope, password);
      final recoveryPayload = await codec.openWithRecovery(
        envelope,
        recoveryKey,
      );
      if (!_sameBytes(passwordPayload, recoveryPayload)) {
        throw const CloudBackupValidationException(
          CloudBackupValidationFailure.invalidArtifact,
        );
      }
    } on BackupException {
      throw const CloudBackupValidationException(
        CloudBackupValidationFailure.invalidArtifact,
      );
    }
    final bytes = utf8.encode(envelope);
    final digest = await Sha256().hash(bytes);
    return VerifiedBackupArtifact._(
      backupId: backupId,
      envelope: envelope,
      sha256: _hex(digest.bytes),
      byteLength: bytes.length,
      createdAt: createdAt.toUtc(),
    );
  }

  /// Rehydrates an artifact that was already double-verified before it was
  /// staged in private storage. The immutable envelope is authenticated by its
  /// saved digest; unlock credentials are deliberately not persisted.
  static Future<VerifiedBackupArtifact> fromStaged({
    required String backupId,
    required String envelope,
    required String sha256,
    required int byteLength,
    required DateTime createdAt,
  }) async {
    _validateIdentifier(backupId, 'backupId');
    if (!_isSha256(sha256) || byteLength < 1) {
      throw const CloudBackupValidationException(
        CloudBackupValidationFailure.invalidArtifact,
      );
    }
    final bytes = utf8.encode(envelope);
    final digest = _hex((await Sha256().hash(bytes)).bytes);
    if (bytes.length != byteLength || digest != sha256) {
      throw const CloudBackupValidationException(
        CloudBackupValidationFailure.invalidArtifact,
      );
    }
    return VerifiedBackupArtifact._(
      backupId: backupId,
      envelope: envelope,
      sha256: sha256,
      byteLength: byteLength,
      createdAt: createdAt.toUtc(),
    );
  }
}

/// A stable remote identity obtained before bytes are uploaded. Retrying the
/// same backup ID must return the same reservation.
final class RemoteBackupReservation {
  const RemoteBackupReservation({
    required this.providerId,
    required this.objectId,
    required this.backupId,
  });

  final String providerId;
  final String objectId;
  final String backupId;
}

final class RemoteBackupMetadata {
  const RemoteBackupMetadata({
    required this.providerId,
    required this.objectId,
    required this.backupId,
    required this.sha256,
    required this.byteLength,
    required this.createdAt,
    required this.contentType,
  });

  final String providerId;
  final String objectId;
  final String backupId;
  final String sha256;
  final int byteLength;
  final DateTime createdAt;
  final String contentType;
}

/// Provider adapters own OAuth, HTTP and provider-specific revision handling.
/// They never receive the ledger password or recovery key.
abstract interface class CloudBackupProvider {
  String get providerId;

  Future<RemoteBackupReservation> reserve(VerifiedBackupArtifact artifact);

  Future<RemoteBackupMetadata?> inspect(RemoteBackupReservation reservation);

  Future<RemoteBackupMetadata> upload(
    RemoteBackupReservation reservation,
    VerifiedBackupArtifact artifact,
  );

  Future<List<int>> download(String objectId);
}

/// Coordinates provider-neutral idempotency and uncertain-result recovery.
/// Durable scheduling is supplied separately by the encrypted job queue.
final class CloudBackupCoordinator {
  const CloudBackupCoordinator(this.provider);

  final CloudBackupProvider provider;

  Future<RemoteBackupMetadata> upload(VerifiedBackupArtifact artifact) async {
    final reservation = await provider.reserve(artifact);
    _validateReservation(reservation, artifact);
    final existing = await provider.inspect(reservation);
    if (existing != null) {
      _validateMetadata(existing, reservation, artifact);
      return existing;
    }
    try {
      final uploaded = await provider.upload(reservation, artifact);
      _validateMetadata(uploaded, reservation, artifact);
      return uploaded;
    } on CloudBackupProviderException catch (error) {
      if (error.failure != CloudBackupProviderFailure.uncertainResult) rethrow;
      final recovered = await provider.inspect(reservation);
      if (recovered == null) rethrow;
      _validateMetadata(recovered, reservation, artifact);
      return recovered;
    }
  }

  Future<String> downloadAndVerify(
    RemoteBackupMetadata metadata, {
    String? password,
    String? recoveryKey,
  }) async {
    if ((password == null) == (recoveryKey == null)) {
      throw ArgumentError('Provide exactly one backup credential');
    }
    _validateIdentifier(metadata.objectId, 'objectId');
    if (metadata.providerId != provider.providerId ||
        metadata.contentType != cloudBackupContentType ||
        metadata.byteLength < 1 ||
        !_isSha256(metadata.sha256)) {
      throw const CloudBackupValidationException(
        CloudBackupValidationFailure.remoteMetadataMismatch,
      );
    }
    final bytes = await provider.download(metadata.objectId);
    final digest = _hex((await Sha256().hash(bytes)).bytes);
    if (bytes.length != metadata.byteLength || digest != metadata.sha256) {
      throw const CloudBackupValidationException(
        CloudBackupValidationFailure.corruptDownload,
      );
    }
    late final String envelope;
    try {
      envelope = utf8.decode(bytes);
      final codec = EnvelopeCodec();
      if (password != null) {
        await codec.openWithPassword(envelope, password);
      } else {
        await codec.openWithRecovery(envelope, recoveryKey!);
      }
    } on FormatException {
      throw const CloudBackupValidationException(
        CloudBackupValidationFailure.corruptDownload,
      );
    } on BackupException {
      throw const CloudBackupValidationException(
        CloudBackupValidationFailure.credentialRejected,
      );
    }
    return envelope;
  }

  void _validateReservation(
    RemoteBackupReservation reservation,
    VerifiedBackupArtifact artifact,
  ) {
    try {
      _validateIdentifier(reservation.providerId, 'providerId');
      _validateIdentifier(reservation.objectId, 'objectId');
      _validateIdentifier(reservation.backupId, 'backupId');
    } on ArgumentError {
      throw const CloudBackupValidationException(
        CloudBackupValidationFailure.reservationConflict,
      );
    }
    if (reservation.providerId != provider.providerId ||
        reservation.backupId != artifact.backupId) {
      throw const CloudBackupValidationException(
        CloudBackupValidationFailure.reservationConflict,
      );
    }
  }

  void _validateMetadata(
    RemoteBackupMetadata metadata,
    RemoteBackupReservation reservation,
    VerifiedBackupArtifact artifact,
  ) {
    if (metadata.providerId != reservation.providerId ||
        metadata.objectId != reservation.objectId ||
        metadata.backupId != artifact.backupId ||
        metadata.sha256 != artifact.sha256 ||
        metadata.byteLength != artifact.byteLength ||
        metadata.contentType != cloudBackupContentType ||
        metadata.createdAt.toUtc() != artifact.createdAt) {
      throw const CloudBackupValidationException(
        CloudBackupValidationFailure.remoteMetadataMismatch,
      );
    }
  }
}

void _validateIdentifier(String value, String name) {
  if (value.isEmpty ||
      value.length > 200 ||
      !RegExp(r'^[a-zA-Z0-9._:-]+$').hasMatch(value)) {
    throw ArgumentError.value(value, name);
  }
}

bool _isSha256(String value) => RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var difference = 0;
  for (var i = 0; i < a.length; i++) {
    difference |= a[i] ^ b[i];
  }
  return difference == 0;
}

String _hex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
