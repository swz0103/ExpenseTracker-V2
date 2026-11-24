import 'dart:io';

import '../../core/platform/bounded_https.dart';
import '../../features/settings/model/app_update.dart';
import 'platform_channel.dart';

/// [UpdatePort] on the phone: dart:io for the two files, and Android's
/// installer through `UpdateHandler.kt`, which checks the file first (size,
/// SHA-256, package name, version code, signing certificate). Only the
/// sideload build has that handler; the play build never makes this port
/// (distribution.dart).
final class AndroidUpdatePort implements UpdatePort {
  const AndroidUpdatePort();

  HttpClient _client() => HttpClient()
    ..connectionTimeout = const Duration(seconds: 20)
    ..idleTimeout = const Duration(seconds: 20)
    ..userAgent = 'ExpenseTracker';

  /// Where GitHub may send the update's two files on: its own hosts,
  /// over `https` ([BoundedHttps.open] refuses any other redirect).
  static bool _github(Uri to) =>
      to.host == 'github.com' ||
      to.host.endsWith('.github.com') ||
      to.host.endsWith('.githubusercontent.com');

  @override
  Future<String> fetch(Uri url) async {
    final client = _client();
    try {
      final response = await BoundedHttps.open(
        client,
        'GET',
        url,
        allowed: _github,
        wait: const Duration(seconds: 30),
      );
      // The status first: a failure's body is not read at all.
      if (response.statusCode != 200) {
        throw HttpException('GitHub answered ${response.statusCode}');
      }
      return await BoundedHttps.text(
        response,
        maxUpdateInfoBytes,
        uri: url,
        stall: const Duration(seconds: 30),
      );
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
      final response = await BoundedHttps.open(
        client,
        'GET',
        url,
        allowed: _github,
        wait: const Duration(seconds: 30),
      );
      if (response.statusCode != 200) {
        throw HttpException('GitHub answered ${response.statusCode}');
      }
      // A download that stops arriving for a minute is given up on.
      await BoundedHttps.save(
        response,
        part,
        maxApkBytes,
        uri: url,
        stall: const Duration(minutes: 1),
        progress: progress,
      );
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
      'maxBytes': maxApkBytes,
    });
    return UpdateInstall.values.firstWhere(
      (o) => o.name == outcome,
      orElse: () => throw StateError('Unknown install outcome: $outcome'),
    );
  }
}
