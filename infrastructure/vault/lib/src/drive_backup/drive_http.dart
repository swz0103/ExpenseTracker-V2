import 'dart:io';
import 'dart:typed_data';

/// One HTTP exchange with Google Drive, kept small enough to fake in tests.
final class DriveRequest {
  DriveRequest({
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

final class DriveResponse {
  DriveResponse({
    required this.statusCode,
    Map<String, String> headers = const {},
    List<int> body = const [],
  }) : headers = Map.unmodifiable({
         for (final entry in headers.entries)
           entry.key.toLowerCase(): entry.value,
       }),
       body = List.unmodifiable(body);

  final int statusCode;

  /// Header names are lower case.
  final Map<String, String> headers;
  final List<int> body;
}

/// The request may or may not have reached the server: no connection, a
/// timeout, a cut stream or an oversized response.
final class DriveTransportException implements Exception {
  const DriveTransportException();

  @override
  String toString() => 'DriveTransportException';
}

abstract interface class DriveTransport {
  /// [timeout] bounds each phase of one request; uploads send one chunk
  /// per request, so a slow link never needs the whole file in one window
  /// (health check G8-11).
  Future<DriveResponse> send(DriveRequest request, {required Duration timeout});
}

/// dart:io transport: no redirects, capped responses, no shared client.
final class IoDriveTransport implements DriveTransport {
  const IoDriveTransport();

  @override
  Future<DriveResponse> send(
    DriveRequest request, {
    required Duration timeout,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = timeout
      ..autoUncompress = true;
    try {
      final outgoing = await client
          .openUrl(request.method, request.uri)
          .timeout(timeout);
      outgoing.followRedirects = false;
      outgoing.contentLength = request.body.length;
      request.headers.forEach(outgoing.headers.set);
      if (request.body.isNotEmpty) outgoing.add(request.body);
      final incoming = await outgoing.close().timeout(timeout);
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in incoming.timeout(timeout)) {
        if (bytes.length + chunk.length > request.maxResponseBytes) {
          throw const DriveTransportException();
        }
        bytes.add(chunk);
      }
      final headers = <String, String>{};
      incoming.headers.forEach((name, values) {
        headers[name] = values.join(',');
      });
      return DriveResponse(
        statusCode: incoming.statusCode,
        headers: headers,
        body: bytes.takeBytes(),
      );
    } on DriveTransportException {
      rethrow;
    } on Object {
      throw const DriveTransportException();
    } finally {
      client.close(force: true);
    }
  }
}
