import 'package:flutter/services.dart';

import 'platform_channel.dart';

/// Reads a QR code with Google's code scanner (`ScanPart.kt`); null when
/// the person closes it. The first scan on a phone may wait while Play
/// services fetches the scanner. A problem is thrown as words to show.
Future<String?> androidScanQr() async {
  try {
    return await platformChannel.invokeMethod<String>('scanQr');
  } on PlatformException catch (error) {
    throw ScanProblem(switch (error.code) {
      'install' => '無法下載掃描器：請確認 Google Play 服務已開啟並更新',
      'busy' => '掃描器已經開著',
      _ => '沒有掃到，請再試一次',
    });
  }
}

/// Why a scan did not work, in words for the person.
final class ScanProblem implements Exception {
  const ScanProblem(this.words);

  final String words;

  @override
  String toString() => words;
}
