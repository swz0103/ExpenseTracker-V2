import 'dart:convert';

import 'cloud_backup.dart';
import 'cloud_backup_history.dart';

const googleDriveBackupProviderId = 'google-drive-v3';

enum DriveApiFailure {
  authenticationRequired,
  permissionDenied,
  quotaExceeded,
  throttled,
  unavailable,
  conflict,
  uncertainResult,
}

final class DriveApiException implements Exception {
  const DriveApiException(this.failure);

  final DriveApiFailure failure;

  @override
  String toString() => 'DriveApiException(${failure.name})';
}

final class DriveFileRecord {
  DriveFileRecord({
    required this.id,
    required this.mimeType,
    required this.byteLength,
    required Map<String, String> appProperties,
    required this.trashed,
  }) : appProperties = Map<String, String>.unmodifiable(appProperties);

  final String id;
  final String mimeType;
  final int byteLength;
  final Map<String, String> appProperties;
  final bool trashed;
}

/// Small REST boundary. The concrete Android transport owns OAuth tokens,
/// HTTPS, timeouts and Drive error parsing; this adapter owns backup semantics.
abstract interface class DriveBackupApi {
  Future<String> generateFileId();

  Future<DriveFileRecord?> getFile(String fileId);

  Future<DriveFileRecord> createFile({
    required String fileId,
    required String name,
    required String mimeType,
    required List<int> bytes,
    required Map<String, String> appProperties,
  });

  Future<List<int>> downloadFile(String fileId);

  /// Must paginate to completion and filter to non-trashed files carrying the
  /// ExpenseTracker backup app property.
  Future<List<DriveFileRecord>> listBackupFiles();

  Future<void> deleteFile(String fileId);
}

/// A generated Drive file ID must be durable before upload starts. The store
/// contains routing metadata only; no OAuth token, envelope or financial data.
abstract interface class DriveReservationStore {
  Future<String?> objectIdFor(String backupId);

  Future<void> save({required String backupId, required String objectId});
}

final class GoogleDriveBackupProvider
    implements CloudBackupProvider, CloudBackupCatalogProvider {
  const GoogleDriveBackupProvider({
    required this.api,
    required this.reservations,
  });

  final DriveBackupApi api;
  final DriveReservationStore reservations;

  @override
  String get providerId => googleDriveBackupProviderId;

  @override
  Future<RemoteBackupReservation> reserve(
    VerifiedBackupArtifact artifact,
  ) async {
    try {
      var objectId = await reservations.objectIdFor(artifact.backupId);
      if (objectId == null) {
        objectId = await api.generateFileId();
        _validateDriveId(objectId);
        await reservations.save(
          backupId: artifact.backupId,
          objectId: objectId,
        );
      }
      _validateDriveId(objectId);
      return RemoteBackupReservation(
        providerId: providerId,
        objectId: objectId,
        backupId: artifact.backupId,
      );
    } on DriveApiException catch (error) {
      throw _providerError(error.failure);
    }
  }

  @override
  Future<RemoteBackupMetadata?> inspect(
    RemoteBackupReservation reservation,
  ) async {
    try {
      final file = await api.getFile(reservation.objectId);
      if (file == null) return null;
      if (file.trashed) {
        throw const CloudBackupProviderException(
          CloudBackupProviderFailure.unavailable,
        );
      }
      return _metadata(file);
    } on DriveApiException catch (error) {
      throw _providerError(error.failure);
    }
  }

  @override
  Future<RemoteBackupMetadata> upload(
    RemoteBackupReservation reservation,
    VerifiedBackupArtifact artifact,
  ) async {
    try {
      final file = await api.createFile(
        fileId: reservation.objectId,
        name: _fileName(artifact),
        mimeType: cloudBackupContentType,
        bytes: utf8.encode(artifact.envelope),
        appProperties: _properties(artifact),
      );
      return _metadata(file);
    } on DriveApiException catch (error) {
      throw _providerError(error.failure);
    }
  }

  @override
  Future<List<int>> download(String objectId) async {
    try {
      return await api.downloadFile(objectId);
    } on DriveApiException catch (error) {
      throw _providerError(error.failure);
    }
  }

  @override
  Future<List<RemoteBackupMetadata>> listBackups() async {
    try {
      final files = await api.listBackupFiles();
      return files
          .where((file) => !file.trashed)
          .map(_metadata)
          .toList(growable: false);
    } on DriveApiException catch (error) {
      throw _providerError(error.failure);
    }
  }

  @override
  Future<void> deleteBackup(RemoteBackupMetadata expected) async {
    if (expected.providerId != providerId) {
      throw const CloudBackupValidationException(
        CloudBackupValidationFailure.remoteMetadataMismatch,
      );
    }
    try {
      final file = await api.getFile(expected.objectId);
      if (file == null ||
          file.trashed ||
          !_sameRemote(_metadata(file), expected)) {
        throw const CloudBackupValidationException(
          CloudBackupValidationFailure.remoteMetadataMismatch,
        );
      }
      await api.deleteFile(expected.objectId);
    } on DriveApiException catch (error) {
      throw _providerError(error.failure);
    }
  }
}

bool _sameRemote(RemoteBackupMetadata a, RemoteBackupMetadata b) =>
    a.providerId == b.providerId &&
    a.objectId == b.objectId &&
    a.backupId == b.backupId &&
    a.sha256 == b.sha256 &&
    a.byteLength == b.byteLength &&
    a.createdAt.toUtc() == b.createdAt.toUtc() &&
    a.contentType == b.contentType;

Map<String, String> _properties(VerifiedBackupArtifact artifact) => {
  'format': 'ExpenseTracker-V2-backup',
  'formatVersion': '1',
  'backupId': artifact.backupId,
  'sha256': artifact.sha256,
  'byteLength': artifact.byteLength.toString(),
  'createdAt': artifact.createdAt.toIso8601String(),
};

String _fileName(VerifiedBackupArtifact artifact) {
  final date = artifact.createdAt.toIso8601String().replaceAll(':', '-');
  return 'ExpenseTracker-V2-$date-${artifact.backupId}.etv2backup';
}

RemoteBackupMetadata _metadata(DriveFileRecord file) {
  final properties = file.appProperties;
  final length = int.tryParse(properties['byteLength'] ?? '');
  final createdAt = DateTime.tryParse(properties['createdAt'] ?? '');
  final backupId = properties['backupId'];
  final sha256 = properties['sha256'];
  if (properties.length != 6 ||
      properties['format'] != 'ExpenseTracker-V2-backup' ||
      properties['formatVersion'] != '1' ||
      backupId == null ||
      sha256 == null ||
      length == null ||
      length != file.byteLength ||
      createdAt == null ||
      file.mimeType != cloudBackupContentType) {
    throw const CloudBackupValidationException(
      CloudBackupValidationFailure.remoteMetadataMismatch,
    );
  }
  return RemoteBackupMetadata(
    providerId: googleDriveBackupProviderId,
    objectId: file.id,
    backupId: backupId,
    sha256: sha256,
    byteLength: length,
    createdAt: createdAt.toUtc(),
    contentType: file.mimeType,
  );
}

CloudBackupProviderException _providerError(DriveApiFailure failure) =>
    CloudBackupProviderException(switch (failure) {
      DriveApiFailure.authenticationRequired =>
        CloudBackupProviderFailure.authenticationRequired,
      DriveApiFailure.permissionDenied =>
        CloudBackupProviderFailure.permissionDenied,
      DriveApiFailure.quotaExceeded => CloudBackupProviderFailure.quotaExceeded,
      DriveApiFailure.throttled => CloudBackupProviderFailure.throttled,
      DriveApiFailure.unavailable => CloudBackupProviderFailure.unavailable,
      DriveApiFailure.conflict || DriveApiFailure.uncertainResult =>
        CloudBackupProviderFailure.uncertainResult,
    });

void _validateDriveId(String value) {
  if (value.isEmpty ||
      value.length > 200 ||
      !RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(value)) {
    throw const CloudBackupValidationException(
      CloudBackupValidationFailure.reservationConflict,
    );
  }
}
