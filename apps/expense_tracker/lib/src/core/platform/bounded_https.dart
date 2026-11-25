import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../diagnostics/app_fault.dart';

/// An answer longer than the request allows: a broken or hostile server's,
/// refused before it fills the phone's memory or storage.
final class AnswerTooLarge extends HttpException {
  AnswerTooLarge(this.limit, Uri uri)
    : super('The answer is over $limit bytes.', uri: uri);

  /// The most the request allowed, in bytes.
  final int limit;
}

/// A server that answered with [status] where the request wants 200: the
/// error log keeps the status, never the server's words or the address.
final class HttpRefused extends HttpException implements AppFault {
  HttpRefused(this.status) : super('HTTP $status');

  final int status;

  @override
  String toString() => 'HTTP $status';
}

/// A redirect the request does not allow: to plain `http`, to a host it
/// does not name, or one too many.
final class RedirectRefused extends HttpException {
  RedirectRefused(Uri to) : super('A redirect was refused.', uri: to);
}

/// The one way the app's own requests outside the market feed (the update
/// feed and its download, Google Drive) are opened and read, after the
/// market transport's pattern (`io_transports.dart`): a redirect is
/// followed by hand, for a GET only, at most [maxRedirects] times, and
/// only to an `https` address [open]'s `allowed` names; and a body is
/// read only up to a limit ([text], [save]).
abstract final class BoundedHttps {
  /// The most redirects one request follows.
  static const maxRedirects = 5;

  /// The only headers sent on to another origin than the one first asked:
  /// what to answer with and which part. Every other one (Authorization,
  /// Cookie, Proxy-Authorization, any key) stays with the first origin.
  static const _carried = {'accept', 'accept-encoding', 'user-agent', 'range'};

  /// The headers of [headers] sent to a hop: all of them to the origin
  /// first asked ([sameOrigin]), only [_carried] ones to any other.
  static Map<String, String> headersFor(
    Map<String, String> headers, {
    required bool sameOrigin,
  }) => {
    for (final MapEntry(key: name, :value) in headers.entries)
      if (sameOrigin || _carried.contains(name.toLowerCase())) name: value,
  };

  /// Sends [method] to [url] with [headers] and the body [send] writes.
  /// A GET's redirect is followed while it goes to `https` and [allowed]
  /// takes its address; any other method's redirect is answered as it is
  /// (Drive's 308 to a resumable upload says how much arrived). [wait]
  /// bounds each answer's first byte.
  static Future<HttpClientResponse> open(
    HttpClient client,
    String method,
    Uri url, {
    required bool Function(Uri to) allowed,
    Map<String, String> headers = const {},
    Future<void> Function(HttpClientRequest request)? send,
    Duration? wait,
  }) async {
    var at = url;
    for (var hops = 0; ; hops++) {
      final request = await client.openUrl(method, at);
      request.followRedirects = false;
      headersFor(
        headers,
        sameOrigin: at.origin == url.origin,
      ).forEach(request.headers.set);
      if (send != null) await send(request);
      final closing = request.close();
      final response = wait == null
          ? await closing
          : await closing.timeout(wait);
      final location = response.headers.value(HttpHeaders.locationHeader);
      if (method != 'GET' ||
          !_redirects.contains(response.statusCode) ||
          location == null) {
        return response;
      }
      final to = at.resolve(location);
      // What was said with the redirect is not read.
      unawaited(response.drain<void>().catchError((Object _) {}));
      if (hops >= maxRedirects || to.scheme != 'https' || !allowed(to)) {
        throw RedirectRefused(to);
      }
      at = to;
    }
  }

  static const _redirects = {301, 302, 303, 307, 308};

  /// [response]'s body as UTF-8 words, refused past [limit] bytes; [stall]
  /// gives up on a body that stops arriving that long.
  static Future<String> text(
    HttpClientResponse response,
    int limit, {
    required Uri uri,
    Duration? stall,
  }) async {
    if (response.contentLength > limit) throw AnswerTooLarge(limit, uri);
    final bytes = BytesBuilder(copy: false);
    await for (final chunk
        in stall == null ? response : response.timeout(stall)) {
      bytes.add(chunk);
      if (bytes.length > limit) throw AnswerTooLarge(limit, uri);
    }
    return utf8.decode(bytes.takeBytes());
  }

  /// Writes [response]'s body into [into], refused past [limit] bytes,
  /// saying how much has arrived; [stall] gives up on a body that stops
  /// arriving that long. A refused or broken body leaves [into] partly
  /// written: the caller writes to a part file and deletes it.
  static Future<void> save(
    HttpClientResponse response,
    File into,
    int limit, {
    required Uri uri,
    Duration? stall,
    void Function(int received)? progress,
  }) async {
    if (response.contentLength > limit) throw AnswerTooLarge(limit, uri);
    final sink = into.openWrite();
    var received = 0;
    try {
      await for (final chunk
          in stall == null ? response : response.timeout(stall)) {
        received += chunk.length;
        if (received > limit) throw AnswerTooLarge(limit, uri);
        sink.add(chunk);
        progress?.call(received);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
  }
}
