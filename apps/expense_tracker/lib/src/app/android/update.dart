import 'dart:convert';
import 'dart:io';

import '../../features/settings/model/app_update.dart';
import 'channel.dart';

/// [UpdatePort] on the phone: dart:io for the two files, and Android's
/// installer through `UpdatePart.kt`, which checks the SHA-256 first.
final class AndroidUpdatePort implements UpdatePort {
  const AndroidUpdatePort();

  HttpClient _client() => HttpClient()
    ..connectionTimeout = const Duration(seconds: 20)
    ..idleTimeout = const Duration(seconds: 20)
    ..userAgent = 'ExpenseTracker';

  @override
  Future<String> fetch(Uri url) async {
    final client = _client();
    try {
      final request = await client.getUrl(url);
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) {
        throw HttpException('GitHub answered ${response.statusCode}');
      }
      return body;
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<void> download(
    Uri url,
    File into,
    void Function(int received) progress,
  ) async {
    final client = _client();
    final part = File('${into.path}.part');
    try {
      final request = await client.getUrl(url);
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (response.statusCode != 200) {
        throw HttpException('GitHub answered ${response.statusCode}');
      }
      final sink = part.openWrite();
      var received = 0;
      try {
        // A download that stops arriving for a minute is given up on.
        await for (final chunk in response.timeout(
          const Duration(minutes: 1),
        )) {
          sink.add(chunk);
          received += chunk.length;
          progress(received);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      await part.rename(into.path);
    } finally {
      client.close(force: true);
      if (part.existsSync()) await part.delete();
    }
  }

  @override
  Future<UpdateInstall> install(File apk, String sha256) async {
    final outcome = await platformChannel.invokeMethod<String>('installApk', {
      'path': apk.path,
      'sha256': sha256,
    });
    return UpdateInstall.values.firstWhere(
      (o) => o.name == outcome,
      orElse: () => throw StateError('Unknown install outcome: $outcome'),
    );
  }
}
