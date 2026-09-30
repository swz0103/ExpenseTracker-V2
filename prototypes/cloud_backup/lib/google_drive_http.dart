import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'google_drive_adapter.dart';

abstract interface class DriveAccessTokenSource {
  Future<String> accessToken();
}

final class DriveHttpRequest {
  DriveHttpRequest({
    required this.method,
    required this.uri,
    Map<String, String> headers = const {},
    List<int> body = const [],
    this.maxResponseBytes = 1024 * 1024,
  }) : headers = Map.unmodifiable(headers),
       body = List.unmodifiable(body);

  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final List<int> body;
  final int maxResponseBytes;
}

final class DriveHttpResponse {
  DriveHttpResponse({
    required this.statusCode,
    Map<String, String> headers = const {},
    List<int> body = const [],
  }) : headers = Map.unmodifiable({
         for (final entry in headers.entries)
           entry.key.toLowerCase(): entry.value,
       }),
       body = List.unmodifiable(body);

  final int statusCode;
  final Map<String, String> headers;
  final List<int> body;
}

final class DriveHttpTransportException implements Exception {
  const DriveHttpTransportException();
}

abstract interface class DriveHttpTransport {
  Future<DriveHttpResponse> send(
    DriveHttpRequest request, {
    required Duration timeout,
  });
}

final class IoDriveHttpTransport implements DriveHttpTransport {
  const IoDriveHttpTransport();

  @override
  Future<DriveHttpResponse> send(
    DriveHttpRequest request, {
    required Duration timeout,
  }) async {
    final client = HttpClient()..autoUncompress = true;
    try {
      final outgoing = await client
          .openUrl(request.method, request.uri)
          .timeout(timeout);
      outgoing.followRedirects = false;
      request.headers.forEach(outgoing.headers.set);
      if (request.body.isNotEmpty) outgoing.add(request.body);
      final incoming = await outgoing.close().timeout(timeout);
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in incoming.timeout(timeout)) {
        if (bytes.length + chunk.length > request.maxResponseBytes) {
          throw const DriveHttpTransportException();
        }
        bytes.add(chunk);
      }
      final responseHeaders = <String, String>{};
      incoming.headers.forEach((name, values) {
        responseHeaders[name] = values.join(',');
      });
      return DriveHttpResponse(
        statusCode: incoming.statusCode,
        headers: responseHeaders,
        body: bytes.takeBytes(),
      );
    } on DriveHttpTransportException {
      rethrow;
    } on Object {
      throw const DriveHttpTransportException();
    } finally {
      client.close(force: true);
    }
  }
}

final class GoogleDriveRestApi implements DriveBackupApi {
  const GoogleDriveRestApi({
    required this.transport,
    required this.tokens,
    this.timeout = const Duration(seconds: 30),
  });

  final DriveHttpTransport transport;
  final DriveAccessTokenSource tokens;
  final Duration timeout;

  static final _api = Uri.parse('https://www.googleapis.com/drive/v3/');
  static final _upload = Uri.parse(
    'https://www.googleapis.com/upload/drive/v3/',
  );

  @override
  Future<String> generateFileId() async {
    final response = await _send(
      'GET',
      _api
          .resolve('files/generateIds')
          .replace(
            queryParameters: const {
              'count': '1',
              'space': 'drive',
              'type': 'files',
            },
          ),
    );
    final json = _jsonObject(response);
    final ids = json['ids'];
    if (ids is! List || ids.length != 1 || ids.single is! String) {
      throw const DriveApiException(DriveApiFailure.unavailable);
    }
    return ids.single as String;
  }

  @override
  Future<DriveFileRecord?> getFile(String fileId) async {
    final response = await _send(
      'GET',
      _api
          .resolve('files/${Uri.encodeComponent(fileId)}')
          .replace(
            queryParameters: const {
              'fields': 'id,mimeType,size,appProperties,trashed',
            },
          ),
      allowNotFound: true,
    );
    if (response.statusCode == HttpStatus.notFound) return null;
    return _file(_jsonObject(response));
  }

  @override
  Future<DriveFileRecord> createFile({
    required String fileId,
    required String name,
    required String mimeType,
    required List<int> bytes,
    required Map<String, String> appProperties,
  }) async {
    final metadata = utf8.encode(
      jsonEncode({
        'id': fileId,
        'name': name,
        'mimeType': mimeType,
        'appProperties': appProperties,
      }),
    );
    final initiate = await _send(
      'POST',
      _upload
          .resolve('files')
          .replace(
            queryParameters: const {
              'uploadType': 'resumable',
              'fields': 'id,mimeType,size,appProperties,trashed',
            },
          ),
      body: metadata,
      headers: {
        HttpHeaders.contentTypeHeader: 'application/json; charset=utf-8',
        'x-upload-content-type': mimeType,
        'x-upload-content-length': bytes.length.toString(),
      },
    );
    final locationText = initiate.headers['location'];
    final location = locationText == null ? null : Uri.tryParse(locationText);
    if (location == null || !_trustedUploadLocation(location)) {
      throw const DriveApiException(DriveApiFailure.unavailable);
    }
    late final DriveHttpResponse uploaded;
    try {
      uploaded = await _send(
        'PUT',
        location,
        body: bytes,
        headers: {
          HttpHeaders.contentTypeHeader: mimeType,
          HttpHeaders.contentLengthHeader: bytes.length.toString(),
        },
        resultMayBeCommitted: true,
      );
    } on DriveHttpTransportException {
      throw const DriveApiException(DriveApiFailure.uncertainResult);
    }
    return _file(_jsonObject(uploaded));
  }

  @override
  Future<List<int>> downloadFile(String fileId) async {
    final response = await _send(
      'GET',
      _api
          .resolve('files/${Uri.encodeComponent(fileId)}')
          .replace(queryParameters: const {'alt': 'media'}),
      maxResponseBytes: 128 * 1024 * 1024,
    );
    return response.body;
  }

  @override
  Future<List<DriveFileRecord>> listBackupFiles() async {
    final files = <DriveFileRecord>[];
    String? pageToken;
    final seenTokens = <String>{};
    do {
      final parameters = <String, String>{
        'q': "appProperties has { key='format' and value='ExpenseTracker-V2-backup' } and trashed=false",
        'fields': 'nextPageToken,files(id,mimeType,size,appProperties,trashed)',
        'pageSize': '1000',
        if (pageToken != null) 'pageToken': pageToken,
      };
      final response = await _send(
        'GET',
        _api.resolve('files').replace(queryParameters: parameters),
      );
      final json = _jsonObject(response);
      final rows = json['files'];
      if (rows is! List) {
        throw const DriveApiException(DriveApiFailure.unavailable);
      }
      files.addAll(
        rows.map((row) {
          if (row is! Map<String, Object?>) {
            throw const DriveApiException(DriveApiFailure.unavailable);
          }
          return _file(row);
        }),
      );
      if (files.length > 10000) {
        throw const DriveApiException(DriveApiFailure.unavailable);
      }
      final next = json['nextPageToken'];
      if (next != null &&
          (next is! String || next.isEmpty || !seenTokens.add(next))) {
        throw const DriveApiException(DriveApiFailure.unavailable);
      }
      pageToken = next as String?;
    } while (pageToken != null);
    return files;
  }

  @override
  Future<void> deleteFile(String fileId) async {
    await _send('DELETE', _api.resolve('files/${Uri.encodeComponent(fileId)}'));
  }

  Future<DriveHttpResponse> _send(
    String method,
    Uri uri, {
    List<int> body = const [],
    Map<String, String> headers = const {},
    int maxResponseBytes = 1024 * 1024,
    bool allowNotFound = false,
    bool resultMayBeCommitted = false,
  }) async {
    late final String token;
    try {
      token = await tokens.accessToken();
    } on DriveApiException {
      rethrow;
    } on Object {
      throw const DriveApiException(DriveApiFailure.authenticationRequired);
    }
    if (token.isEmpty ||
        token.length > 8192 ||
        token.contains(RegExp(r'[\r\n]'))) {
      throw const DriveApiException(DriveApiFailure.authenticationRequired);
    }
    late final DriveHttpResponse response;
    try {
      response = await transport.send(
        DriveHttpRequest(
          method: method,
          uri: uri,
          headers: {
            HttpHeaders.authorizationHeader: 'Bearer $token',
            HttpHeaders.acceptHeader: 'application/json',
            ...headers,
          },
          body: body,
          maxResponseBytes: maxResponseBytes,
        ),
        timeout: timeout,
      );
    } on DriveHttpTransportException {
      if (resultMayBeCommitted) rethrow;
      throw const DriveApiException(DriveApiFailure.unavailable);
    }
    if (response.statusCode >= 200 && response.statusCode < 300)
      return response;
    if (allowNotFound && response.statusCode == HttpStatus.notFound) {
      return response;
    }
    if (resultMayBeCommitted &&
        (response.statusCode == HttpStatus.permanentRedirect ||
            response.statusCode == HttpStatus.requestTimeout ||
            response.statusCode >= 500)) {
      throw const DriveApiException(DriveApiFailure.uncertainResult);
    }
    throw DriveApiException(_failure(response));
  }
}

Map<String, Object?> _jsonObject(DriveHttpResponse response) {
  try {
    final value = jsonDecode(utf8.decode(response.body));
    if (value is Map<String, Object?>) return value;
  } on FormatException {
    // Mapped below without exposing provider response data.
  }
  throw const DriveApiException(DriveApiFailure.unavailable);
}

DriveFileRecord _file(Map<String, Object?> json) {
  final id = json['id'];
  final mimeType = json['mimeType'];
  final size = json['size'];
  final properties = json['appProperties'];
  final trashed = json['trashed'];
  final parsedSize = switch (size) {
    String value => int.tryParse(value),
    int value => value,
    _ => null,
  };
  if (id is! String ||
      mimeType is! String ||
      parsedSize == null ||
      parsedSize < 0 ||
      properties is! Map<String, Object?> ||
      trashed is! bool) {
    throw const DriveApiException(DriveApiFailure.unavailable);
  }
  final stringProperties = <String, String>{};
  for (final entry in properties.entries) {
    if (entry.value is! String) {
      throw const DriveApiException(DriveApiFailure.unavailable);
    }
    stringProperties[entry.key] = entry.value! as String;
  }
  return DriveFileRecord(
    id: id,
    mimeType: mimeType,
    byteLength: parsedSize,
    appProperties: stringProperties,
    trashed: trashed,
  );
}

DriveApiFailure _failure(DriveHttpResponse response) {
  if (response.statusCode == HttpStatus.unauthorized) {
    return DriveApiFailure.authenticationRequired;
  }
  if (response.statusCode == HttpStatus.conflict)
    return DriveApiFailure.conflict;
  if (response.statusCode == HttpStatus.tooManyRequests) {
    return DriveApiFailure.throttled;
  }
  if (response.statusCode >= 500) return DriveApiFailure.unavailable;
  if (response.statusCode == HttpStatus.forbidden) {
    final reasons = _errorReasons(response.body);
    if (reasons.any(
      (reason) => const {
        'storageQuotaExceeded',
        'teamDriveFileLimitExceeded',
      }.contains(reason),
    )) {
      return DriveApiFailure.quotaExceeded;
    }
    if (reasons.any(
      (reason) => const {
        'rateLimitExceeded',
        'userRateLimitExceeded',
        'sharingRateLimitExceeded',
      }.contains(reason),
    )) {
      return DriveApiFailure.throttled;
    }
    return DriveApiFailure.permissionDenied;
  }
  return DriveApiFailure.unavailable;
}

Set<String> _errorReasons(List<int> body) {
  try {
    final value = jsonDecode(utf8.decode(body));
    if (value is! Map) return const {};
    final error = value['error'];
    if (error is! Map) return const {};
    final errors = error['errors'];
    if (errors is! List) return const {};
    return {
      for (final item in errors)
        if (item is Map && item['reason'] is String) item['reason'] as String,
    };
  } on FormatException {
    return const {};
  }
}

bool _trustedUploadLocation(Uri uri) {
  final host = uri.host.toLowerCase();
  return uri.scheme == 'https' &&
      uri.userInfo.isEmpty &&
      uri.fragment.isEmpty &&
      (host == 'googleapis.com' || host.endsWith('.googleapis.com'));
}
